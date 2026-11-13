import Foundation
import MotionCore
import MotionEditor
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func showcase3DScenesCompileAndRenderEveryScene() async throws {
  let player = MotionPlayer(configuration: .init(scale: 0.5, backend: .gpu))
  await player.load(Showcase3D.source)
  #expect(player.status == .ready)
  #expect(Set(player.compositions.map(\.id)) == Set(Showcase3D.scenes.map(\.id)))
  for scene in Showcase3D.scenes {
    player.select(compositionID: scene.id)
    let rendered = try await player.render(frame: 30)
    #expect(rendered.image.width == 320 && rendered.image.height == 180, "\(scene.id)")
    let canvas = try #require(rendered.tree.children.first?.children.first, "\(scene.id)")
    #expect(canvas.type == "ms-three" && canvas.scene != nil, "\(scene.id)")
    #expect(!scene.features.isEmpty)
  }
}

@Test @MainActor
func showcase3DEditorKeepsSceneTracksAndWorkingCopyEdits() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("three-editor-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let example = ShowcaseExample.project(Showcase3D.project, entry: ShowcaseDefaults.entry)
  let location = try example.prepare(root: directory)
  let model = EditorModel(project: location.project, entry: location.entry, configuration: .init(scale: 0.5, backend: .gpu))
  for scene in Showcase3D.scenes {
    await model.open(compositionID: scene.id)
    #expect(model.status == .idle, "\(scene.id)")
    for _ in 0..<200 where model.player.displayedFrame == nil { try await Task.sleep(for: .milliseconds(10)) }
    model.observeTimelineFrame()
    let rendered = try await model.player.render(frame: 20)
    #expect(rendered.tree.threeEditorElements.contains { $0.type == "mesh" || $0.type == "primitive" })
    #expect(model.timelineTracks.contains { $0.label == "mesh" || $0.label == "primitive" })
    #expect(model.timelineTracks.contains { $0.label.hasSuffix("Light") })
    #expect(!model.timelineTracks.contains { $0.label.hasSuffix("Geometry") })
  }
  await model.open(compositionID: "GeometryLab")
  let track = try #require(model.timelineTracks.first { $0.label == "spotLight" })
  model.selectTrack(track)
  for _ in 0..<200 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.styles?.isThree == true)
  let file = try #require(model.files.keys.first { $0.hasSuffix("GeometryLab.tsx") })
  let original = try #require(model.files[file])
  await model.setStyle("intensity", .number(20))
  let dimmed = try await model.player.render(frame: 0)
  #expect(dimmed.tree.threeEditorElements.first { $0.source == track.src }?.properties["intensity"] == .number(20))
  await model.undo()
  #expect(model.files[file] == original)
  await model.setKeyframe(of: track.src, key: "intensity", frame: 0, value: 10)
  await model.setKeyframe(of: track.src, key: "intensity", frame: 20, value: 50)
  let middle = try await model.player.render(frame: 10)
  #expect(middle.tree.threeEditorElements.first { $0.source == track.src }?.properties["intensity"] == .number(30))
  // Editing a keyframed 3D property saves at the playhead and never sends it as a CSS override.
  model.scrub(to: 10)
  await model.setStyle("intensity", .number(35))
  let edited = try await model.player.render(frame: 10)
  #expect(edited.tree.threeEditorElements.first { $0.source == track.src }?.properties["intensity"] == .number(35))
  #expect(model.player.previewOverrides.isEmpty)
  await model.undo()
  await model.undo()
  await model.undo()
  #expect(model.files[file] == original)
  await model.setTiming(of: track.src, start: 5, duration: 30)
  let hidden = try await model.player.render(frame: 0)
  #expect(!hidden.tree.threeEditorElements.contains { $0.source == track.src })
  let visible = try await model.player.render(frame: 10)
  #expect(visible.tree.threeEditorElements.contains { $0.source == track.src })
  await model.undo()
  #expect(model.files[file] == original)
  #expect(try String(contentsOf: Showcase3D.project.appendingPathComponent(file), encoding: .utf8) == original)
}

@Test @MainActor
func threeEditorKeyframesReachNativeTransformsMaterialsAndCamera() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("three-properties-\(UUID())")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let source = """
    import React from 'react';
    import {registerRoot, Composition} from 'remotion';
    import {ThreeCanvas} from '@remotion/three';
    const Demo = () => <ThreeCanvas width={160} height={90} camera={{position: [0, 0, 8], fov: 50}}>
      <ambientLight intensity={1} />
      <mesh position={[0, 0, 0]}>
        <boxGeometry />
        <meshStandardMaterial color="#ff0000" roughness={0.5} />
      </mesh>
    </ThreeCanvas>;
    registerRoot(() => <Composition id="Demo" component={Demo} width={160} height={90} fps={30} durationInFrames={30} />);
    """
  try source.write(to: directory.appendingPathComponent("index.tsx"), atomically: true, encoding: .utf8)
  let model = EditorModel(project: directory, entry: "index.tsx", configuration: .init(backend: .gpu))
  await model.open(compositionID: "Demo")
  #expect(model.status == .idle)
  for (label, key, values) in [("mesh", "positionX", [0.0, 2.0]),
                               ("meshStandardMaterial", "roughness", [0.2, 0.8]),
                               ("ThreeCanvas", "cameraFov", [30.0, 60.0])] {
    let track = try #require(model.objectTracks.first { $0.label == label })
    await model.setKeyframe(of: track.src, key: key, frame: 0, value: values[0])
    await model.setKeyframe(of: track.src, key: key, frame: 10, value: values[1])
  }
  func scene(in node: RenderNode) -> Scene3D? { node.scene ?? node.children.compactMap { scene(in: $0) }.first }
  let rendered = try await model.player.render(frame: 5)
  let middle = try #require(scene(in: rendered.tree))
  #expect(middle.camera.fov == 45)
  let mesh = try #require(middle.objects.first { $0.kind == "mesh" })
  #expect(mesh.position == [1, 0, 0])
  #expect(abs((mesh.material?.roughness ?? 0) - 0.5) < 0.0001)
  // Capture uses the evaluated camera at the playhead, including existing keyframes.
  let cameraTrack = try #require(model.objectTracks.first { $0.label == "ThreeCanvas" })
  model.selectTrack(cameraTrack)
  for _ in 0..<200 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  model.scrub(to: 5)
  await model.captureKeyframe()
  #expect(model.selectedTrack?.keyframes["cameraFov"]?.contains { $0.frame == 5 && $0.value == 45 } == true)
  #expect(model.objectTracks.first { $0.label == "mesh" }?.reason == nil)
  for _ in 0..<7 { await model.undo() }
  #expect(model.files["index.tsx"] == source)
}
