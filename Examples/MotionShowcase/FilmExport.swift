import Foundation
import MotionCore
import MotionEncode
import MotionRender
import Observation
import OSLog

private final class RenderCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  func cancel() { lock.withLock { cancelled = true } }
  func check() throws {
    if lock.withLock({ cancelled }) { throw CancellationError() }
  }
}

@MainActor
@Observable
final class FilmExport {
  private nonisolated static let logger = Logger(subsystem: "app.rxlab.MotionSwift", category: "FilmExport")
  private nonisolated static var debugLogging: Bool {
    #if DEBUG
    true
    #else
    ProcessInfo.processInfo.environment["MOTIONSWIFT_RENDER_DEBUG"] == "1"
    #endif
  }

  private nonisolated static func log(_ message: String, baseline: UInt64?, started: Date) {
    guard debugLogging else { return }
    let bytes = AppMemory.residentBytes()
    let delta = bytes.flatMap { current in baseline.map { Int64(current) - Int64($0) } }
    let growth = delta.map { String(format: "%+.1f MiB", Double($0) / 1_048_576) } ?? "unavailable"
    let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
    let entry = "\(message) elapsed=\(elapsed)s RSS=\(AppMemory.formatted(bytes)) delta=\(growth)"
    logger.notice("\(entry, privacy: .public)")
  }

  var isRunning = false
  var completedFrames = 0
  var totalFrames = 0
  var currentBytes: UInt64?
  var peakBytes: UInt64?
  var output: URL?
  var error: String?
  var status = "Ready to render"
  private var cancellation = RenderCancellation()

  func sampleMemory() {
    currentBytes = AppMemory.residentBytes()
    if isRunning, let currentBytes { peakBytes = max(peakBytes ?? 0, currentBytes) }
  }

  func cancel() {
    cancellation.cancel()
    status = "Stopping…"
  }

  func render(bundle: String, composition: Composition, destination: URL, workers: Int) async {
    guard !isRunning else { return }
    isRunning = true
    completedFrames = 0
    totalFrames = composition.durationInFrames
    output = nil
    error = nil
    peakBytes = nil
    cancellation = RenderCancellation()
    let token = cancellation
    let started = Date()
    let baseline = AppMemory.residentBytes()
    Self.log("Export start frames=\(composition.durationInFrames) size=\(composition.width)x\(composition.height) workers=\(workers)",
             baseline: baseline, started: started)
    sampleMemory()
    status = "Rendering composition…"
    // Encode alongside the destination; publish only a finished movie, preserving any previous file.
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID()).mp4")
    do {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let thread = Thread {
          let result = Result {
            try Self.encode(bundle: bundle, composition: composition, output: temporary, workers: workers,
                            cancellation: token) { count in
              Task { @MainActor in
                self.completedFrames = count
                self.sampleMemory()
                if count == composition.durationInFrames { self.status = "Finishing video…" }
              }
            }
            try token.check()
            if FileManager.default.fileExists(atPath: destination.path) {
              _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
              try FileManager.default.moveItem(at: temporary, to: destination)
            }
          }
          try? FileManager.default.removeItem(at: temporary)
          continuation.resume(with: result)
        }
        thread.stackSize = 8 << 20
        thread.name = "motionswift.showcase.export"
        thread.qualityOfService = .userInitiated
        thread.start()
      }
      output = destination
      status = "Composition exported"
    } catch is CancellationError {
      status = "Render cancelled"
    } catch {
      self.error = String(describing: error)
      status = "Render failed"
    }
    sampleMemory()
    isRunning = false
    Self.log("Export end status=\(status) completed=\(completedFrames)/\(totalFrames) peak=\(AppMemory.formatted(peakBytes))",
             baseline: baseline, started: started)
  }

  nonisolated private static func encode(
    bundle: String, composition: Composition, output: URL, workers: Int,
    cancellation: RenderCancellation, progress: @escaping @Sendable (Int) -> Void
  ) throws {
    let started = Date()
    let baseline = AppMemory.residentBytes()
    defer { log("Encoder scope exiting", baseline: baseline, started: started) }
    try cancellation.check()
    let stream = try SharedVideoStream(
      output: output, width: composition.width, height: composition.height, fps: composition.fps)
    let audioDirectory = output.deletingLastPathComponent().appendingPathComponent("audio-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: audioDirectory) }
    let audio = AudioMix(directory: audioDirectory, fps: composition.fps)
    log("Encoder created", baseline: baseline, started: started)
    do {
      try FramePipeline.run(
        bundle: bundle, composition: composition, frames: Array(0..<composition.durationInFrames), props: "{}",
        options: PipelineOptions(workers: workers, backend: .gpu, scale: 1, sharedVideoFrames: true)
      ) { frame in
        try cancellation.check()
        guard let video = frame.videoFrame else { throw MotionError("Missing IOSurface video frame") }
        try stream.write(video.pixelBuffer)
        try audio.append(frame.media)
        if (frame.index + 1).isMultiple(of: 100) || frame.index == composition.durationInFrames - 1 {
          log("Encoded frames=\(frame.index + 1)/\(composition.durationInFrames)", baseline: baseline, started: started)
        }
        if frame.index.isMultiple(of: 10) || frame.index == composition.durationInFrames - 1 {
          progress(frame.index + 1)
        }
      }
      log("Pipeline returned; workers joined", baseline: baseline, started: started)
      try cancellation.check()
      try stream.finish()
      try audio.mux(video: output)
      log("Encoder finished", baseline: baseline, started: started)
    } catch {
      stream.cancel()
      log("Encoder cancelled or failed: \(error)", baseline: baseline, started: started)
      throw error
    }
  }
}
