import Foundation
import MotionCore
@testable import MotionEditor
import MotionSwiftUI
import Testing

private let rigSource = """
  import React, {useLayoutEffect} from 'react';
  import {registerRoot, Composition, useCurrentFrame} from 'remotion';
  import {ThreeCanvas} from '@remotion/three';
  import {useThree} from '@react-three/fiber';
  const Rig = ({frame}: {frame: number}) => {
    const camera = useThree(state => state.camera);
    useLayoutEffect(() => {
      camera.position.set(frame / 10, 1, 8);
      camera.lookAt(0, 0, 0);
      camera.fov = 50;
    }, [camera, frame]);
    return null;
  };
  const Demo = () => {
    const frame = useCurrentFrame();
    return <ThreeCanvas width={160} height={90}>
      <Rig frame={frame} />
      <ambientLight intensity={1} />
      <mesh rotation={[0, 0, 0]}>
        <boxGeometry />
        <meshStandardMaterial color="#ff0000" />
      </mesh>
    </ThreeCanvas>;
  };
  registerRoot(() => <Composition id="Demo" component={Demo} width={160} height={90} fps={30} durationInFrames={30} />);
  """

private func scene(in node: RenderNode) -> Scene3D? { node.scene ?? node.children.compactMap { scene(in: $0) }.first }

@Test
func scenePreviewOverridesPatchCameraAndStampedObjects() throws {
  for euler in [[0.3, -1.2, 0.7], [0.0, 0.0, 0.0], [-2.0, 0.4, 3.0]] {
    let back = Scene3D.euler(quaternion: Scene3D.quaternion(euler: euler))
    for index in 0..<3 { #expect(abs(back[index] - euler[index]) < 1e-9) }
  }
  let json = """
    {"width":160,"height":90,"dpr":[1,2],"flat":false,"background":null,"fog":null,
     "camera":{"fov":50,"near":0.1,"far":100,"zoom":1,"aspect":null,"position":[0,0,5],"quaternion":[0,0,0,1]},
     "objects":[{"kind":"mesh","position":[0,0,0],"quaternion":[0,0,0,1],"scale":[1,1,1],"visible":true,"renderOrder":0,
       "geometry":{"type":"box","args":[]},"material":null,"light":null,"src":null,"source":"a.tsx:3:4","children":[]}],
     "editor":[{"source":"a.tsx:1:1","type":"ThreeCanvas","properties":{"cameraPositionX":0}}]}
    """
  let original = try Scene3D.decode(json)
  let node = RenderNode(type: "ms-three", style: [:], source: "a.tsx:1:1", scene: original)
  let patched = try #require(node.applying([
    "a.tsx:1:1": ["cameraPositionX": .number(2), "cameraFov": .number(30)],
    "a.tsx:3:4": ["rotationY": .number(.pi / 2)],
  ]).scene)
  #expect(patched.camera.position == [2, 0, 5])
  #expect(patched.camera.fov == 30)
  #expect(abs(Scene3D.euler(quaternion: patched.objects[0].quaternion)[1] - .pi / 2) < 1e-9)
  #expect(patched.editor?.first?.properties["cameraPositionX"] == .number(2))
  #expect(node.applying(["a.tsx:1:1": ["cameraPositionX": .number(2)]]).style.isEmpty)
}

