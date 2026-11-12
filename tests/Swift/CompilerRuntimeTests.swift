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

@Test func sustainedBenchmarkCompilesAndEvaluatesLastFrame() throws {
  struct BenchmarkConfiguration: Decodable {
    let project: String
    let entryPoint: String
  }
  let configURL = repository.appendingPathComponent("tests/perf/bench.long.config.json")
  let config = try JSONDecoder().decode(BenchmarkConfiguration.self, from: Data(contentsOf: configURL))
  let project = configURL.deletingLastPathComponent().appendingPathComponent(config.project).standardizedFileURL
  let runtime = try Runtime(bundle: Compiler().compile(project: project, entry: config.entryPoint))
  let compositions = try runtime.compositions()
  #expect(Set(compositions.map(\.id)) == ["Flex", "Layers", "LoopingTimed"])
  for composition in compositions {
    #expect(composition.durationInFrames == 300)
    _ = try runtime.frame(composition: composition, number: 299)
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

@Test func embeddedTypeScript7ChecksValidAndInvalidProjects() throws {
  let compiler = Compiler()
  let valid = try compiler.checkTypes(project: repository.appendingPathComponent("tests/type-fixtures/valid"), entry: "core.tsx")
  #expect(valid.isEmpty, "\(valid)")
  let invalid = try compiler.checkTypes(project: repository.appendingPathComponent("tests/type-fixtures/invalid"), entry: "grid.tsx")
  #expect(invalid.contains { $0.rule == "ts/2322" && $0.line > 0 && $0.col > 0 && $0.file.hasSuffix("grid.tsx") })
}

@Test func embeddedCompilerNeedsOnlyProjectSources() throws {
  let files = FileManager.default
  let project = files.temporaryDirectory.appendingPathComponent("motionswift-project-\(UUID().uuidString)")
  try files.createDirectory(at: project, withIntermediateDirectories: true)
  defer { try? files.removeItem(at: project) }
  try files.createDirectory(at: project.appendingPathComponent("src"), withIntermediateDirectories: true)
  try """
    import {registerRoot, Composition} from 'remotion';
    import dimensions from '../dimensions.json';
    import {View} from './View';
    registerRoot(() => <Composition id="Standalone" component={View} width={dimensions.width}
      height={32} fps={30} durationInFrames={1} />);
    """.write(to: project.appendingPathComponent("src/index.tsx"), atomically: true, encoding: .utf8)
  try "export const View = () => <div style={{backgroundColor: '#123456'}} />;"
    .write(to: project.appendingPathComponent("src/View.jsx"), atomically: true, encoding: .utf8)
  try #"{"width":32}"#.write(to: project.appendingPathComponent("dimensions.json"), atomically: true, encoding: .utf8)
  let runtime = try Runtime(bundle: Compiler().compile(project: project, entry: "src/index.tsx"))
  let composition = try #require(runtime.compositions().first)
  #expect(composition.id == "Standalone")
  #expect(try runtime.frame(composition: composition, number: 0).children[0].style["backgroundColor"] == .string("#123456"))
}

@Test(arguments: [
  "import 'node:fs';",
  "const load = () => import('./other'); export {load};",
  "const load = (name: string) => require(name); export {load};",
  "export const View = () => <video />;",
  "export const View = () => <div className='invalid' />;",
  "export const View = () => <div style={{display: 'grid'}} />;",
])
func embeddedCompilerRejectsUnsupportedSources(source: String) throws {
  let files = FileManager.default
  let project = files.temporaryDirectory.appendingPathComponent("motionswift-invalid-\(UUID().uuidString)")
  try files.createDirectory(at: project, withIntermediateDirectories: true)
  defer { try? files.removeItem(at: project) }
  try source.write(to: project.appendingPathComponent("index.tsx"), atomically: true, encoding: .utf8)
  try "export default 1;".write(to: project.appendingPathComponent("other.ts"), atomically: true, encoding: .utf8)
  do {
    _ = try Compiler().compile(project: project, entry: "index.tsx")
    Issue.record("Expected unsupported source to fail: \(source)")
  } catch {
    let message = String(describing: error)
    let expected = source.contains("node:fs") ? "ms/unsupported-package"
      : source.contains("import(") || source.contains("require(") ? "Dynamic import/require"
      : source.contains("video") ? "ms/no-raw-media"
      : source.contains("className") ? "ms/no-classname" : "ms/unsupported-css-value"
    #expect(message.contains(expected), "\(message)")
  }
}

@Test func tsgoEmissionRemainsIndependentOfTypeChecking() throws {
  let project = repository.appendingPathComponent("tests/compiler-fixtures/types")
  let compiler = Compiler()
  let files = FileManager.default
  let temporary = files.temporaryDirectory.appendingPathComponent("motionswift-types-\(UUID().uuidString)")
  try files.copyItem(at: project, to: temporary)
  defer { try? files.removeItem(at: temporary) }
  let entry = temporary.appendingPathComponent("input.tsx")
  let source = try String(contentsOf: entry, encoding: .utf8)
  try (source + "\nconst invalid: number = 'type error';\n").write(to: entry, atomically: true, encoding: .utf8)
  #expect(try compiler.checkTypes(project: temporary, entry: "input.tsx").contains { $0.rule == "ts/2322" })
  let runtime = try Runtime(bundle: compiler.compile(project: temporary, entry: "input.tsx"))
  #expect(try runtime.compositions().first?.id == "Types")
}
