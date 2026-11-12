import Foundation
import MotionCompiler
import MotionCore
import MotionEncode
import MotionRender
import MotionRuntime

struct Arguments {
  var options: [String: String] = [:]
  var positional: [String] = []

  init(_ input: [String]) throws {
    let allowed: Set<String> = [
      "project", "entry", "frame", "frames", "props", "report-json", "dump-layout", "codec",
      "concurrency", "backend", "scale",
    ]
    var index = 0
    while index < input.count {
      let token = input[index]
      if token.hasPrefix("--") {
        let pieces = token.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
        guard let key = pieces.first, allowed.contains(key), options[key] == nil else {
          throw MotionError("Unknown or repeated option: \(token)")
        }
        if pieces.count == 2 {
          options[key] = pieces[1]
        } else {
          index += 1
          guard index < input.count, !input[index].hasPrefix("--") else {
            throw MotionError("Missing value: \(token)")
          }
          options[key] = input[index]
        }
      } else {
        positional.append(token)
      }
      index += 1
    }
    if let value = options["backend"], RenderBackend(rawValue: value) == nil {
      throw MotionError("--backend must be cpu or gpu")
    }
    if let value = options["codec"], value != "h264" {
      throw MotionError("Only --codec=h264 is implemented")
    }
    if let value = options["concurrency"], value != "auto", (Int(value) ?? 0) < 1 {
      throw MotionError("--concurrency must be a positive integer or auto")
    }
    if let value = options["scale"], !((Double(value) ?? 0) > 0) {
      throw MotionError("--scale must be a positive number")
    }
  }

  var backend: RenderBackend { options["backend"].flatMap(RenderBackend.init) ?? .cpu }
  var scale: Double { options["scale"].flatMap(Double.init) ?? 1 }
  /// Render workers. `auto` (the default) uses half the cores, leaving the rest for
  /// ffmpeg/x264, which encodes concurrently.
  var concurrency: Int {
    options["concurrency"].flatMap(Int.init)
      ?? max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
  }
}

func repository() throws -> URL {
  if let home = ProcessInfo.processInfo.environment["MOTIONSWIFT_HOME"] {
    return URL(fileURLWithPath: home)
  }
  let starts = [
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent(),
  ]
  for start in starts {
    var candidate = start
    while candidate.path != "/" {
      if FileManager.default.fileExists(
        atPath: candidate.appendingPathComponent("js/compiler/compile.cjs").path) {
        return candidate
      }
      candidate.deleteLastPathComponent()
    }
  }
  throw MotionError("Set MOTIONSWIFT_HOME to the repository containing js/compiler/compile.cjs")
}

func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(value).write(to: URL(fileURLWithPath: path), options: .atomic)
}

func run() throws {
  let input = Array(CommandLine.arguments.dropFirst())
  if input == ["--version"] {
    print("motionswift 0.2.0-phase0")
    return
  }
  if input.isEmpty || input == ["--help"] {
    print(
      """
      motionswift check|list --project <dir> --entry <file>
      motionswift still --project <dir> --entry <file> <composition> <out.png> --frame=0
      motionswift render --project <dir> --entry <file> <composition> <out.mp4> --codec=h264
      Options: --frames=a-b --props=file.json --report-json=file --dump-layout=file
               --backend=cpu|gpu (Skia raster or Skia Metal) --concurrency=N|auto --scale=N
      Phase 0: macOS, synchronous React, strict box subset, parallel frame workers, silent H.264.
      """)
    return
  }
  let command = input[0]
  guard ["check", "list", "still", "render"].contains(command) else {
    throw MotionError("Unknown command: \(command)")
  }
  let arguments = try Arguments(Array(input.dropFirst()))
  let project = URL(fileURLWithPath: arguments.options["project"] ?? ".").standardizedFileURL
  let startup = Date()
  if command == "check" {
    let diagnostics = try Compiler(repository: repository()).checkTypes(
      project: project, entry: arguments.options["entry"] ?? "src/index.ts")
    if !diagnostics.isEmpty {
      print(String(bytes: try JSONEncoder().encode(diagnostics), encoding: .utf8) ?? "[]")
      throw MotionError("Type checking failed")
    }
  }
  let bundle = try Compiler(repository: repository()).compile(
    project: project, entry: arguments.options["entry"] ?? "src/index.ts")
  let runtime = try Runtime(bundle: bundle)
  let catalog = try runtime.compositions()
  if command == "list" {
    let data = try JSONEncoder().encode(catalog)
    print(String(bytes: data, encoding: .utf8) ?? "[]")
    return
  }
  let props =
    try arguments.options["props"].map { try String(contentsOfFile: $0, encoding: .utf8) } ?? "{}"
  if command == "check" {
    guard arguments.positional.isEmpty else {
      throw MotionError("check takes no positional arguments")
    }
    // Validate the dynamically produced styles as well as the compiler's static diagnostics.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for composition in catalog {
      let tree = try runtime.frame(composition: composition, number: 0, props: props)
      _ = try Renderer(width: composition.width, height: composition.height)
        .render(tree, composition: composition, to: directory.appendingPathComponent("check.png"))
    }
    print("[]")
    return
  }
  try render(
    arguments: arguments, bundle: bundle, runtime: runtime, catalog: catalog, props: props,
    startup: startup)
}

