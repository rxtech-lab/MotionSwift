import Foundation
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
