import Foundation
import MotionCore

/// Phase 0 image-sequence encoder. The frame directory is private to each render job.
public enum VideoEncoder {
  public static func encode(directory: URL, output: URL, composition: Composition, frameCount: Int)
    throws {
    guard frameCount > 0 else { throw MotionError("Cannot encode an empty frame range") }
    try Subprocess.run(
      "ffmpeg",
      [
        "-hide_banner", "-loglevel", "error", "-y", "-framerate", String(composition.fps),
        "-start_number", "0", "-i", directory.appendingPathComponent("%06d.png").path,
        "-frames:v", String(frameCount), "-c:v", "libx264", "-crf", "18", "-preset", "medium",
        "-pix_fmt", "yuv420p", output.path,
      ])
  }
}
