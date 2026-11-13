import Foundation
import MotionCompiler
import MotionCore
import MotionPortable
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
  for sample in samples.sorted(by: { ($0.frame * 17 % 31) < ($1.frame * 17 % 31) }) {
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

@Test func nativeCompilerCacheAliasesExportsAndOriginalMaps() throws {
  let project = FileManager.default.temporaryDirectory.appendingPathComponent("motionswift-contract-\(UUID())")
  defer { try? FileManager.default.removeItem(at: project) }
  let package = project.appendingPathComponent("node_modules/palette")
  try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
  func write(_ path: String, _ source: String) throws {
    try source.write(to: project.appendingPathComponent(path), atomically: true, encoding: .utf8)
  }
  try write("tsconfig.json", #"{"compilerOptions":{"baseUrl":".","paths":{"@value":["value.ts"]}}}"#)
  try write("value.ts", "export const value: number = 1;")
  try write("node_modules/palette/package.json",
    #"{"name":"palette","exports":{"./accent":{"browser":"./browser.js","import":"./import.js","default":"./default.js"}}}"#)
  try write("node_modules/palette/browser.js", "export const accent = 'browser';")
  try write("node_modules/palette/import.js", "export const accent = 'import';")
  try write("node_modules/palette/default.js", "export const accent = 'default';")
  try write("main.ts",
    "import {value} from '@value';\nimport {accent} from 'palette/accent';\nthrow Error('original-fixture-' + value + '-' + accent);")
  let compiler = Compiler()
  let start = Date()
  let cold = try compiler.graph(project: project, entry: "main.ts")
  let coldTime = Date().timeIntervalSince(start)
  let warmStart = Date()
  let warm = try compiler.graph(project: project, entry: "main.ts")
  print("Native cache: cold \(coldTime * 1000) ms; warm \(Date().timeIntervalSince(warmStart) * 1000) ms; hits=1 misses=1")
  #expect(compiler.cacheStatistics == .init(hits: 1, misses: 1))
  #expect(try cold.encoded() == warm.encoded())
  let oneShot = Compiler(cacheEnabled: false)
  #expect(try oneShot.graph(project: project, entry: "main.ts").encoded() == cold.encoded())
  #expect(oneShot.cacheStatistics == .init())
  #expect(cold.modules.values.first?.sourceMap?.contains("main.ts") == true)
  do { _ = try Runtime(bundle: GraphLinker.link(cold)); Issue.record("Expected mapped error") } catch {
    let message = String(describing: error)
    #expect(message.contains("original-fixture-1-browser"), "\(message)")
    #expect(message.contains("main.ts:3:"), "\(message)")
  }
  try write("value.ts", "export const value = 2;")
  let changed = try compiler.graph(project: project, entry: "main.ts")
  #expect(changed != cold)
  #expect(compiler.cacheStatistics.misses == 2)
  try write("node_modules/palette/browser.js", "export const accent = 'changed';")
  #expect(try compiler.graph(project: project, entry: "main.ts") != changed)
  // A cold rebuild must not embed random toolchain extraction paths.
  compiler.clearCache()
  let again = try compiler.graph(project: project, entry: "main.ts")
  compiler.clearCache()
  #expect(try again.encoded() == compiler.graph(project: project, entry: "main.ts").encoded())
}

@Test func nativeExportsPatternsArraysConditionsAndBlockedImports() throws {
  let project = FileManager.default.temporaryDirectory.appendingPathComponent("motionswift-exports-\(UUID())")
  defer { try? FileManager.default.removeItem(at: project) }
  let package = project.appendingPathComponent("node_modules/@fixture/colors")
  try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
  func write(_ url: URL, _ text: String) throws { try text.write(to: url, atomically: true, encoding: .utf8) }
  try write(package.appendingPathComponent("package.json"), #"""
    {"name":"@fixture/colors","exports":{
      ".":{"import":"./import.js","browser":"./browser.js","default":"./fallback.js"},
      "./feature/*":"./*.js","./array":["./browser.js"],"./private":null}}
    """#)
  try write(package.appendingPathComponent("import.js"), "export const value = 'import-first';")
  try write(package.appendingPathComponent("browser.js"), "export const value = 'browser';")
  try write(package.appendingPathComponent("fallback.js"), "export const value = 'fallback';")
  let main = project.appendingPathComponent("main.ts")
  let compiler = Compiler()
  let cases = [("@fixture/colors", "import-first"), ("@fixture/colors/feature/browser", "browser"),
    ("@fixture/colors/array", "browser")]
  for (specifier, expected) in cases {
    try write(main, "import {value} from '\(specifier)'; throw Error(value);")
    let graph = try compiler.graph(project: project, entry: "main.ts")
    #expect(graph.packages == ["@fixture/colors"])
    do { _ = try Runtime(bundle: GraphLinker.link(graph)); Issue.record("Expected fixture throw")
    } catch { #expect(String(describing: error).contains(expected)) }
  }
  try write(main, "// original import location\nimport {value} from '@fixture/colors/private';\nthrow Error(value);")
  do { _ = try compiler.graph(project: project, entry: "main.ts"); Issue.record("Expected exports block")
  } catch {
    let message = String(describing: error)
    #expect(message.contains("main.ts:2:21:"), "\(message)")
    #expect(message.contains("package exports"))
  }
}

@Test func nativeRequiresInsideStringsAreNotDependencies() throws {
  let project = FileManager.default.temporaryDirectory.appendingPathComponent("motionswift-literal-\(UUID())")
  try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: project) }
  try #"export const text = "require('fake-package')";"#
    .write(to: project.appendingPathComponent("main.ts"), atomically: true, encoding: .utf8)
  let graph = try Compiler().graph(project: project, entry: "main.ts")
  #expect(graph.modules.values.first?.dependencies.isEmpty == true)
}
