import CryptoKit
import Foundation
import MotionCompiler
import MotionCore
@testable import MotionRender
import MotionRuntime
import MotionSwiftUI
import SkiaKit
import Testing

private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent()
private let threeProject = repository.appendingPathComponent("tests/three")

private struct GeometryCase: Decodable {
  let type: String
  let args: [Double]
  let vertices: Int
  let indices: Int?
  let sha256: String
}

private func bytes<T>(_ values: [T]) -> Data { values.withUnsafeBytes { Data($0) } }

/// Native generators must reproduce three.js r187 geometry buffers bit for bit.
@Test func geometryGeneratorsMatchThreeJSBuffers() throws {
  let data = try Data(contentsOf: threeProject.appendingPathComponent("geometry-hashes.json"))
  struct File: Decodable { let geometries: [GeometryCase] }
  for item in try JSONDecoder().decode(File.self, from: data).geometries {
    let mesh = try GeometryFactory.make(Scene3D.Geometry(type: item.type, args: item.args))
    var hash = SHA256()
    hash.update(data: bytes(mesh.positions))
    hash.update(data: bytes(mesh.normals))
    if let indices = mesh.indices { hash.update(data: bytes(indices)) }
    let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
    #expect(mesh.vertexCount == item.vertices, "\(item.type) \(item.args)")
    #expect(mesh.indices?.count == item.indices, "\(item.type) \(item.args)")
    #expect(digest == item.sha256, "\(item.type) \(item.args) buffers differ from three.js")
  }
}

@Test func matrixMathFollowsThreeJS() {
  let world = M4.compose(position: [1, 2, 3], quaternion: [0.1, 0.2, 0.3, (1 - 0.14).squareRoot()], scale: [2, 1, 0.5])
  let identity = world * world.inverted()
  for (index, value) in identity.e.enumerated() {
    #expect(abs(value - M4.identity.e[index]) < 1e-12)
  }
  let mirrored = M4.compose(position: [0, 0, 0], quaternion: [0, 0, 0, 1], scale: [-1, 1, 1])
  #expect(mirrored.determinant < 0)
  #expect(world.transformPoint(SIMD3(0, 0, 0)) == SIMD3(1, 2, 3))
}

private let sceneSource = """
  import React, {useLayoutEffect} from 'react';
  import {AbsoluteFill, Composition, registerRoot, useCurrentFrame, interpolate} from 'remotion';
  import {ThreeCanvas} from '@remotion/three';
  import {useThree} from '@react-three/fiber';
  import {Color, DoubleSide} from 'three';
  const Rig = ({frame}: {frame: number}) => {
    const camera = useThree(state => state.camera);
    useLayoutEffect(() => {
      camera.position.set(interpolate(frame, [0, 10], [0, 4]), 2, 6);
      camera.lookAt(0, 0, 0);
      camera.fov = 40;
    }, [camera, frame]);
    return null;
  };
  const Scene = () => {
    const frame = useCurrentFrame();
    return <AbsoluteFill style={{backgroundColor: '#102030'}}>
      <ThreeCanvas width={64} height={48}>
        <Rig frame={frame} />
        <ambientLight intensity={0.5} />
        <directionalLight position={[2, 3, 4]} intensity={frame / 5} color="orange" />
        <group position={[0, 1, 0]} rotation-y={frame * 0.1}>
          <mesh scale={0.5} rotation={[0.2, 0.3, 0.4]}>
            <boxGeometry args={[1, 2, 3]} />
            <meshStandardMaterial color={new Color().setHSL(0.6, 0.5, 0.5)} roughness={0.2} side={DoubleSide} />
          </mesh>
        </group>
      </ThreeCanvas>
    </AbsoluteFill>;
  };
  registerRoot(() => <Composition id="Scene" component={Scene} width={64} height={48} fps={30} durationInFrames={20} />);
  """

