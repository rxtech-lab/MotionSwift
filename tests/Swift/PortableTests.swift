import Foundation
import JavaScriptCore
import MotionCompiler
import MotionCore
import MotionPortable
import MotionRender
import MotionRuntime
import Testing

private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent()
private let fixtures = repository.appendingPathComponent("tests/compositions")
let sampleProject = repository.appendingPathComponent("Examples/MotionStudio/SampleProject")

private func pixels(_ bundle: String, composition id: String, frame: Int) throws -> Data {
  let runtime = try Runtime(bundle: bundle)
  guard let composition = try runtime.compositions().first(where: { $0.id == id }) else {
    throw MotionError("Missing composition \(id)")
  }
  let renderer = try Renderer(width: composition.width, height: composition.height)
  try renderer.draw(try runtime.frame(composition: composition, number: frame), composition: composition)
  return try renderer.pixels()
}

/// The device path (portable compiler + precompiled vendor graph) must render exactly what the Mac
/// tsgo/esbuild path renders, and a Mac-exported graph must too.
@Test(arguments: ["Solid", "Boxes", "Motion", "Flex", "Layers", "Timed"])
func portableAndMacGraphsMatchTsgoPixels(composition: String) throws {
  let tsgo = try Compiler().compile(project: fixtures, entry: "src/index.ts")
  let portable = try GraphLinker.link(PortableCompiler().compile(project: fixtures, entry: "src/index.ts"))
  let stamped = try GraphLinker.link(PortableCompiler().compile(project: fixtures, entry: "src/index.ts", stamp: true))
  let synced = try ModuleGraph(data: Compiler().graph(project: fixtures, entry: "src/index.ts").encoded())
  let mac = try GraphLinker.link(synced)
  for frame in [0, 12, 29] {
    let expected = try pixels(tsgo, composition: composition, frame: frame)
    #expect(try pixels(portable, composition: composition, frame: frame) == expected)
    #expect(try pixels(stamped, composition: composition, frame: frame) == expected)
    #expect(try pixels(mac, composition: composition, frame: frame) == expected)
  }
}

@Test func moduleGraphRoundTripsAndValidatesVendorAndImports() throws {
  let graph = try PortableCompiler().compile(project: sampleProject, entry: "src/index.ts", stamp: true)
  #expect(graph.stamped)
  #expect(Set(graph.modules.keys) == ["src/index.ts", "src/Root.tsx", "src/Cards.tsx", "src/Row.tsx", "src/Pulse.tsx"])
  #expect(try ModuleGraph(data: graph.encoded()) == graph)

  var foreign = graph
  foreign.vendor = "react@17.0.0"
  #expect(throws: MotionError.self) { try ModuleGraph(data: foreign.encoded()) }
  var broken = graph
  broken.modules["src/Root.tsx"] = nil
  #expect(throws: MotionError.self) { try GraphLinker.link(broken) }
}

@Test func portableCompilerReportsUnsupportedPackagesWithSyncHint() throws {
  let error = #expect(throws: EditError.self) {
    try PortableCompiler().compile(files: ["src/a.tsx": "import x from 'lodash';\nexport default x;"], entry: "src/a.tsx")
  }
  #expect(error?.description.contains("ms/unsupported-package: lodash") == true)
  #expect(error?.description.contains("motionswift graph") == true)
}

@Test func stampedFramesExposeSourceStampsOnLayoutBoxes() throws {
  let bundle = try GraphLinker.link(PortableCompiler().compile(project: sampleProject, entry: "src/index.ts", stamp: true))
  let runtime = try Runtime(bundle: bundle)
  let cards = try #require(try runtime.compositions().first { $0.id == "Cards" })
  let tree = try runtime.frame(composition: cards, number: 0)
  let boxes = try Renderer(width: cards.width, height: cards.height).draw(tree, composition: cards)
  #expect(boxes.compactMap(\.source) == [
    "src/Cards.tsx:5:28", "src/Cards.tsx:6:3", "src/Cards.tsx:7:3", "src/Cards.tsx:8:3",
  ])
}

/// docs/editor.md → Commit: the re-rendered committed frame must match the preview-override frame.
@Test func committedEditMatchesPreviewOverridePixels() throws {
  let compiler = try PortableCompiler()
  var files = try PortableCompiler.sources(in: sampleProject)
  let bundle = try GraphLinker.link(compiler.compile(files: files, entry: "src/index.ts", stamp: true))
  let runtime = try Runtime(bundle: bundle)
  let cards = try #require(try runtime.compositions().first { $0.id == "Cards" })
  let renderer = try Renderer(width: cards.width, height: cards.height)
  let overrides: [String: [String: JSONValue]] = [
    "src/Cards.tsx:6:3": ["left": .number(96), "top": .number(30), "width": .number(250)],
  ]
  try renderer.draw(try runtime.frame(composition: cards, number: 0).applying(overrides), composition: cards)
  let preview = try renderer.pixels()

  for (key, value) in overrides["src/Cards.tsx:6:3"]! {
    let edited = try compiler.edit(source: files["src/Cards.tsx"]!, operation: .setStyle("src/Cards.tsx:6:3", key, value))
    files["src/Cards.tsx"] = edited.source
  }
  #expect(files["src/Cards.tsx"]!.contains("left: 96, top: 30, width: 250, height: 140"))
  let committed = try Runtime(bundle: GraphLinker.link(compiler.compile(files: files, entry: "src/index.ts", stamp: true)))
  try renderer.draw(try committed.frame(composition: cards, number: 0), composition: cards)
  #expect(try renderer.pixels() == preview)
}

