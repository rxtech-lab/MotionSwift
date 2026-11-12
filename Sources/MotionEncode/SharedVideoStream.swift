import AVFoundation
import CoreVideo
import Foundation
import MotionCore
import VideoToolbox

/// Native hardware H.264 writer. Accepts GPU-completed IOSurface pixel buffers directly;
/// AVFoundation feeds them to VideoToolbox without an application CPU readback or pipe.
/// Call only on the ordered pipeline consumer thread. Readiness bounds encoder backlog.
/// Submitted pixel buffers must stay immutable; the encoder retains them while in use.
public final class SharedVideoStream {
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor
  private let frameDuration: CMTime
  private let width: Int
  private let height: Int
  public private(set) var framesWritten = 0

  public init(output: URL, width: Int, height: Int, fps: Double) throws {
    guard width > 0, height > 0, width <= 16384, height <= 16384,
      width.isMultiple(of: 2), height.isMultiple(of: 2), fps.isFinite, fps > 0
    else { throw MotionError("H.264 requires positive even dimensions up to 16384 and a positive finite fps") }
    self.width = width
    self.height = height
    frameDuration = CMTime(seconds: 1 / fps, preferredTimescale: 600_000)
    if FileManager.default.fileExists(atPath: output.path) {
      let type = try FileManager.default.attributesOfItem(atPath: output.path)[.type] as? FileAttributeType
      guard type == .typeRegular else { throw MotionError("Video output already exists and is not a regular file") }
      try FileManager.default.removeItem(at: output)
    }
    writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    var settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width, AVVideoHeightKey: height,
      // Match ffmpeg's existing untagged RGBA -> yuv420p conversion. Explicit
      // matrix metadata also prevents decoders assuming a different SD/HD matrix.
      AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_601_4,
      ],
      AVVideoCompressionPropertiesKey: [
        kVTCompressionPropertyKey_Quality as String: 0.65,
        AVVideoExpectedSourceFrameRateKey: fps,
      ],
    ]
    #if os(macOS)
    settings[AVVideoEncoderSpecificationKey] = [
      kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
    ]
    #endif
    // iOS and iPadOS AVAssetWriter H.264 always uses the hardware encoder; there is no switch.
    guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
      throw MotionError("Native hardware H.264 settings are unavailable")
    }
    input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ])
    guard writer.canAdd(input) else { throw MotionError("Cannot add native hardware video input") }
    writer.add(input)
    guard writer.startWriting() else { throw MotionError("Cannot start native video writer: \(String(describing: writer.error))") }
    writer.startSession(atSourceTime: .zero)
  }

  public func write(_ buffer: CVPixelBuffer) throws {
    guard CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height,
      CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
      CVPixelBufferGetIOSurface(buffer) != nil
    else { throw MotionError("Native video requires a matching IOSurface-backed BGRA pixel buffer") }
    let deadline = Date().addingTimeInterval(30)
    while !input.isReadyForMoreMediaData {
      guard writer.status == .writing, Date() < deadline else {
        throw MotionError("Native hardware encoder stopped or timed out: \(String(describing: writer.error))")
      }
      Thread.sleep(forTimeInterval: 0.001)
    }
    let time = CMTimeMultiply(frameDuration, multiplier: Int32(framesWritten))
    guard adaptor.append(buffer, withPresentationTime: time) else {
      throw MotionError("Native hardware encoder rejected frame: \(String(describing: writer.error))")
    }
    framesWritten += 1
  }

  public func finish() throws {
    guard framesWritten > 0 else { throw MotionError("Cannot encode an empty frame range") }
    writer.endSession(atSourceTime: CMTimeMultiply(frameDuration, multiplier: Int32(framesWritten)))
    input.markAsFinished()
    let completed = DispatchSemaphore(value: 0)
    writer.finishWriting { completed.signal() }
    guard completed.wait(timeout: .now() + 30) == .success else {
      writer.cancelWriting()
      throw MotionError("Timed out finishing native hardware video")
    }
    guard writer.status == .completed else {
      throw MotionError("Native hardware encoding failed: \(String(describing: writer.error))")
    }
  }

  public func cancel() { writer.cancelWriting() }
}