@Test @MainActor
func addCameraBakesCodeRigAndCanvasDragsEditCameraAndObjects() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("camera-editor-\(UUID())")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try rigSource.write(to: directory.appendingPathComponent("index.tsx"), atomically: true, encoding: .utf8)
  let model = EditorModel(project: directory, entry: "index.tsx", configuration: .init(backend: .gpu))
  await model.open(compositionID: "Demo")
  #expect(model.status == .idle)
  for _ in 0..<200 where model.player.displayedFrame == nil { try await Task.sleep(for: .milliseconds(10)) }
  model.observeTimelineFrame()
  let camera = try #require(model.cameraTrack)
  #expect(!model.hasCameraKeyframes)
  #expect(model.cameraState?.position.z == 8)

  // Dragging a camera aimed by arbitrary code adds it to the timeline and applies the drag, one step.
  model.selectCamera()
  for _ in 0..<200 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.cameraMode == .bake)
  model.scrub(to: 10)
  for _ in 0..<200 where model.player.displayedFrame?.frame != 10 { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.beginThreeDrag(.orbit))
  model.updateThreeDrag(dx: 80, dy: 0)
  await model.endThreeDrag()
  #expect(model.hasCameraKeyframes)
  #expect(model.cameraTrack?.keyframes["cameraPositionX"]?.map(\.frame) == [0, 10, 20, 29])
  let baked = try #require(scene(in: try await model.player.render(frame: 10).tree))
  #expect(abs(baked.camera.position[0] - 1) > 0.5)
  #expect(model.undoActionName == "Orbit Camera")
  await model.undo()
  #expect(model.files["index.tsx"] == rigSource)
  #expect(!model.hasCameraKeyframes)

  // Orbiting at the playhead writes position and rotation keyframes in one step.
  model.selectCamera()
  for _ in 0..<200 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  model.scrub(to: 10)
  for _ in 0..<200 where model.player.displayedFrame?.frame != 10 { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.beginThreeDrag(.orbit))
  model.updateThreeDrag(dx: 80, dy: 0)
  #expect(model.threePreview["cameraPositionX"].map { abs($0 - 1) > 0.5 } == true)
  await model.endThreeDrag()
  let orbited = try #require(scene(in: try await model.player.render(frame: 10).tree))
  #expect(abs(orbited.camera.position[0] - 1) > 0.5)
  #expect(model.cameraTrack?.keyframes["cameraRotationY"]?.contains { $0.frame == 10 } == true)
  #expect(model.undoActionName == "Orbit Camera")

  // Rotating a mesh writes its static rotation.
  let mesh = try #require(model.objectTracks.first { $0.label == "mesh" })
  model.selectTrack(mesh)
  for _ in 0..<200 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.beginThreeDrag(.orbit) == false)
  #expect(model.beginThreeDrag(.rotate))
  model.updateThreeDrag(dx: 50, dy: 0)
  await model.endThreeDrag()
  #expect(model.files["index.tsx"]?.contains("rotation={[0, 0.5, 0]}") == true)

  for _ in 0..<3 { await model.undo() }
  #expect(model.files["index.tsx"] == rigSource)
  #expect(model.canRedo)
  #expect(camera.src == model.cameraTrack?.src)
}

private let literalRigSource = """
  import React, {useLayoutEffect} from 'react';
  import {registerRoot, Composition, useCurrentFrame, interpolate, Easing} from 'remotion';
  import {ThreeCanvas} from '@remotion/three';
  import {useThree} from '@react-three/fiber';
  type Key = {frame: number; position: [number, number, number]; target: [number, number, number]; fov: number};
  const keys: Key[] = [
    {frame: 0, position: [0, 0, 8], target: [0, 0, 0], fov: 50},
    {frame: 30, position: [6, 0, 6], target: [0, 0, 0], fov: 40},
  ];
  const ease = Easing.inOut(Easing.cubic);
  const lerp = (frame: number, pick: (key: Key) => number) =>
    interpolate(frame, keys.map(k => k.frame), keys.map(pick), {easing: ease, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const CameraRig = ({frame}: {frame: number; keys: Key[]}) => {
    const camera = useThree(state => state.camera);
    useLayoutEffect(() => {
      camera.position.set(lerp(frame, k => k.position[0]), lerp(frame, k => k.position[1]), lerp(frame, k => k.position[2]));
      camera.lookAt(lerp(frame, k => k.target[0]), lerp(frame, k => k.target[1]), lerp(frame, k => k.target[2]));
      camera.fov = lerp(frame, k => k.fov);
    }, [camera, frame]);
    return null;
  };
  const Demo = () => {
    const frame = useCurrentFrame();
    return <ThreeCanvas width={160} height={90}>
      <CameraRig frame={frame} keys={keys} />
      <ambientLight intensity={1} />
      <mesh><boxGeometry /><meshBasicMaterial color="#ff0000" /></mesh>
    </ThreeCanvas>;
  };
  registerRoot(() => <Composition id="Demo" component={Demo} width={160} height={90} fps={30} durationInFrames={40} />);
  """