@Test func previewBudgetReportsStages() throws {
  let bundle = try GraphLinker.link(PortableCompiler().compile(project: sampleProject, entry: "src/index.ts"))
  let composition = try #require(try Runtime(bundle: bundle).compositions().first { $0.id == "Pulse" })
  let report = try PreviewBudget.measure(bundle: bundle, composition: composition, frames: Array(0..<6))
  #expect(report.frames == 5)
  #expect(report.total.p50 > 0 && report.total.p50 >= report.javascript.p50)
  #expect(report.budgetMs == 1000.0 / 30)
}

/// Packages outside the vendor graph fail on device with a sync hint; a Mac graph bundles them.
@Test func macGraphBundlesPackagesTheDeviceVendorGraphLacks() throws {
  let project = FileManager.default.temporaryDirectory.appendingPathComponent("motionswift-package-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: project) }
  let package = project.appendingPathComponent("node_modules/tiny-palette")
  try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: project.appendingPathComponent("src"), withIntermediateDirectories: true)
  try #"{"name": "tiny-palette", "version": "1.0.0", "main": "index.js"}"#
    .write(to: package.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
  try "exports.accent = '#ff0000';".write(to: package.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
  try """
    import React from 'react';
    import {AbsoluteFill, Composition, registerRoot} from 'remotion';
    // @ts-ignore untyped package
    import {accent} from 'tiny-palette';
    const Card = () => <AbsoluteFill style={{backgroundColor: accent}} />;
    registerRoot(() => <Composition id="Card" component={Card} width={16} height={9} fps={30} durationInFrames={1} />);
    """.write(to: project.appendingPathComponent("src/index.tsx"), atomically: true, encoding: .utf8)

  #expect(throws: EditError.self) { try PortableCompiler().compile(project: project, entry: "src/index.tsx") }
  let graph = try Compiler().graph(project: project, entry: "src/index.tsx")
  #expect(graph.packages == ["tiny-palette"])
  let red = try pixels(GraphLinker.link(ModuleGraph(data: graph.encoded())), composition: "Card", frame: 0)
  #expect(red.prefix(4) == Data([255, 0, 0, 255]))
}

@Test func detectedStylesIncludeResolvedValuesAndAgentLabels() throws {
  let compiler = try PortableCompiler()
  let summary = try compiler.styles(
    source: "const Card = () => <div data-ms-properties={{width: {label: 'Card width', group: 'Size'}}} "
      + "style={{width: 120, ...theme, color: '#fff'}} />;", src: "a.tsx:1:20")
  let properties = summary.detectedProperties(resolved: ["width": .number(180), "color": .string("#fff"), "fontSize": .number(24)])
  #expect(properties.map(\.key) == ["width", "color", "fontSize"])
  #expect(properties.first { $0.key == "width" }?.kind == .computed)
  #expect(properties.first { $0.key == "color" }?.kind == .static)
  #expect(properties.first { $0.key == "fontSize" }?.value == .number(24))
  #expect(summary.label(for: "width") == "Card width")
  #expect(summary.group(for: "width") == "Size")
  #expect(summary.group(for: "fontSize") == "Text")
  #expect(summary.group(for: "opacity") == "Appearance")
}

@Test func portableContentCacheRevalidatesDependenciesAndOptions() throws {
  let compiler = try PortableCompiler()
  var files = ["main.ts": "export {value} from './value.js';", "value.ts": "export const value: number = 1;"]
  files["value.js"] = "export const value = 99;"
  let start = Date()
  let cold = try compiler.compile(files: files, entry: "main.ts")
  #expect(cold.modules["main.ts"]?.dependencies["./value.js"] == "value.ts")
  let coldTime = Date().timeIntervalSince(start)
  #expect(compiler.cacheStatistics == .init(hits: 0, misses: 2))
  let warmStart = Date()
  let warm = try compiler.compile(files: files, entry: "main.ts")
  print("Portable cache: cold \(coldTime * 1000) ms; warm \(Date().timeIntervalSince(warmStart) * 1000) ms; hits=2 misses=0")
  #expect(compiler.cacheStatistics == .init(hits: 2, misses: 0))
  #expect(try cold.encoded() == warm.encoded())
  files["value.ts"] = "export const value: number = 2;"
  let changed = try compiler.compile(files: files, entry: "main.ts")
  #expect(compiler.cacheStatistics == .init(hits: 1, misses: 1))
  #expect(changed != cold)
  _ = try compiler.compile(files: files, entry: "main.ts", stamp: true)
  #expect(compiler.cacheStatistics.misses == 2)
  files["value.ts"] = nil
  let fallback = try compiler.compile(files: files, entry: "main.ts")
  #expect(fallback.modules["main.ts"]?.dependencies["./value.js"] == "value.js")
  files["value.js"] = nil
  #expect(throws: EditError.self) { try compiler.compile(files: files, entry: "main.ts") }
}

@Test func portableAliasesPreferExactThenLongestPrefixAndOrderedFallbacks() throws {
  let compiler = try PortableCompiler()
  var files = [
    "tsconfig.json": #"{"extends":"./config/base","compilerOptions":{"paths":{"@/*":["missing/*","src/*"],"#
      + #""@/deep/*":["deep/*"],"@/deep/value":["exact.ts"],"*suffix":["src/prefix*.ts"]}}}"#,
    "config/base.json": #"{/* JSONC */ "compilerOptions":{"baseUrl":"..", /* trailing */},}"#,
    "main.ts": "export {x} from '@/deep/value'; export {y} from '@/deep/other'; export {z} from '@/fallback'; export {s} from 'suffix';",
    "exact.ts": "export const x = 1;", "deep/other.ts": "export const y = 2;", "src/fallback.ts": "export const z = 3;",
    "src/prefix.ts": "export const s = 4;",
  ]
  let graph = try compiler.compile(files: files, entry: "main.ts")
  #expect(graph.modules["main.ts"]?.dependencies == [
    "@/deep/value": "exact.ts", "@/deep/other": "deep/other.ts", "@/fallback": "src/fallback.ts", "suffix": "src/prefix.ts",
  ])
  files["exact.ts"] = nil
  do {
    _ = try compiler.compile(files: files, entry: "main.ts")
    Issue.record("Expected unresolved alias")
  } catch {
    #expect(String(describing: error).contains("main.ts:1:17:"))
  }
}

