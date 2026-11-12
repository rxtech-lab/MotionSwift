import Foundation
import JavaScriptCore
import MotionCore

/// Native TypeScript 7 (tsgo) emits and checks TS/TSX; esbuild links the emitted JavaScript.
public struct Compiler {
  /// Retained for source compatibility; compiler assets come from the package bundle.
  public let repository: URL

  public init(repository: URL) { self.repository = repository }
  public init() { repository = Bundle.module.bundleURL }

  public func compile(project: URL, entry: String) throws -> String {
    try withToolchain { toolchain, temporary in
      let vendor = try resource("Vendor")
      let emitted = temporary.appendingPathComponent("emitted")
      let config = try configuration(project: project, entry: entry, vendor: vendor, temporary: temporary,
        emit: emitted)
      let compilation = try run(toolchain.appendingPathComponent("typescript/lib/tsc"),
        ["--project", config.path, "--pretty", "false", "--listFiles"], directory: project)
      guard compilation.status == 0 else { throw MotionError("tsgo: \(compilation.output)") }
      try inspect(files: compilation.output.components(separatedBy: .newlines), vendor: vendor)
      let javascriptExtension = ["mts": "mjs", "cts": "cjs"][project.appendingPathComponent(entry).pathExtension] ?? "js"
      let compiledEntry = emitted.appendingPathComponent(entry).deletingPathExtension()
        .appendingPathExtension(javascriptExtension)
      let bootstrap = temporary.appendingPathComponent("entry.js")
      let output = temporary.appendingPathComponent("bundle.js")
      let metadata = temporary.appendingPathComponent("meta.json")
      let source = """
        import \(try quoted(compiledEntry.standardizedFileURL.path));
        export {default as react} from \(try quoted(vendor.appendingPathComponent("node_modules/react/index.js").path));
        export {default as reconciler} from \(try quoted(vendor.appendingPathComponent("node_modules/react-reconciler/index.js").path));
        export * as shim from \(try quoted(vendor.appendingPathComponent("shim/index.js").path));
        """
      try source.write(to: bootstrap, atomically: true, encoding: .utf8)
      var arguments = [bootstrap.path, "--bundle", "--platform=browser", "--format=iife",
        "--global-name=__ms_compiled", "--target=es2022", "--packages=external",
        "--define:process.env.NODE_ENV=\"production\"", "--log-level=warning",
        "--outfile=\(output.path)", "--metafile=\(metadata.path)"]
      for name in ["react", "react-reconciler", "scheduler"] {
        arguments.append("--alias:\(name)=\(vendor.appendingPathComponent("node_modules/\(name)").path)")
      }
      arguments.append("--alias:@motionswift/remotion=\(vendor.appendingPathComponent("shim").path)")
      arguments.append("--alias:remotion=\(vendor.appendingPathComponent("shim/index.js").path)")
      let result = try run(toolchain.appendingPathComponent("esbuild/bin/esbuild"), arguments, directory: project)
      guard result.status == 0 else { throw MotionError("esbuild: \(result.output)") }
      try inspect(metadata: metadata)
      return try String(contentsOf: output, encoding: .utf8) + """
        \nconst __ms_ids={react:'react',reconciler:'reconciler',shim:'shim'};
        function __ms_require(id){return __ms_compiled[id];}
        __ms_start();
        """
    }
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
        "react": [modules.appendingPathComponent("@types/react/index.d.ts").path],
        "react/jsx-runtime": [modules.appendingPathComponent("@types/react/jsx-runtime.d.ts").path]],
    ]
    if let emit {
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

  private func resource(_ path: String) throws -> URL {
    guard let root = Bundle.module.resourceURL?.appendingPathComponent("Resources") else {
      throw MotionError("Missing embedded compiler resources")
    }
    let url = root.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw MotionError("Missing embedded compiler resource: \(path). Run make compiler before building.")
    }
    return url
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

  private func run(_ executable: URL, _ arguments: [String], directory: URL? = nil) throws
    -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "Invalid UTF-8 output")
  }

  private func quoted(_ string: String) throws -> String {
    String(bytes: try JSONEncoder().encode(string), encoding: .utf8) ?? "\"\""
  }

  private func inspect(metadata: URL) throws {
    let graph = try JSONDecoder().decode(CompilerGraph.self, from: Data(contentsOf: metadata))
    for output in graph.outputs.values {
      for dependency in output.imports where dependency.external == true {
        throw MotionError("ms/unsupported-package: \(dependency.path)")
      }
    }
  }

  private func inspect(files: [String], vendor: URL) throws {
    guard let context = JSContext() else { throw MotionError("Cannot create compiler inspector") }
    context.evaluateScript(try String(contentsOf: resource("inspect.js"), encoding: .utf8))
    for file in files where !file.isEmpty {
      let url = URL(fileURLWithPath: file).standardizedFileURL.resolvingSymlinksInPath()
      if file.hasSuffix(".d.ts") || file.hasSuffix(".d.mts") || file.hasSuffix(".d.cts")
        || url.path.hasPrefix(vendor.resolvingSymlinksInPath().path + "/") || url.pathExtension == "json" { continue }
      let source = try String(contentsOf: url, encoding: .utf8)
      let result = context.objectForKeyedSubscript("MotionInspector")?.forProperty("inspect")?.call(withArguments: [
        source, url.path, !url.path.contains("node_modules"),
      ])
      if let error = context.exception { throw MotionError("Compiler: \(error.toString() ?? "inspection failed")") }
      guard result?.toString() == "[]" else { throw MotionError(result?.toString() ?? "Compiler inspection failed") }
    }
  }

  private func diagnostics(_ output: String, status: Int32) throws -> [Diagnostic] {
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

private struct CompilerGraph: Decodable {
  let outputs: [String: CompilerOutput]
}

private struct CompilerOutput: Decodable {
  let imports: [CompilerImport]
}

private struct CompilerImport: Decodable {
  let path: String
  let external: Bool?
}