@Test @MainActor
func cameraDragsEditLiteralRigKeysInCode() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("camera-rig-\(UUID())")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try literalRigSource.write(to: directory.appendingPathComponent("index.tsx"), atomically: true, encoding: .utf8)
  let model = EditorModel(project: directory, entry: "index.tsx", configuration: .init(backend: .gpu))
  await model.open(compositionID: "Demo")
  for _ in 0..<200 where model.player.displayedFrame == nil { try await Task.sleep(for: .milliseconds(10)) }
  model.observeTimelineFrame()
  for _ in 0..<300 where model.cameraRig == nil { try await Task.sleep(for: .milliseconds(10)) }
  let rig = try #require(model.cameraRig)
  #expect(rig.keys.map(\.frame) == [0, 30])
  model.selectCamera()
  for _ in 0..<200 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.cameraMode == .rig)
  #expect(model.cameraKeyFrames == [0, 30])

  // Orbiting at frame 30 rewrites that key: the rig keeps looking at its target.
  model.scrub(to: 30)
  for _ in 0..<200 where model.player.displayedFrame?.frame != 30 { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.beginThreeDrag(.orbit))
  model.updateThreeDrag(dx: 60, dy: 0)
  let preview = try #require(model.cameraState?.position)
  await model.endThreeDrag()
  #expect(model.undoActionName == "Orbit Camera")
  let edited = try #require(model.cameraRig?.keys.last)
  #expect(edited.frame == 30 && edited.target == [0, 0, 0] && edited.fov == 40)
  #expect(abs(edited.position[0] - preview.x) < 0.01 && abs(edited.position[2] - preview.z) < 0.01)
  #expect(!model.hasCameraKeyframes)
  let rendered = try #require(scene(in: try await model.player.render(frame: 30).tree))
  #expect(abs(rendered.camera.position[0] - preview.x) < 0.01)

  // A pan between keys inserts a key at the playhead, in order, and moves the target along.
  model.scrub(to: 15)
  for _ in 0..<200 where model.player.displayedFrame?.frame != 15 { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.beginThreeDrag(.pan))
  model.updateThreeDrag(dx: 0, dy: -20)
  await model.endThreeDrag()
  let inserted = try #require(model.cameraRig)
  #expect(inserted.keys.map(\.frame) == [0, 15, 30])
  // Panning grabs the scene: dragging up lowers the camera and its target together.
  #expect(inserted.keys[1].target[1] < 0 && abs(inserted.keys[1].target[1] - inserted.keys[1].position[1]) < 1e-3)
  #expect(abs(inserted.keys[1].fov - 45) < 0.01)

  await model.deleteCameraRigKey(at: 15)
  #expect(model.cameraRig?.keys.map(\.frame) == [0, 30])

  // Keyboard flight (WASD) previews live and saves the burst as one rig edit; the target moves along.
  model.scrub(to: 0)
  for _ in 0..<200 where model.player.displayedFrame?.frame != 0 { try await Task.sleep(for: .milliseconds(10)) }
  for _ in 0..<3 { model.flyCamera(move: SIMD3(0, 0, 1)) }
  #expect(model.isGesturing && (model.threePreview["cameraPositionZ"] ?? 8) < 8)
  for _ in 0..<200 where model.isGesturing || model.status != .idle { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.undoActionName == "Move Camera")
  // The reload re-reads the rig after the status returns to idle.
  for _ in 0..<200 where model.cameraRig?.keys.first?.position[2] == 8 { try await Task.sleep(for: .milliseconds(10)) }
  let flown = try #require(model.cameraRig?.keys.first)
  #expect(flown.position[2] < 8 && flown.target[2] < 0)
  for _ in 0..<4 { await model.undo() }
  #expect(model.files["index.tsx"] == literalRigSource)
}