@Test @MainActor
func threeCanvasCommitsResolvedSceneOnPortableCompiler() async throws {
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(.files(["index.tsx": sceneSource], entry: "index.tsx"))
  let bundle = try #require(player.bundle)
  let composition = try #require(player.composition)
  let runtime = try Runtime(bundle: bundle)
  let root = try runtime.frame(composition: composition, number: 10)
  let canvas = try #require(root.children.first?.children.first)
  #expect(canvas.type == "ms-three")
  #expect(canvas.children.isEmpty)
  let scene = try #require(canvas.scene)
  #expect(scene.width == 64 && scene.height == 48)
  #expect(scene.camera.position == [4, 2, 6])
  #expect(scene.camera.fov == 40)
  #expect(scene.objects.map(\.kind) == ["ambient", "directional", "group"])
  #expect(scene.objects[1].light?.intensity == 2)
  // three.js resolves CSS names to linear sRGB: orange = #ffa500.
  #expect(abs((scene.objects[1].light?.color[1] ?? 0) - 0.3762621) < 1e-6)
  let mesh = try #require(scene.objects[2].children.first)
  #expect(mesh.geometry == Scene3D.Geometry(type: "box", args: [1, 2, 3]))
  #expect(mesh.material?.type == "standard" && mesh.material?.side == 2 && mesh.material?.roughness == 0.2)
  #expect(mesh.scale == [0.5, 0.5, 0.5])
  // Frames are independent: frame 0 re-evaluates the camera and the light from scratch.
  let first = try runtime.frame(composition: composition, number: 0).children[0].children[0].scene
  #expect(first?.camera.position == [0, 2, 6])
  #expect(first?.objects[1].light?.intensity == 0)
}

@Test func threeCanvasRendersDeterministicallyOnBothSkiaBackends() throws {
  let bundle = try Compiler().compile(project: threeProject, entry: "src/index.ts")
  let runtime = try Runtime(bundle: bundle)
  let composition = try #require(try runtime.compositions().first { $0.id == "GeometryLab" })
  let node = try runtime.frame(composition: composition, number: 10)
  var outputs: [Data] = []
  for backend in Backend.allCases {
    let renderer = try Renderer(width: composition.width, height: composition.height, backend: backend)
    try renderer.draw(node, composition: composition)
    let first = try renderer.pixels()
    try renderer.draw(node, composition: composition)
    let second = try renderer.pixels()
    for _ in 0..<3 {
      try renderer.draw(node, composition: composition)
      #expect(try renderer.pixels() == first, "\(backend) later repeat render differs")
    }
    if second != first {
      let changed = first.indices.filter { first[$0] != second[$0] }
      let examples = changed.prefix(20).map { "\($0):\(first[$0])->\(second[$0])" }
      print("3D \(backend): \(changed.count) changed bytes; first differences: \(examples)")
      let directory = repository.appendingPathComponent("tests/reports/three-test")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try first.write(to: directory.appendingPathComponent("\(backend)-first.rgba"))
      try second.write(to: directory.appendingPathComponent("\(backend)-repeat.rgba"))
    }
    #expect(second == first, "\(backend) repeat render differs")
    outputs.append(first)
  }
  #expect(outputs[0] == outputs[1], "CPU and GPU compositing of the 3D canvas differ")
  // The canvas is not blank: dozens of distinct colors.
  let colors = Set(stride(from: 0, to: outputs[0].count, by: 4 * 97).map { outputs[0][$0] })
  #expect(colors.count > 20)
}

@Test func threeCanvasHonorsRenderScaleAndDevicePixelRatioRange() throws {
  let scene = try Scene3D.decode("""
    {"width":100,"height":50,"dpr":[1,2],"flat":false,"background":null,"fog":null,
     "camera":{"fov":50,"near":0.1,"far":100,"zoom":1,"aspect":null,"position":[0,0,5],"quaternion":[0,0,0,1]},"objects":[]}
    """)
  #expect(SceneRenderer3D.pixelSize(scene, devicePixelRatio: 1) == Scene3DPixelSize(width: 100, height: 50, dpr: 1))
  #expect(SceneRenderer3D.pixelSize(scene, devicePixelRatio: 1.5) == Scene3DPixelSize(width: 150, height: 75, dpr: 1.5))
  // R3F caps the WebGL canvas at dpr 2; Remotion upscales it to the composition scale.
  #expect(SceneRenderer3D.pixelSize(scene, devicePixelRatio: 4) == Scene3DPixelSize(width: 200, height: 100, dpr: 2))
  let image = try SceneRenderer3D().render(scene, devicePixelRatio: 2)
  #expect(image.width == 200 && image.height == 100)
  #expect(image.pixels.allSatisfy { $0 == 0 }, "No background: the canvas is transparent")
}

