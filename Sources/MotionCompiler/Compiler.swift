#if os(macOS)
import Foundation
import JavaScriptCore
import MotionCore
import MotionPortable

/// Native TypeScript 7 (tsgo) emits and checks TS/TSX; esbuild links the emitted JavaScript.
public struct Compiler {
  /// Retained for source compatibility; compiler assets come from the package bundle.
  public let repository: URL
  private let cache = NativeGraphCache()
  private var cacheEnabled = true
  public var cacheStatistics: CompilerCacheStatistics { cache.statistics }
  public func clearCache() { cache.clear() }

  public init(repository: URL) { self.repository = repository }
  /// Disable retained-graph bookkeeping for one-shot callers such as the CLI.
  public init(cacheEnabled: Bool = true) {
    repository = Bundle.module.bundleURL
    self.cacheEnabled = cacheEnabled
  }

  /// Emits the project with tsgo after subset inspection; returns the emitted entry module.
  private func emit(project: URL, entry: String, toolchain: URL, temporary: URL, vendor: URL) throws -> URL {
    let emitted = temporary.appendingPathComponent("emitted")
    let config = try configuration(project: project, entry: entry, vendor: vendor, temporary: temporary,
      emit: emitted)
    let compilation = try run(toolchain.appendingPathComponent("typescript/lib/tsc"),
      ["--project", config.path, "--pretty", "false", "--listFiles"], directory: project)
    guard compilation.status == 0 else { throw MotionError("tsgo: \(compilation.output)") }
    try inspect(files: compilation.output.components(separatedBy: .newlines), vendor: vendor)
    let javascriptExtension = ["mts": "mjs", "cts": "cjs"][project.appendingPathComponent(entry).pathExtension] ?? "js"
    return emitted.appendingPathComponent(entry).deletingPathExtension().appendingPathExtension(javascriptExtension)
  }

