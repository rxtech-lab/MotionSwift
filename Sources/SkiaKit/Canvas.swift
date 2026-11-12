import CSkia
import CoreVideo
import Foundation
import Metal
import MotionCore

/// Where Skia rasterises. Both backends use the same drawing calls and produce
/// unpremultiplied RGBA8888 output.
public enum Backend: String, Sendable, CaseIterable {
  /// Skia's CPU raster backend.
  case cpu
  /// Skia Ganesh on Metal. Each canvas owns its own GPU context and command queue.
  case gpu

  public var label: String { self == .cpu ? "skia-cpu" : "skia-metal" }
}

/// A Skia drawing surface. A canvas is not thread-safe: confine it to one render worker.
public final class Canvas {
  private let surface: UnsafeMutableRawPointer
  public let width: Int
  public let height: Int
  public let backend: Backend
  // Kept alive for the surface's lifetime; Skia also retains them.
  private let device: (any MTLDevice)?
  private let queue: (any MTLCommandQueue)?
  private var videoPool: MetalVideoPool?

  public init(width: Int, height: Int, backend: Backend = .cpu) throws {
    self.width = width
    self.height = height
    self.backend = backend
    let pixelsWide = Int32(clamping: width)
    let pixelsHigh = Int32(clamping: height)
    switch backend {
    case .cpu:
      device = nil
      queue = nil
      guard let handle = msk_create(pixelsWide, pixelsHigh) else {
        throw MotionError("Cannot allocate Skia raster surface")
      }
      surface = handle
    case .gpu:
      guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
        throw MotionError("No Metal device available for --backend=gpu")
      }
      self.device = device
      self.queue = queue
      let handle = msk_create_gpu(
        pixelsWide, pixelsHigh, Unmanaged.passUnretained(device as AnyObject).toOpaque(),
        Unmanaged.passUnretained(queue as AnyObject).toOpaque())
      guard let handle else { throw MotionError("Cannot allocate Skia Metal surface") }
      surface = handle
    }
  }

  deinit { msk_destroy(surface) }

  public func clear() { msk_clear(surface) }

  public func save(opacity: Double = 1) { msk_save(surface, Float(opacity)) }
  public func restore() { msk_restore(surface) }
  public func translate(_ x: Double, _ y: Double) { msk_translate(surface, Float(x), Float(y)) }
  public func rotate(_ degrees: Double) { msk_rotate(surface, Float(degrees)) }
  public func scale(_ x: Double, _ y: Double) { msk_scale(surface, Float(x), Float(y)) }
  public func clip(width: Double, height: Double) { msk_clip(surface, Float(width), Float(height)) }

  public func rectangle(
    x: Double = 0, y: Double = 0, width: Double, height: Double, radius: Double, color: UInt32
  ) {
    msk_rect(surface, Float(x), Float(y), Float(width), Float(height), Float(radius), color)
  }

  public func text(
    _ text: String, family: String, size: Double, color: UInt32, x: Double = 0, baseline: Double
  ) throws {
    guard msk_text(surface, text, family, Float(size), color, Float(x), Float(baseline)) else {
      throw MotionError("Skia could not resolve font: \(family)")
    }
  }

  /// Unpremultiplied RGBA8888 pixels, rows tightly packed. GPU work is flushed first.
  public func rgba() throws -> Data {
    var data = Data(count: width * height * 4)
    let count = data.count
    let ok = data.withUnsafeMutableBytes { buffer in
      msk_read_rgba(surface, buffer.bindMemory(to: UInt8.self).baseAddress, count)
    }
    guard ok else { throw MotionError("Cannot read back \(backend.rawValue) surface pixels") }
    return data
  }

  /// GPU-only F16 -> BGRA8 resolve into an IOSurface shared with VideoToolbox.
  /// Synchronizes GPU completion without reading or mapping pixel bytes on the CPU.
  public func videoFrame() throws -> MetalVideoFrame {
    guard let device else { throw MotionError("IOSurface video output requires the GPU backend") }
    if videoPool == nil { videoPool = try MetalVideoPool(device: device, width: width, height: height) }
    guard let frame = try videoPool?.allocate(), let wrapper = frame.texture,
      let texture = CVMetalTextureGetTexture(wrapper)
    else { throw MotionError("Cannot allocate shared Metal video frame") }
    guard msk_copy_to_metal_texture(surface, Unmanaged.passUnretained(texture as AnyObject).toOpaque())
    else { throw MotionError("Cannot resolve Metal frame into IOSurface") }
    return frame
  }

  public func writePNG(to url: URL) throws {
    guard msk_png(surface, url.path) else { throw MotionError("Cannot write PNG: \(url.path)") }
  }
}
