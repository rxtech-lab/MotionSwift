import Foundation
import Metal
import MotionCompiler
import MotionCore
import MotionRender
import MotionRuntime
import Testing

private var repository: URL {
  URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
}

private let hasMetal = MTLCreateSystemDefaultDevice() != nil

/// Layered opacity plus fractional, scaled edges: the cases where Ganesh's byte vertex
/// colours used to drift from the raster pipeline.
private let layeredTree = RenderNode(
  type: "div", style: ["backgroundColor": .string("#14213d")],
  children: [
    RenderNode(
      type: "div",
      style: [
        "position": .string("absolute"), "left": .number(3.5), "top": .number(2),
        "width": .number(9), "height": .number(9), "backgroundColor": .string("#fca311"),
        "transform": .string("scale(1.07)"),
      ]),
    RenderNode(
      type: "div",
      style: [
        "position": .string("absolute"), "left": .number(6), "top": .number(5),
        "width": .number(8), "height": .number(8), "opacity": .number(0.5),
        "backgroundColor": .string("#e5e5e5"),
      ]),
  ])

private func composition(width: Int = 16, height: Int = 16) throws -> Composition {
  try JSONDecoder().decode(
    Composition.self,
    from: Data(
      #"{"id":"t","width":\#(width),"height":\#(height),"fps":30,"durationInFrames":2}"#.utf8))
}

@Test(.enabled(if: hasMetal)) func gpuMatchesCPUPixelForPixel() throws {
  let comp = try composition()
  let cpu = try Renderer(width: 16, height: 16, backend: .cpu)
  let gpu = try Renderer(width: 16, height: 16, backend: .gpu)
  let cpuBoxes = try cpu.draw(layeredTree, composition: comp)
  let gpuBoxes = try gpu.draw(layeredTree, composition: comp)
  #expect(cpuBoxes.count == gpuBoxes.count)
  #expect(try cpu.pixels() == gpu.pixels())
}

@Test func scaleMultipliesSurfaceButNotLayout() throws {
  let renderer = try Renderer(width: 16, height: 16, scale: 2.5)
  #expect(renderer.pixelWidth == 40 && renderer.pixelHeight == 40)
  let boxes = try renderer.draw(layeredTree, composition: composition())
  #expect(boxes[0].width == 16)
  #expect(try renderer.pixels().count == 40 * 40 * 4)
  #expect(throws: MotionError.self) { _ = try Renderer(width: 16, height: 16, scale: 0) }
}

@Test func pipelineDeliversFramesInOrderAndMatchesSerialRendering() throws {
  let bundle = try Compiler(repository: repository).compile(
    project: repository.appendingPathComponent("tests/compositions"), entry: "src/index.ts")
  let runtime = try Runtime(bundle: bundle)
  let comp = try #require(try runtime.compositions().first { $0.id == "Timed" })
  let frames = Array(5..<20)
  let serial = try Renderer(width: comp.width, height: comp.height)
  let expected = try frames.map { frame in
    try serial.draw(runtime.frame(composition: comp, number: frame), composition: comp)
    return try serial.pixels()
  }
  for backend in hasMetal ? [RenderBackend.cpu, .gpu] : [.cpu] {
    var delivered: [RenderedFrame] = []
    try FramePipeline.run(
      bundle: bundle, composition: comp, frames: frames, props: "{}",
      options: PipelineOptions(workers: 4, backend: backend, window: 4)
    ) { delivered.append($0) }
    #expect(delivered.map(\.frame) == frames)
    #expect(delivered.map(\.pixels) == expected)
  }
}

@Test func pipelinePropagatesWorkerAndConsumerErrors() throws {
  let bundle = try Compiler(repository: repository).compile(
    project: repository.appendingPathComponent("tests/compositions"), entry: "src/index.ts")
  let comp = try #require(try Runtime(bundle: bundle).compositions().first { $0.id == "Timed" })
  // Frame 99 is out of range, so one worker fails while the others keep claiming frames.
  #expect(throws: MotionError.self) {
    try FramePipeline.run(
      bundle: bundle, composition: comp, frames: [0, 1, 99, 2, 3], props: "{}",
      options: PipelineOptions(workers: 3)
    ) { _ in }
  }
  #expect(throws: MotionError.self) {
    try FramePipeline.run(
      bundle: bundle, composition: comp, frames: Array(0..<30), props: "{}",
      options: PipelineOptions(workers: 3, window: 3)
    ) { frame in if frame.index == 4 { throw MotionError("consumer stopped") } }
  }
}