  /// Compiles a module graph for iOS/iPadOS devices: one CommonJS module with every npm package the
  /// project imports bundled in, and vendor imports (React, the shim) left for the device's
  /// precompiled vendor graph. Packages are resolved from the project's `node_modules` and still
  /// pass the dynamic import/require inspection.
  public func graph(project: URL, entry: String) throws -> ModuleGraph {
    let manifest = cacheEnabled ? try NativeGraphCache.manifest(project) : [:]
    let identity = try CompilerContent.key([
      "project": project.standardizedFileURL.path, "entry": entry,
      "manifest": try CompilerContent.key(manifest), "vendor": Vendor.sha256,
      "versions": try String(contentsOf: resource("versions.json"), encoding: .utf8),
      "inspector": CompilerContent.hash(try Data(contentsOf: resource("inspect.js"))),
      "contract": "native-graph-v2-es2022-browser-import",
    ])
    if cacheEnabled, let graph = cache.lookup(identity) { return graph }
    var tracked: [URL] = []
    let graph = try withToolchain { toolchain, temporary in
      let vendor = try resource("Vendor")
      let compiledEntry = try emit(project: project, entry: entry, toolchain: toolchain, temporary: temporary,
        vendor: vendor)
      let output = temporary.appendingPathComponent("graph.js")
      let metadata = temporary.appendingPathComponent("meta.json")
      let aliases = try resolutionOptions(project: project)
      let emitted = temporary.appendingPathComponent("emitted")
      var linkOptions: [String: Any] = ["baseUrl": emitted.path]
      if let paths = aliases["paths"] as? [String: [String]] {
        linkOptions["paths"] = paths.mapValues { targets in targets.map { target in
          var url = emitted.appendingPathComponent(target)
          if let ext = ["ts": "js", "tsx": "js", "jsx": "js", "mts": "mjs", "cts": "cjs"][url.pathExtension] {
            url = url.deletingPathExtension().appendingPathExtension(ext)
          }
          return url.path
        } }
      }
      if let base = aliases["baseUrl"] as? String { linkOptions["baseUrl"] = emitted.appendingPathComponent(base).path }
      let linkConfig = temporary.appendingPathComponent("link-tsconfig.json")
      try JSONSerialization.data(withJSONObject: ["compilerOptions": linkOptions], options: [.sortedKeys]).write(to: linkConfig)
      var arguments = [compiledEntry.path, "--bundle", "--platform=browser", "--format=cjs", "--target=es2022",
        "--define:process.env.NODE_ENV=\"production\"", "--log-level=warning",
        "--outfile=\(output.path)", "--metafile=\(metadata.path)",
        "--tsconfig=\(linkConfig.path)", "--conditions=browser,import", "--main-fields=browser,module,main",
        "--sourcemap=external", "--sources-content=true", "--minify-whitespace", "--legal-comments=none"]
      arguments.append("--external:node:*")
      arguments += Vendor.specifiers.map { "--external:\($0)" }
      let modules = project.appendingPathComponent("node_modules").path
      let result = try run(toolchain.appendingPathComponent("esbuild/bin/esbuild"), arguments, directory: project,
        environment: ["NODE_PATH": modules])
      guard result.status == 0 else {
        throw MotionError("esbuild: \(result.output)\n\(try importHints(project: project, output: result.output))")
      }
      let graph = try JSONDecoder().decode(CompilerGraph.self, from: Data(contentsOf: metadata))
      var packages = Set<String>()
      var packageFiles: [String] = []
      for input in graph.inputs.keys {
        let url = (input.hasPrefix("/") ? URL(fileURLWithPath: input) : project.appendingPathComponent(input)).standardizedFileURL
        if !url.path.hasPrefix(temporary.path + "/") { tracked.append(url) }
        var directory = url.standardizedFileURL.deletingLastPathComponent()
        while !directory.path.isEmpty && directory.path != "/" {
          let manifest = directory.appendingPathComponent("package.json")
          if FileManager.default.fileExists(atPath: manifest.path) { tracked.append(manifest) }
          let parent = directory.deletingLastPathComponent().standardizedFileURL
          guard parent.path != directory.path else { break }
          directory = parent
        }
        guard let range = input.range(of: "node_modules/", options: .backwards) else { continue }
        let parts = input[range.upperBound...].split(separator: "/")
        guard let first = parts.first else { continue }
        packages.insert(first.hasPrefix("@") && parts.count > 1 ? "\(first)/\(parts[1])" : String(first))
        packageFiles.append(input.hasPrefix("/") ? input : project.appendingPathComponent(input).path)
      }
      try inspect(files: packageFiles, vendor: vendor, subset: false)
      let code = try String(contentsOf: output, encoding: .utf8)
      var dependencies: [String: String] = [:]
      let imports = try PortableCompiler().importLocations(files: ["bundle.js": code])
      for location in imports {
        let specifier = location.specifier
        guard Vendor.specifiers.contains(specifier) else {
          let hints = try importHints(project: project, output: "\"\(specifier)\"")
          throw MotionError("ms/unsupported-package: \(specifier) could not be bundled from \(modules)\n\(hints)")
        }
        dependencies[specifier] = "vendor:\(specifier)"
      }
      var map = try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathExtension("map"))) as? [String: Any] ?? [:]
      map["sources"] = (map["sources"] as? [String] ?? []).map { source in
        let url = temporary.appendingPathComponent(source).standardizedFileURL
        let root = project.standardizedFileURL.path + "/"
        if url.path.hasPrefix(root) { return String(url.path.dropFirst(root.count)) }
        if let range = url.path.range(of: "node_modules/") { return String(url.path[range.lowerBound...]) }
        return url.lastPathComponent
      }
      map["file"] = "\(entry).bundle.js"
      let sourceMap = String(bytes: try JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]), encoding: .utf8)
      let name = "\(entry).bundle.js"
      return ModuleGraph(
        entry: name, modules: [name: .init(code: code, dependencies: dependencies, sourceMap: sourceMap)], packages: packages.sorted(),
        producer: "tsgo 7.0.2 + esbuild 0.28.1 (macOS)", stamped: false)
    }
    // A project edited during compilation must not poison the identity captured before emission.
    if cacheEnabled, try NativeGraphCache.manifest(project) == manifest {
      try cache.store(identity, graph: graph, dependencies: tracked)
    }
    return graph
  }

  public func compile(project: URL, entry: String) throws -> String {
    try GraphLinker.link(graph(project: project, entry: entry))
  }

  public func checkTypes(project: URL, entry: String) throws -> [Diagnostic] {
    try withToolchain { toolchain, temporary in
      let vendor = try resource("Vendor")
      let config = try configuration(project: project, entry: entry, vendor: vendor, temporary: temporary)
      let result = try run(toolchain.appendingPathComponent("typescript/lib/tsc"),
        ["--project", config.path, "--pretty", "false"], directory: project)
      return try diagnostics(result.output, status: result.status)
    }
  }

  private func configuration(project: URL, entry: String, vendor: URL, temporary: URL, emit: URL? = nil) throws -> URL {
    let modules = vendor.appendingPathComponent("node_modules")
    let shim = vendor.appendingPathComponent("shim")
    var options: [String: Any] = [
      "target": "ES2022", "module": "ESNext", "moduleResolution": "Bundler",
      "jsx": "react-jsx", "jsxImportSource": "@motionswift/remotion", "strict": true,
      "isolatedModules": true, "esModuleInterop": true, "skipLibCheck": false,
      "resolveJsonModule": true, "allowJs": true,
      "types": ["react"], "typeRoots": [modules.appendingPathComponent("@types").path],
      "paths": ["@motionswift/remotion": [shim.appendingPathComponent("index.d.ts").path],
        "@motionswift/remotion/jsx-runtime": [shim.appendingPathComponent("jsx-runtime.d.ts").path],
        "remotion": [shim.appendingPathComponent("index.d.ts").path],
        "three": [shim.appendingPathComponent("three.d.ts").path],
        "three/addons/loaders/USDLoader.js": [shim.appendingPathComponent("usd-loader.d.ts").path],
        "three/examples/jsm/loaders/USDLoader.js": [shim.appendingPathComponent("usd-loader.d.ts").path],
        "three/addons/loaders/USDZLoader.js": [shim.appendingPathComponent("usd-loader.d.ts").path],
        "three/examples/jsm/loaders/USDZLoader.js": [shim.appendingPathComponent("usd-loader.d.ts").path],
        "@react-three/fiber": [shim.appendingPathComponent("fiber.d.ts").path],
        "@remotion/paths": [shim.appendingPathComponent("remotion-paths.d.ts").path],
        "@remotion/shapes": [shim.appendingPathComponent("remotion-shapes.d.ts").path],
        "@remotion/transitions": [shim.appendingPathComponent("transitions.d.ts").path],
        "@remotion/transitions/fade": [shim.appendingPathComponent("transition-fade.d.ts").path],
        "@remotion/transitions/slide": [shim.appendingPathComponent("transition-slide.d.ts").path],
        "@remotion/transitions/wipe": [shim.appendingPathComponent("transition-wipe.d.ts").path],
        "@remotion/three": [shim.appendingPathComponent("remotion-three.d.ts").path],
        "@motionswift/map": [shim.appendingPathComponent("map.d.ts").path],
        "react": [modules.appendingPathComponent("@types/react/index.d.ts").path],
        "react/jsx-runtime": [modules.appendingPathComponent("@types/react/jsx-runtime.d.ts").path]],
    ]
    let aliases = try resolutionOptions(project: project)
    if let paths = aliases["paths"] as? [String: [String]], var builtins = options["paths"] as? [String: [String]] {
      for (key, targets) in paths where builtins[key] == nil {
        builtins[key] = targets.map { project.appendingPathComponent($0).path }
      }
      options["paths"] = builtins
    }
    // TypeScript 7 removed baseUrl; equivalent absolute paths preserve legacy projects.
    if let base = aliases["baseUrl"] as? String, var paths = options["paths"] as? [String: [String]], paths["*"] == nil {
      paths["*"] = [project.appendingPathComponent(base).appendingPathComponent("*").path]
      options["paths"] = paths
    }
    if let emit {
      options["sourceMap"] = true
      options["inlineSources"] = true
      // Rendering remains independent of semantic type errors; checkTypes reports them separately.
      options["noCheck"] = true
      options["rootDir"] = project.standardizedFileURL.path
      options["outDir"] = emit.path
    } else {
      options["noEmit"] = true
    }
    let config = temporary.appendingPathComponent("tsconfig.json")
    try JSONSerialization.data(withJSONObject: ["compilerOptions": options,
      "files": [project.appendingPathComponent(entry).standardizedFileURL.path]]).write(to: config)
    return config
  }

  private func withToolchain<T>(_ body: (URL, URL) throws -> T) throws -> T {
    #if arch(arm64)
    let architecture = "arm64"
    #elseif arch(x86_64)
    let architecture = "x64"
    #else
    throw MotionError("Embedded compiler supports Apple Silicon and Intel macOS")
    #endif
    let files = FileManager.default
    let temporary = files.temporaryDirectory.appendingPathComponent("motionswift-compiler-\(UUID().uuidString)")
    try files.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: temporary) }
    for (name, archive) in [
      ("typescript", "typescript-typescript-darwin-\(architecture)-7.0.2.tgz"),
      ("esbuild", "esbuild-darwin-\(architecture)-0.28.1.tgz"),
    ] {
      let destination = temporary.appendingPathComponent(name)
      try files.createDirectory(at: destination, withIntermediateDirectories: true)
      let result = try run(URL(fileURLWithPath: "/usr/bin/tar"),
        ["-xzf", try resource("Toolchains/\(archive)").path, "--strip-components=1", "-C", destination.path])
      guard result.status == 0 else { throw MotionError("Cannot unpack \(name): \(result.output)") }
    }
    return try body(temporary, temporary)
  }

  private func run(
    _ executable: URL, _ arguments: [String], directory: URL? = nil, environment: [String: String] = [:]
  ) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    if !environment.isEmpty {
      process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "Invalid UTF-8 output")
  }

  private func inspect(metadata: URL) throws {
    let graph = try JSONDecoder().decode(CompilerGraph.self, from: Data(contentsOf: metadata))
    for output in graph.outputs.values {
      for dependency in output.imports where dependency.external == true {
        throw MotionError("ms/unsupported-package: \(dependency.path)")
      }
    }
  }

  private func inspect(files: [String], vendor: URL, subset: Bool = true) throws {
    guard let context = JSContext() else { throw MotionError("Cannot create compiler inspector") }
    context.evaluateScript(try String(contentsOf: resource("inspect.js"), encoding: .utf8))
    for file in files where !file.isEmpty {
      let url = URL(fileURLWithPath: file).standardizedFileURL.resolvingSymlinksInPath()
      if file.hasSuffix(".d.ts") || file.hasSuffix(".d.mts") || file.hasSuffix(".d.cts")
        || url.path.hasPrefix(vendor.resolvingSymlinksInPath().path + "/") || url.pathExtension == "json" { continue }
      let source = try String(contentsOf: url, encoding: .utf8)
      let result = context.objectForKeyedSubscript("MotionInspector")?.forProperty("inspect")?.call(withArguments: [
        source, url.path, subset && !url.path.contains("node_modules"),
      ])
      if let error = context.exception { throw MotionError("Compiler: \(error.toString() ?? "inspection failed")") }
      guard result?.toString() == "[]" else { throw MotionError(result?.toString() ?? "Compiler inspection failed") }
    }
  }
}

