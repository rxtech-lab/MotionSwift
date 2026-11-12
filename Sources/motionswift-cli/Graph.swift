import Foundation
import MotionCompiler
import MotionCore
import MotionPortable
import MotionRender
import MotionRuntime
import Network

/// `motionswift graph`, `serve-graph` and `budget`: the Mac side of iOS/iPadOS support.
enum DeviceCommands {
  static let names: Set<String> = ["graph", "serve-graph", "budget"]

  static func run(_ command: String, _ arguments: Arguments) throws {
    let project = URL(fileURLWithPath: arguments.options["project"] ?? ".").standardizedFileURL
    let entry = arguments.options["entry"] ?? "src/index.ts"
    switch command {
    case "graph":
      guard arguments.positional.count == 1 else { throw MotionError("Expected <out.msgraph>") }
      let graph = try compileGraph(project: project, entry: entry, arguments: arguments)
      try graph.encoded().write(to: URL(fileURLWithPath: arguments.positional[0]), options: .atomic)
      print("\(graph.modules.count) modules, packages: \(graph.packages.joined(separator: ", ")), vendor: \(graph.vendor)")
    case "serve-graph":
      try serve(project: project, entry: entry, arguments: arguments)
    default:
      try budget(project: project, entry: entry, arguments: arguments)
    }
  }

  /// `--compiler=tsgo` (default for graphs: bundles npm packages) or `portable` (the on-device
  /// compiler, which also accepts `--stamp=true` for editor stamps).
  static func compileGraph(project: URL, entry: String, arguments: Arguments) throws -> ModuleGraph {
    switch arguments.options["compiler"] ?? "tsgo" {
    case "tsgo": return try Compiler().graph(project: project, entry: entry)
    case "portable":
      return try PortableCompiler().compile(
        project: project, entry: entry, stamp: arguments.options["stamp"] == "true")
    default: throw MotionError("--compiler must be tsgo or portable")
    }
  }

  // MARK: serve-graph

  /// Serves `GET /graph` (recompiled on every request, so devices always get the saved sources)
  /// and `GET /health`. Bind to 127.0.0.1 for the simulator, or `--host=0.0.0.0` for devices on
  /// the local network.
  static func serve(project: URL, entry: String, arguments: Arguments) throws {
    let port = NWEndpoint.Port(rawValue: UInt16(arguments.options["port"] ?? "4317") ?? 0) ?? 4317
    let host = arguments.options["host"] ?? "127.0.0.1"
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: port)
    let listener = try NWListener(using: parameters)
    let queue = DispatchQueue(label: "motionswift.serve-graph")
    listener.newConnectionHandler = { connection in
      connection.start(queue: queue)
      receive(connection) { path in
        let response: Response
        switch path {
        case "/health": response = Response(status: 200, type: "text/plain", body: Data("ok".utf8))
        case "/graph":
          do {
            let graph = try compileGraph(project: project, entry: entry, arguments: arguments)
            response = Response(status: 200, type: "application/json", body: try graph.encoded())
            print("served graph: \(graph.modules.count) modules, \(graph.packages.count) packages")
          } catch {
            response = Response(status: 500, type: "text/plain", body: Data("\(error)".utf8))
            FileHandle.standardError.write(Data("graph failed: \(error)\n".utf8))
          }
        default: response = Response(status: 404, type: "text/plain", body: Data("not found".utf8))
        }
        var head = "HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Error")\r\n"
        head += "Content-Type: \(response.type)\r\nContent-Length: \(response.body.count)\r\n"
        head += "X-MotionSwift-Vendor: \(Vendor.identity)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
      }
    }
    listener.stateUpdateHandler = { state in
      switch state {
      case .ready: print("Serving \(project.path) (\(entry)) at http://\(host):\(port)/graph")
      case .failed(let error):
        FileHandle.standardError.write(Data("serve-graph failed: \(error)\n".utf8))
        exit(1)
      default: break
      }
    }
    listener.start(queue: queue)
    dispatchMain()
  }

  private struct Response {
    let status: Int
    let type: String
    let body: Data
  }

  private static func receive(_ connection: NWConnection, buffer: Data = Data(), handler: @escaping @Sendable (String) -> Void) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, complete, error in
      var buffer = buffer
      if let data { buffer.append(data) }
      if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
        let head = String(bytes: buffer[..<end.lowerBound], encoding: .utf8) ?? ""
        let parts = head.split(separator: " ")
        let path = parts.count > 1 && parts[0] == "GET" ? String(parts[1].split(separator: "?")[0]) : ""
        handler(path)
      } else if complete || error != nil || buffer.count > 65536 {
        connection.cancel()
      } else {
        receive(connection, buffer: buffer, handler: handler)
      }
    }
  }

  // MARK: budget

  /// Prints a preview budget report (JSON). Run with `JSC_useJIT=false` to measure the
  /// interpreter that iOS and iPadOS devices use.
  static func budget(project: URL, entry: String, arguments: Arguments) throws {
    guard arguments.positional.count == 1 else { throw MotionError("Expected <composition>") }
    let bundle: String
    switch arguments.options["compiler"] ?? "portable" {
    case "portable": bundle = try GraphLinker.link(PortableCompiler().compile(project: project, entry: entry))
    case "tsgo": bundle = try Compiler().compile(project: project, entry: entry)
    default: throw MotionError("--compiler must be tsgo or portable")
    }
    let catalog = try Runtime(bundle: bundle).compositions()
    guard let composition = catalog.first(where: { $0.id == arguments.positional[0] }) else {
      throw MotionError("Unknown composition: \(arguments.positional[0])")
    }
    var frames: [Int]?
    if let range = arguments.options["frames"] {
      let parts = range.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 2, parts[0] >= 0, parts[1] >= parts[0], parts[1] < composition.durationInFrames else {
        throw MotionError("Invalid --frames; expected inclusive a-b in composition range")
      }
      frames = Array(parts[0]...parts[1])
    }
    let report = try PreviewBudget.measure(
      bundle: bundle, composition: composition, frames: frames, scale: arguments.scale, backend: arguments.backend)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(bytes: try encoder.encode(report), encoding: .utf8) ?? "{}")
    FileHandle.standardError.write(Data((report.summary + "\n").utf8))
  }
}
