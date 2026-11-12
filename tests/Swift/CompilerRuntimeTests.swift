import Foundation
import MotionCompiler
import MotionCore
import MotionRuntime
import Testing

private var repository: URL {
  URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
}

@Test func compilesEnumsNamespacesAndSatisfies() throws {
  let compiler = Compiler(repository: repository)
  let project = repository.appendingPathComponent("tests/compiler-fixtures/types")
  let runtime = try Runtime(bundle: compiler.compile(project: project, entry: "input.tsx"))
  let compositions = try runtime.compositions()
  #expect(compositions.count == 1)
  #expect(compositions[0].id == "Types")
  #expect(compositions[0].width == 320)
  let tree = try runtime.frame(composition: compositions[0], number: 0)
  #expect(tree.children[0].style["backgroundColor"] == .string("#14213d"))
}

@Test func independentFramesRespectSequenceAndProps() throws {
  let compiler = Compiler(repository: repository)
  let project = repository.appendingPathComponent("tests/compositions")
  let runtime = try Runtime(bundle: compiler.compile(project: project, entry: "src/index.ts"))
  let compositions = try runtime.compositions()
  let composition = try #require(compositions.first { $0.id == "Timed" })
  let after = try runtime.frame(composition: composition, number: 15)
  let before = try runtime.frame(composition: composition, number: 0)
  let repeatFrame = try runtime.frame(composition: composition, number: 15)
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  #expect(try encoder.encode(after) == encoder.encode(repeatFrame))
  #expect(before.children[0].children.isEmpty)
  #expect(!after.children[0].children.isEmpty)
  #expect(throws: MotionError.self) { _ = try runtime.frame(composition: composition, number: -1) }
  #expect(throws: MotionError.self) { _ = try runtime.frame(composition: composition, number: 30) }
  #expect(throws: MotionError.self) {
    _ = try runtime.frame(composition: composition, number: 0, props: "[]")
  }
}

@Test func javaScriptCoreMotionMatchesRemotionTrace() throws {
  struct Sample: Decodable {
    let frame: Int
    let values: [Double]
  }
  let compiler = Compiler(repository: repository)
  let project = repository.appendingPathComponent("tests/compiler-fixtures/motion")
  let runtime = try Runtime(bundle: compiler.compile(project: project, entry: "input.tsx"))
  let composition = try #require(runtime.compositions().first)
  let samples = try JSONDecoder().decode(
    [Sample].self, from: Data(contentsOf: project.appendingPathComponent("expected.json")))
  for sample in samples {
    let tree = try runtime.frame(composition: composition, number: sample.frame)
    let values = tree.children[0].children.compactMap { $0.style["left"]?.number }
    #expect(values.count == sample.values.count)
    for (actual, expected) in zip(values, sample.values) { #expect(abs(actual - expected) <= 1e-9) }
  }
}