extension Compiler {
  fileprivate func resource(_ path: String) throws -> URL {
    guard let root = Bundle.module.resourceURL?.appendingPathComponent("Resources") else {
      throw MotionError("Missing embedded compiler resources")
    }
    let url = root.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw MotionError("Missing embedded compiler resource: \(path). Run make compiler before building.")
    }
    return url
  }

  fileprivate func quoted(_ string: String) throws -> String {
    String(bytes: try JSONEncoder().encode(string), encoding: .utf8) ?? "\"\""
  }

  /// Maps esbuild resolution failures back to the original import locations.
  fileprivate func importHints(project: URL, output: String) throws -> String {
    let locations = try PortableCompiler().importLocations(files: PortableCompiler.sources(in: project))
    return locations.filter { output.contains("\"" + $0.specifier + "\"") }.map {
      "\($0.file):\($0.line):\($0.col): cannot resolve import '\($0.specifier)'; "
        + "check paths, package exports and installed dependencies"
    }.joined(separator: "\n")
  }
}

private extension Compiler {
  func diagnostics(_ output: String, status: Int32) throws -> [Diagnostic] {
    if status == 0 { return [] }
    let located = try NSRegularExpression(pattern: #"^(.*)\((\d+),(\d+)\): error TS(\d+): (.*)$"#)
    let global = try NSRegularExpression(pattern: #"^error TS(\d+): (.*)$"#)
    var values: [[String: Any]] = []
    for line in output.components(separatedBy: .newlines) where !line.isEmpty {
      let range = NSRange(line.startIndex..., in: line)
      if let match = located.firstMatch(in: line, range: range) {
        func group(_ index: Int) -> String { (line as NSString).substring(with: match.range(at: index)) }
        values.append(["rule": "ts/\(group(4))", "file": group(1), "line": Int(group(2)) ?? 1,
          "col": Int(group(3)) ?? 1, "message": group(5)])
      } else if let match = global.firstMatch(in: line, range: range) {
        values.append(["rule": "ts/\((line as NSString).substring(with: match.range(at: 1)))", "file": "",
          "line": 1, "col": 1, "message": (line as NSString).substring(with: match.range(at: 2))])
      } else if !values.isEmpty {
        values[values.count - 1]["message"] = (values.last?["message"] as? String ?? "") + "\n" + line
      } else { throw MotionError("TypeScript 7 exited with status \(status): \(output)") }
    }
    guard !values.isEmpty else { throw MotionError("TypeScript 7 exited with status \(status)") }
    return try JSONDecoder().decode([Diagnostic].self, from: JSONSerialization.data(withJSONObject: values))
  }
}

private extension Compiler {
  func resolutionOptions(project: URL) throws -> [String: Any] {
    // Without a root tsconfig there are no aliases or inherited options to resolve.
    // Avoid loading the portable JS compiler and reading every project source just for this check.
    guard FileManager.default.fileExists(atPath: project.appendingPathComponent("tsconfig.json").path) else { return [:] }
    return try PortableCompiler().resolutionOptions(files: PortableCompiler.sources(in: project))
  }

}

private struct CompilerGraph: Decodable {
  let inputs: [String: CompilerInput]
  let outputs: [String: CompilerOutput]
}

private struct CompilerInput: Decodable {}

private struct CompilerOutput: Decodable {
  let imports: [CompilerImport]
}

private struct CompilerImport: Decodable {
  let path: String
  let external: Bool?
}
#endif

#if os(macOS)
/// Bounded process-local graph cache. All project source/config/package bytes participate in the
/// identity; external inputs reported by esbuild are checked again before returning a hit.
private final class NativeGraphCache {
  private let lock = NSLock()
  private var entries: [String: (ModuleGraph, [URL: String])] = [:]
  private var counts = CompilerCacheStatistics()
  var statistics: CompilerCacheStatistics { lock.lock(); defer { lock.unlock() }; return counts }
  func clear() { lock.lock(); defer { lock.unlock() }; entries.removeAll(); counts = .init() }

  static func manifest(_ root: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]) else { throw MotionError("Cannot read project: \(root.path)") }
    let extensions: Set<String> = ["ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs", "json"]
    for case let url as URL in enumerator {
      guard extensions.contains(url.pathExtension),
        try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
      else { continue }
      result[String(url.path.dropFirst(root.path.count))] = CompilerContent.hash(try Data(contentsOf: url))
    }
    return result
  }

  func lookup(_ key: String) -> ModuleGraph? {
    lock.lock(); defer { lock.unlock() }
    if let (graph, dependencies) = entries[key], dependencies.allSatisfy({ url, hash in
      (try? CompilerContent.hash(Data(contentsOf: url))) == hash
    }) { counts.hits += 1; return graph }
    counts.misses += 1
    return nil
  }

  func store(_ key: String, graph: ModuleGraph, dependencies: [URL]) throws {
    var hashes: [URL: String] = [:]
    for url in dependencies { hashes[url] = CompilerContent.hash(try Data(contentsOf: url)) }
    lock.lock(); defer { lock.unlock() }
    if entries.count >= 8 { entries.removeAll() }
    entries[key] = (graph, hashes)
  }
}
#endif
