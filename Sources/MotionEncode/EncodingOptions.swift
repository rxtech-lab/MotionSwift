import Foundation
import MotionCore

public enum VideoCodec: String, Sendable, CaseIterable {
  case h264, hevc, prores, prores4444
}

public enum VideoPixelFormat: String, Sendable {
  case yuv420p, yuv422p10le, yuva444p10le
}

/// Quality uses the encoder's native units: x264/x265 CRF 0...51,
/// VideoToolbox 0...100, ProRes quantizer 1...31 (lower is better except VideoToolbox).
public struct EncodingOptions: Sendable {
  public let codec: VideoCodec
  public let encoder: VideoEncoder
  public let pixelFormat: VideoPixelFormat
  public let quality: Double
  public var preservesAlpha: Bool { pixelFormat == .yuva444p10le }
  public var fileExtension: String { codec == .prores || codec == .prores4444 ? "mov" : "mp4" }

  public init(codec: VideoCodec = .h264, encoder: VideoEncoder = .software,
              pixelFormat: VideoPixelFormat? = nil, quality: Double? = nil) throws {
    self.codec = codec
    self.encoder = encoder
    self.pixelFormat = pixelFormat ?? (codec == .prores4444 ? .yuva444p10le : codec == .prores ? .yuv422p10le : .yuv420p)
    self.quality = quality ?? (encoder == .software ? (codec == .prores || codec == .prores4444 ? 9 : 18) : 65)
    let expected: VideoPixelFormat = codec == .prores4444 ? .yuva444p10le : codec == .prores ? .yuv422p10le : .yuv420p
    guard self.pixelFormat == expected else {
      throw MotionError("\(codec.rawValue) requires --pixel-format=\(expected.rawValue); alpha requires prores4444/yuva444p10le")
    }
    // ProRes is explicitly software-only until a hardware path can enforce and verify availability.
    guard encoder == .software || (codec == .h264 || codec == .hevc) else {
      throw MotionError("\(codec.rawValue) is available only with --encoder=software; no hardware fallback is allowed")
    }
    let range: ClosedRange<Double> = encoder != .software ? 0...100 :
      (codec == .prores || codec == .prores4444 ? 1...31 : 0...51)
    guard self.quality.isFinite, range.contains(self.quality) else {
      throw MotionError("Quality for \(codec.rawValue)/\(encoder.rawValue) must be in \(range)")
    }
  }

  public func validate(width: Int, height: Int, fps: Double, output: URL) throws {
    guard width > 0, height > 0, width <= 16384, height <= 16384,
          width.isMultiple(of: 2), height.isMultiple(of: 2), fps.isFinite, fps > 0 else {
      throw MotionError("Video requires positive even dimensions up to 16384 and positive finite fps")
    }
    guard output.pathExtension.lowercased() == fileExtension ||
            (fileExtension == "mp4" && output.pathExtension.lowercased() == "mov") else {
      throw MotionError("\(codec.rawValue) requires .\(fileExtension) output")
    }
  }

  public var label: String {
    if encoder == .sharedSurface { return "videotoolbox-iosurface-" + codec.rawValue }
    return "ffmpeg-" + (encoder == .software ?
      (codec == .h264 ? "libx264" : codec == .hevc ? "libx265" : "prores_ks") : codec.rawValue + "_videotoolbox")
  }

  var arguments: [String] {
    let qualityValue = String(quality)
    if encoder != .software {
      return ["-c:v", codec == .hevc ? "hevc_videotoolbox" : "h264_videotoolbox",
              "-allow_sw", "0", "-q:v", qualityValue, "-realtime", "0", "-bf", "0"] +
        (codec == .hevc ? ["-tag:v", "hvc1"] : [])
    }
    switch codec {
    case .h264: return ["-c:v", "libx264", "-crf", qualityValue, "-preset", "medium", "-bf", "0"]
    case .hevc: return ["-c:v", "libx265", "-crf", qualityValue, "-preset", "medium", "-x265-params", "bframes=0:pools=2", "-tag:v", "hvc1"]
    case .prores, .prores4444:
      return ["-c:v", "prores_ks", "-profile:v", codec == .prores4444 ? "4" : "3",
              "-qscale:v", qualityValue, "-alpha_bits", preservesAlpha ? "16" : "0"]
    }
  }
}

/// Inclusive source ranges, emitted in the caller's order. Frame stepping samples
/// each range independently and output runs at source fps / step (preserving time).
public enum FrameSelection {
  public static func segments(_ specification: String?, duration: Int, step: Int = 1) throws -> [[Int]] {
    guard duration > 0, step > 0 else { throw MotionError("Frame duration and step must be positive") }
    let ranges = specification?.split(separator: ",", omittingEmptySubsequences: false).map(String.init) ?? ["0-\(duration - 1)"]
    return try ranges.map { range in
      let parts = range.split(separator: "-", omittingEmptySubsequences: false)
      guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]),
            start >= 0, end >= start, end < duration else {
        throw MotionError("Invalid frame segment '\(range)'; expected inclusive a-b within composition")
      }
      return Array(stride(from: start, through: end, by: step))
    }
  }
}
