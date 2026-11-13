import Foundation
import MotionCompiler
import MotionRender
import MotionRuntime
import Testing

@Test func retainedAsyncFramesMatchSequentialAndShuffledPixels() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  let bundle = try Compiler().compile(project: root.appendingPathComponent("tests/compiler-fixtures/lifecycle"), entry: "input.tsx")
  let runtime = try Runtime(bundle: bundle)
  let composition = try #require(runtime.compositions().first)
  let renderer = try Renderer(width: composition.width, height: composition.height)
  let file = FileManager.default.temporaryDirectory.appendingPathComponent("retained-\(UUID().uuidString).png")
  defer { try? FileManager.default.removeItem(at: file) }
  var sequential: [Int: Data] = [:]
  for frame in 0..<6 {
    _ = try renderer.render(runtime.frame(composition: composition, number: frame), composition: composition, to: file)
    sequential[frame] = try Data(contentsOf: file)
  }
  for frame in [5, 1, 3, 0, 4, 2] {
    _ = try renderer.render(runtime.frame(composition: composition, number: frame), composition: composition, to: file)
    #expect(try Data(contentsOf: file) == sequential[frame])
  }
}
