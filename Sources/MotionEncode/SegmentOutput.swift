#if os(macOS)
import Foundation
import MotionCore

/// Owns scratch files beside the destination; only a complete result replaces output.
public final class SegmentOutput {
  public let directory: URL
  private let output: URL
  public init(output: URL) throws {
    self.output = output
    directory = output.deletingLastPathComponent().appendingPathComponent(".motionswift-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  }
  deinit { try? FileManager.default.removeItem(at: directory) }
  public func segment(_ index: Int) -> URL {
    directory.appendingPathComponent("segment-\(index)." + output.pathExtension)
  }
  public func publish(count: Int, beforePublish: (URL) throws -> Void = { _ in }, cancelled: () -> Bool = { false }) throws {
    guard count > 0, !cancelled() else { throw MotionError("Render cancelled or empty") }
    let result: URL
    if count == 1 { result = segment(0) } else {
      let list = directory.appendingPathComponent("concat.txt")
      // Generated relative names avoid quoting paths supplied by the caller.
      try (0..<count).map { "file '\(segment($0).lastPathComponent)'" }.joined(separator: "\n")
        .write(to: list, atomically: true, encoding: .utf8)
      result = directory.appendingPathComponent("joined." + output.pathExtension)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "1", "-i", list.path,
                           "-map", "0:v:0", "-map", "0:a?", "-c", "copy", result.path]
      try process.run()
      while process.isRunning {
        if cancelled() { process.terminate(); process.waitUntilExit(); throw MotionError("Concatenation cancelled") }
        Thread.sleep(forTimeInterval: 0.01)
      }
      guard process.terminationStatus == 0 else { throw MotionError("Segment concatenation failed") }
    }
    guard !cancelled() else { throw MotionError("Render cancelled") }
    try beforePublish(result)
    guard !cancelled() else { throw MotionError("Render cancelled") }
    // POSIX rename atomically replaces an existing regular file on the same volume.
    guard rename(result.path, output.path) == 0 else { throw MotionError("Cannot publish completed video (errno \(errno))") }
  }
}
#endif
