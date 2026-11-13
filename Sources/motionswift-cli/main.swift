import Foundation
import MotionCompiler
import MotionCore
import MotionEncode
import MotionRender
import MotionRuntime

nonisolated(unsafe) private var interrupted: Int32 = 0

struct Arguments {
  var options: [String: String] = [:]
  var positional: [String] = []

  init(_ input: [String]) throws {
    let allowed: Set<String> = [
      "project", "entry", "frame", "frames", "props", "report-json", "dump-layout", "codec",
      "concurrency", "backend", "scale", "encoder", "compiler", "stamp", "port", "host",
      "quality", "pixel-format", "frame-step", "segments",
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
    if let value = options["codec"], VideoCodec(rawValue: value) == nil {
      throw MotionError("--codec must be h264, hevc, prores, or prores4444")
    }
    if let value = options["encoder"], VideoEncoder(rawValue: value) == nil {
      throw MotionError("--encoder must be software, videotoolbox, or videotoolbox-shared")
    }
    if options["encoder"] == "videotoolbox-shared", backend != .gpu {
      throw MotionError("--encoder=videotoolbox-shared requires --backend=gpu")
    }
    if let value = options["quality"], Double(value) == nil { throw MotionError("Invalid --quality") }
    if let value = options["pixel-format"], VideoPixelFormat(rawValue: value) == nil { throw MotionError("Invalid --pixel-format") }
    if let value = options["frame-step"], (Int(value) ?? 0) < 1 { throw MotionError("--frame-step must be a positive integer") }
    if options["frames"] != nil && options["segments"] != nil { throw MotionError("Use --frames or --segments") }
    _ = try encodingOptions
    if let value = options["concurrency"], value != "auto", (Int(value) ?? 0) < 1 {
      throw MotionError("--concurrency must be a positive integer or auto")
    }
    if let value = options["scale"], !((Double(value) ?? 0) > 0) {
      throw MotionError("--scale must be a positive number")
    }
  }

  var encodingOptions: EncodingOptions {
    get throws {
      try EncodingOptions(codec: options["codec"].flatMap(VideoCodec.init) ?? .h264, encoder: encoder,
                          pixelFormat: options["pixel-format"].flatMap(VideoPixelFormat.init),
                          quality: options["quality"].flatMap(Double.init))
    }
  }
  var backend: RenderBackend { options["backend"].flatMap(RenderBackend.init) ?? .cpu }
  var encoder: VideoEncoder {
    options["encoder"].flatMap(VideoEncoder.init) ?? .software
  }
  var scale: Double { options["scale"].flatMap(Double.init) ?? 1 }
  /// Render workers. `auto` (the default) uses half the cores, leaving the rest for
  /// ffmpeg/x264, which encodes concurrently.
  var concurrency: Int {
    options["concurrency"].flatMap(Int.init)
      ?? max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
  }
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
      motionswift render --project <dir> --entry <file> <composition> <out.mp4> --codec=h264|hevc|prores|prores4444
      motionswift graph --project <dir> --entry <file> <out.msgraph> [--compiler=tsgo|portable --stamp=true]
      motionswift serve-graph --project <dir> --entry <file> [--port=4317 --host=127.0.0.1]
      motionswift budget --project <dir> --entry <file> <composition> [--frames=a-b --scale=N --compiler=portable|tsgo]
      Options: --frames=a-b --props=file.json --report-json=file --dump-layout=file
               --backend=cpu|gpu (Skia raster or Skia Metal) --concurrency=N|auto --scale=N
               --encoder=software|videotoolbox|videotoolbox-shared (default: software)
               --quality=N --pixel-format=yuv420p|yuv422p10le|yuva444p10le
               --frame-step=N (output fps = source fps / N) --segments=a-b,c-d (ordered inclusive ranges)
      Phase 0: macOS, synchronous React, strict box subset, parallel frame workers, silent video.
      """)
    return
  }
  let command = input[0]
  guard ["check", "list", "still", "render"].contains(command) || DeviceCommands.names.contains(command) else {
    throw MotionError("Unknown command: \(command)")
  }
  let arguments = try Arguments(Array(input.dropFirst()))
  if DeviceCommands.names.contains(command) {
    try DeviceCommands.run(command, arguments)
    return
  }
  let project = URL(fileURLWithPath: arguments.options["project"] ?? ".").standardizedFileURL
  let startup = Date()
  if command == "check" {
    let diagnostics = try Compiler().checkTypes(
      project: project, entry: arguments.options["entry"] ?? "src/index.ts")
    if !diagnostics.isEmpty {
      print(String(bytes: try JSONEncoder().encode(diagnostics), encoding: .utf8) ?? "[]")
      throw MotionError("Type checking failed")
    }
  }
  let bundle = try Compiler().compile(
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
  let step = Int(arguments.options["frame-step"] ?? "1")!
  let segments = try FrameSelection.segments(arguments.options["segments"] ?? arguments.options["frames"],
                                              duration: composition.durationInFrames, step: step)
  let frames: [Int]
  if command == "still" {
    guard let frame = Int(arguments.options["frame"] ?? "0"), frame >= 0, frame < composition.durationInFrames else {
      throw MotionError("Invalid --frame")
    }
    frames = [frame]
  } else { frames = segments.flatMap { $0 } }
  let options = PipelineOptions(
    workers: arguments.concurrency, backend: arguments.backend, scale: arguments.scale,
    sharedVideoFrames: arguments.encoder == .sharedSurface)
  let renderStart = Date()
  var timings: [Double] = []
  var stages: [String: JSONValue] = [:]
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
    let settings = try arguments.encodingOptions
    let fps = composition.fps / Double(step)
    try settings.validate(width: size.width, height: size.height, fps: fps, output: output)
    let preflight = Date()
    let transaction = try SegmentOutput(output: output)
    if arguments.encoder == .sharedSurface {
      try SharedVideoStream.checkAvailability(output: transaction.directory.appendingPathComponent("probe." + settings.fileExtension),
                                       width: size.width, height: size.height, fps: fps, options: settings)
    } else {
      try VideoStream.checkAvailability(options: settings, width: size.width, height: size.height, fps: fps)
    }
    stages["availabilityMs"] = .number(Date().timeIntervalSince(preflight) * 1000)
    var writeMs = 0.0
    var finishMs = 0.0
    for (index, segment) in segments.enumerated() {
      guard interrupted == 0 else { throw MotionError("Render cancelled") }
      let target = transaction.segment(index)
      let shared = arguments.encoder == .sharedSurface
        ? try SharedVideoStream(output: target, width: size.width, height: size.height, fps: fps, options: settings) : nil
      let stream = arguments.encoder == .sharedSurface ? nil : try VideoStream(
        output: target, width: size.width, height: size.height, fps: fps, options: settings)
      do {
        try FramePipeline.run(bundle: bundle, composition: composition, frames: segment, props: props, options: options) { frame in
          guard interrupted == 0 else { throw MotionError("Render cancelled") }
          let begin = Date()
          if let shared, let videoFrame = frame.videoFrame {
            try shared.write(videoFrame.pixelBuffer)
          } else if let stream {
            try stream.write(frame.pixels)
          } else { throw MotionError("Missing shared video frame") }
          writeMs += Date().timeIntervalSince(begin) * 1000
          if let path = arguments.options["dump-layout"] { try writeJSON(frame.layout, to: path) }
          timings.append(frame.renderMs)
        }
        let begin = Date()
        try stream?.finish()
        try shared?.finish()
        finishMs += Date().timeIntervalSince(begin) * 1000
      } catch { stream?.cancel(); shared?.cancel(); throw error }
    }
    let concat = Date()
    try transaction.publish(count: segments.count, cancelled: { interrupted != 0 })
    stages["concatAndPublishMs"] = .number(Date().timeIntervalSince(concat) * 1000)
    stages["encodeWriteMs"] = .number(writeMs)
    stages["encodeFinishMs"] = .number(finishMs)
    stages["segments"] = .number(Double(segments.count))
    stages["outputFps"] = .number(fps)
    stages["codec"] = .string(settings.codec.rawValue)
    stages["pixelFormat"] = .string(settings.pixelFormat.rawValue)
    stages["quality"] = .number(settings.quality)
    stages["frameStep"] = .number(Double(step))
  }

  if let path = arguments.options["report-json"] {
    try writeReport(
      to: path, timings: timings, startupMs: startupMs, totalMs: Date().timeIntervalSince(renderStart) * 1000,
      options: options, encoder: command == "render" ? try arguments.encodingOptions.label : "png", extraStages: stages)
  }
}

func writeReport(
  to path: String, timings: [Double], startupMs: Double, totalMs: Double, options: PipelineOptions,
  encoder: String, extraStages: [String: JSONValue] = [:]
) throws {
  let sorted = timings.sorted()
  let report: [String: JSONValue] = [
    "startupMs": .number(startupMs), "frames": .number(Double(timings.count)),
    "backend": .string(options.backend.label), "workers": .number(Double(options.workers)),
    "scale": .number(options.scale),
    "encoder": .string(encoder),
    "stages": .object([
      "frameMs": .object([
        "p50": .number(sorted[sorted.count / 2]),
        "p95": .number(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]),
      ]),
      // Rendering and encoding overlap: this is wall time from first frame to finished file.
      "renderAndEncodeMs": .number(totalMs),
    ].merging(extraStages) { _, new in new }),
  ]
  try writeJSON(report, to: path)
}

// A dead ffmpeg must surface as a write error, not kill the process with SIGPIPE.
signal(SIGPIPE, SIG_IGN)
signal(SIGINT) { _ in interrupted = 1 }
signal(SIGTERM) { _ in interrupted = 1 }
do { try run() } catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
