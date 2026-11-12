import Foundation
import MotionCore

/// Output encoder, independent of the Skia rendering backend.
public enum VideoEncoder: String, Sendable {
  case software
  case videotoolbox
  case sharedSurface = "videotoolbox-shared"

  public var label: String {
    if self == .sharedSurface { return "videotoolbox-iosurface" }
    return "ffmpeg-\(self == .software ? "libx264" : "h264_videotoolbox")-rawvideo-pipe"
  }

  var arguments: [String] {
    switch self {
    case .software: return ["-c:v", "libx264", "-crf", "18", "-preset", "medium"]
    // Require the hardware encoder. Never silently benchmark a software fallback.
    // VideoToolbox quality is 0...100; it is not equivalent to x264 CRF.
    case .videotoolbox:
      return ["-c:v", "h264_videotoolbox", "-allow_sw", "0", "-q:v", "65", "-realtime", "0"]
    case .sharedSurface: return [] // SharedVideoStream owns native encoding, not ffmpeg.
    }
  }
}

/// Streams unpremultiplied RGBA8888 frames into ffmpeg through a pipe, so rendered
/// frames never round-trip through PNG files. Write frames in presentation order.
/// Hardware encoding still reads CPU pixels; this is not a zero-copy Metal encoder.
public final class VideoStream {
  private let process = Process()
  private let input = Pipe()
  private let frameBytes: Int
  public private(set) var framesWritten = 0

  public init(
    output: URL, width: Int, height: Int, fps: Double, encoder: VideoEncoder = .software
  ) throws {
    guard encoder != .sharedSurface else { throw MotionError("Use SharedVideoStream for IOSurface encoding") }
    guard width > 0, height > 0, width <= 16384, height <= 16384,
      width.isMultiple(of: 2), height.isMultiple(of: 2), fps.isFinite, fps > 0
    else { throw MotionError("H.264 requires positive even dimensions up to 16384 and a positive finite fps") }
    frameBytes = width * height * 4
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
      "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(width)x\(height)", "-framerate", String(fps),
      "-i", "pipe:0",
    ] + encoder.arguments + [
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
