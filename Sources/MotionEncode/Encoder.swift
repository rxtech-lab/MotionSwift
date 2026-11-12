import Foundation
import MotionCore

/// Streams unpremultiplied RGBA8888 frames into ffmpeg/x264 through a pipe, so rendered
/// frames never round-trip through PNG files. Write frames in presentation order.
/// Output settings: H.264, CRF 18, preset medium, yuv420p (same as the Remotion reference).
public final class VideoStream {
  private let process = Process()
  private let input = Pipe()
  private let frameBytes: Int
  public private(set) var framesWritten = 0

  public init(output: URL, width: Int, height: Int, fps: Double) throws {
    frameBytes = width * height * 4
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
      "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(width)x\(height)", "-framerate", String(fps),
      "-i", "pipe:0", "-c:v", "libx264", "-crf", "18", "-preset", "medium",
      "-pix_fmt", "yuv420p", output.path,
    ]
    process.standardInput = input
    // Inherit stderr so encoder errors stay visible and cannot fill a pipe.
    try process.run()
  }

  public func write(_ frame: Data) throws {
    guard frame.count == frameBytes else {
      throw MotionError("Frame is \(frame.count) bytes; expected \(frameBytes)")
    }
    do {
      try input.fileHandleForWriting.write(contentsOf: frame)
    } catch {
      throw MotionError("ffmpeg stopped accepting frames: \(error)")
    }
    framesWritten += 1
  }

  /// Closes the pipe and waits for ffmpeg to finish the file.
  public func finish() throws {
    try? input.fileHandleForWriting.close()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw MotionError("ffmpeg exited with status \(process.terminationStatus)")
    }
    guard framesWritten > 0 else { throw MotionError("Cannot encode an empty frame range") }
  }

  /// Stops ffmpeg without producing a valid file (used when rendering fails).
  public func cancel() {
    try? input.fileHandleForWriting.close()
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
  }
}