@Test func portableMapsOriginalColumnsAfterMultipleStampsAndLinking() throws {
  let source = "const View = () => <div><span />{(() => { throw Error('mapped-fixture'); })()}</div>;\nView();"
  let compiler = try PortableCompiler()
  let graph = try compiler.compile(files: ["src/view.tsx": source], entry: "src/view.tsx", stamp: true)
  #expect(graph.modules["src/view.tsx"]?.code.contains("src/view.tsx:1:25") == true)
  #expect(graph.modules["src/view.tsx"]?.sourceMap?.contains("sourcesContent") == true)
  #expect(try ModuleGraph(data: graph.encoded()) == graph)
  let linked = try GraphLinker.link(graph)
  let context = try #require(JSContext())
  context.evaluateScript("function __ms_start() {}")
  context.evaluateScript(linked)
  let range = try #require(linked.range(of: "Error('mapped-fixture')"))
  let prefix = linked[..<range.lowerBound].split(separator: "\n", omittingEmptySubsequences: false)
  let generated = "motionswift:bundle:\(prefix.count):\((prefix.last?.utf16.count ?? 0) + 1)"
  let originalRange = try #require(source.range(of: "Error("))
  let original = source.distance(from: source.startIndex, to: originalRange.lowerBound) + 1
  let mapped = context.objectForKeyedSubscript("__ms_mapStack")?.call(withArguments: [generated])?.toString()
  #expect(mapped == "src/view.tsx:1:\(original)", "\(mapped ?? "missing position")")
  print("Portable original-source example: \(mapped ?? "missing position")")
  do { _ = try Runtime(bundle: linked); Issue.record("Expected mapped runtime error") } catch {
    let message = String(describing: error)
    #expect(message.contains("mapped-fixture"))
    #expect(message.contains("src/view.tsx:1:"), "\(message)")
  }
}

@Test func portableImportDiagnosticsUseOriginalSourceLocations() throws {
  do {
    _ = try PortableCompiler().compile(files: ["src/main.ts": "// header\nimport {x} from './missing';\nexport {x};"], entry: "src/main.ts")
    Issue.record("Expected unresolved import")
  } catch { #expect(String(describing: error).contains("src/main.ts:2:17:")) }
  // A string that looks like a require must never become a dependency.
  let graph = try PortableCompiler().compile(files: ["main.ts": #"export const text = "require('fake')";"#], entry: "main.ts")
  #expect(graph.modules["main.ts"]?.dependencies.isEmpty == true)
}

@Test func portableDependencyErrorsMapThroughLinkedModules() throws {
  let graph = try PortableCompiler().compile(files: [
    "main.ts": "import './z'; export const value = 1;",
    "z.ts": "type Label = string;\nconst label: Label = 'dependency-map';\nthrow Error(label);",
  ], entry: "main.ts", stamp: true)
  let restored = try ModuleGraph(data: graph.encoded())
  do {
    _ = try Runtime(bundle: GraphLinker.link(restored))
    Issue.record("Expected dependency error")
  } catch {
    let message = String(describing: error)
    #expect(message.contains("dependency-map"))
    #expect(message.contains("z.ts:3:"), "\(message)")
  }
}