// Run with Xcode's Metal API validation/capture enabled: even zero-count light arrays
// must bind enough bytes for one shader element at every mesh draw.
@Test func threeCanvasDrawsMeshesWithEveryLightBufferEmpty() throws {
  let bundle = try Compiler().compile(project: threeProject, entry: "src/index.ts")
  let runtime = try Runtime(bundle: bundle)
  let composition = try #require(try runtime.compositions().first { $0.id == "GeometryLab" })
  let root = try runtime.frame(composition: composition, number: 10)
  var scene = try #require(root.children.first?.children.first?.scene)
  let lightKinds: Set<String> = ["ambient", "point", "spot", "directional", "hemisphere"]
  // GeometryLab's lights are direct children; retain its groups of geometry/material pairs.
  scene.objects.removeAll { lightKinds.contains($0.kind) }
  #expect(!scene.objects.isEmpty)
  let renderer = try SceneRenderer3D()
  let image = try renderer.render(scene, devicePixelRatio: 1)
  #expect(image.width == Int(scene.width) && image.height == Int(scene.height))
  #expect(try renderer.render(scene, devicePixelRatio: 1).pixels == image.pixels)
  // Basic and normal materials remain visible without lights; an empty render cannot pass.
  let colors = Set(stride(from: 0, to: image.pixels.count, by: 4 * 97).map { image.pixels[$0] })
  #expect(colors.count > 20)
}

@Test func usdzModelsLoadThroughModelIO() throws {
  MediaSource.publicDirectory = threeProject.appendingPathComponent("public")
  let parts = try USDModelLoader.load("static:models/probe.usdz")
  #expect(parts.count == 8)
  #expect(parts.allSatisfy { $0.mesh.vertexCount > 0 && ($0.mesh.indices?.count ?? 0) % 3 == 0 })
  // UsdPreviewSurface colors are linear, as in three.js' USDLoader.
  let gold = try #require(parts.first { abs($0.material.color[0] - 0.9) < 1e-6 })
  #expect(gold.material.metalness == 1 && abs(gold.material.roughness - 0.3) < 1e-6)
  #expect(parts.contains { $0.material.emissive[0] > 0.9 })
  // Xform translate ops reach the mesh transforms.
  #expect(parts.contains { abs($0.matrix.position.y - 1.62) < 1e-5 })
  #expect(throws: MotionError.self) { try USDModelLoader.load("static:models/missing.usdz") }
}

@Test @MainActor
func unsupportedThreeElementsFailWithActionableErrors() async throws {
  for (body, message) in [
    ("<mesh><boxGeometry /><meshStandardMaterial map={null} /></mesh>", "property map is not supported"),
    ("<mesh><boxGeometry /><meshPhongMaterial wireframe /></mesh>", "wireframe is not supported"),
    ("<mesh><meshBasicMaterial /></mesh>", "requires a geometry"),
  ] {
    let code = """
      import React from 'react';
      import {Composition, registerRoot} from 'remotion';
      import {ThreeCanvas} from '@remotion/three';
      const Scene = () => <ThreeCanvas width={32} height={32}>\(body)</ThreeCanvas>;
      registerRoot(() => <Composition id="Bad" component={Scene} width={32} height={32} fps={30} durationInFrames={1} />);
      """
    let player = MotionPlayer(configuration: .init(scale: 1))
    await player.load(.files(["index.tsx": code], entry: "index.tsx"))
    let runtime = try Runtime(bundle: try #require(player.bundle))
    let composition = try #require(player.composition)
    #expect {
      try runtime.frame(composition: composition, number: 0)
    } throws: { error in
      String(describing: error).contains(message)
    }
  }
}

@Test @MainActor
func cameraElementsAreRejectedBeforeRendering() async throws {
  let code = """
    import React from 'react';
    import {Composition, registerRoot} from 'remotion';
    import {ThreeCanvas} from '@remotion/three';
    const Scene = () => <ThreeCanvas width={32} height={32}><perspectiveCamera /></ThreeCanvas>;
    registerRoot(() => <Composition id="Bad" component={Scene} width={32} height={32} fps={30} durationInFrames={1} />);
    """
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(.files(["index.tsx": code], entry: "index.tsx"))
  #expect(player.bundle == nil)
  #expect(String(describing: player.status).contains("useThree(state => state.camera)"))
}