func render(
  arguments: Arguments, bundle: String, runtime: Runtime, catalog: [Composition], props: String,
  startup: Date
) throws {
  let command = CommandLine.arguments[1]
  guard arguments.positional.count == 2 else {
    throw MotionError("Expected <composition> <output>")
  }
  guard let composition = catalog.first(where: { $0.id == arguments.positional[0] }) else {
    throw MotionError("Unknown composition: \(arguments.positional[0])")
  }
  let output = URL(fileURLWithPath: arguments.positional[1])
  try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
  let startupMs = Date().timeIntervalSince(startup) * 1000
  let frames: [Int]
  if command == "still" {
    guard let frame = Int(arguments.options["frame"] ?? "0") else {
      throw MotionError("Invalid --frame")
    }
    frames = [frame]
  } else if let range = arguments.options["frames"] {
    let tokens = range.split(separator: "-", omittingEmptySubsequences: false)
    let parts = tokens.compactMap { Int($0) }
    guard tokens.count == 2, parts.count == 2, parts[0] >= 0, parts[1] >= parts[0],
      parts[1] < composition.durationInFrames
    else {
      throw MotionError("Invalid --frames; expected inclusive a-b in composition range")
    }
    frames = Array(parts[0]...parts[1])
  } else {
    frames = Array(0..<composition.durationInFrames)
  }
  let options = PipelineOptions(
    workers: arguments.concurrency, backend: arguments.backend, scale: arguments.scale)
  let renderStart = Date()
  var timings: [Double] = []
  if command == "still" {
    let begin = Date()
    let node = try runtime.frame(composition: composition, number: frames[0], props: props)
    let layout = try Renderer(
      width: composition.width, height: composition.height, scale: options.scale,
      backend: options.backend
    ).render(node, composition: composition, to: output)
    if let path = arguments.options["dump-layout"] { try writeJSON(layout, to: path) }
    timings.append(Date().timeIntervalSince(begin) * 1000)
  } else {
    let size = try Renderer.pixelSize(
      width: composition.width, height: composition.height, scale: options.scale)
    let stream = try VideoStream(
      output: output, width: size.width, height: size.height, fps: composition.fps)
    do {
      try FramePipeline.run(
        bundle: bundle, composition: composition, frames: frames, props: props, options: options
      ) { frame in
        try stream.write(frame.pixels)
        if let path = arguments.options["dump-layout"] { try writeJSON(frame.layout, to: path) }
        timings.append(frame.renderMs)
      }
    } catch {
      stream.cancel()
      throw error
    }
    try stream.finish()
  }
  if let path = arguments.options["report-json"] {
    try writeReport(
      to: path, timings: timings, startupMs: startupMs, totalMs: Date().timeIntervalSince(renderStart) * 1000,
      options: options, streamed: command == "render")
  }
}

func writeReport(
  to path: String, timings: [Double], startupMs: Double, totalMs: Double, options: PipelineOptions,
  streamed: Bool
) throws {
  let sorted = timings.sorted()
  let report: [String: JSONValue] = [
    "startupMs": .number(startupMs), "frames": .number(Double(timings.count)),
    "backend": .string(options.backend.label), "workers": .number(Double(options.workers)),
    "scale": .number(options.scale),
    "encoder": .string(streamed ? "ffmpeg-libx264-rawvideo-pipe" : "png"),
    "stages": .object([
      "frameMs": .object([
        "p50": .number(sorted[sorted.count / 2]),
        "p95": .number(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]),
      ]),
      // Rendering and encoding overlap: this is wall time from first frame to finished file.
      "renderAndEncodeMs": .number(totalMs),
    ]),
  ]
  try writeJSON(report, to: path)
}

// A dead ffmpeg must surface as a write error, not kill the process with SIGPIPE.
signal(SIGPIPE, SIG_IGN)
do { try run() } catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
