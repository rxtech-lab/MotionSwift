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
}

#if os(macOS)
import Darwin

/// Streams unpremultiplied RGBA8888 frames into ffmpeg through a pipe, so rendered
/// frames never round-trip through PNG files. Write frames in presentation order.
/// Hardware encoding still reads CPU pixels; this is not a zero-copy Metal encoder.
public final class VideoStream {
  private let process = Process()
  private let input = Pipe()
  private let frameBytes: Int
  private let output: URL
  public private(set) var framesWritten = 0

  public init(
    output: URL, width: Int, height: Int, fps: Double, encoder: VideoEncoder = .software, options: EncodingOptions? = nil
  ) throws {
    let settings = try options ?? EncodingOptions(encoder: encoder)
    guard settings.encoder != .sharedSurface else { throw MotionError("Use SharedVideoStream for IOSurface encoding") }
    try settings.validate(width: width, height: height, fps: fps, output: output)
    self.output = output
    frameBytes = width * height * 4
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
      "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(width)x\(height)", "-framerate", String(fps),
      "-i", "pipe:0",
    ] + settings.arguments + [
      "-pix_fmt", settings.pixelFormat.rawValue, output.path,
    ]
    process.standardInput = input
    // Keep a failed child local to this stream, without changing the host app's
    // process-wide SIGPIPE handler. FileHandle can then throw EPIPE on writes.
    guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
      throw MotionError("Cannot configure ffmpeg input pipe: \(String(cString: strerror(errno)))")
    }
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
    try? FileManager.default.removeItem(at: output)
  }
}
#endif

#if os(macOS)
extension VideoStream {
  /// A real one-frame encode detects missing ffmpeg codecs and inaccessible hardware
  /// before the renderer starts. The requested encoder is never substituted.
  public static func checkAvailability(options: EncodingOptions, width: Int, height: Int, fps: Double) throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + options.fileExtension)
    defer { try? FileManager.default.removeItem(at: output) }
    do {
      let stream = try VideoStream(output: output, width: width, height: height, fps: fps, options: options)
      do {
        try stream.write(Data(repeating: 0, count: width * height * 4))
        try stream.finish()
      } catch { stream.cancel(); throw error }
    } catch {
      throw MotionError("Requested \(options.codec.rawValue)/\(options.encoder.rawValue) unavailable at \(width)x\(height): "
        + "\(error). No software fallback was attempted.")
    }
  }
}
#endif
