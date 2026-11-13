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

  /// Select the effects renderer before starting a frame, preserving the legacy image path otherwise.
  public func prepareEffects(_ enabled: Bool) throws {
    guard msk_effects_precision(surface, enabled) else { throw MotionError("Cannot prepare effects surface") }
  }

  public func clear() { msk_clear(surface) }

  public func save(opacity: Double = 1) { msk_save(surface, Float(opacity)) }
  public func saveState() { msk_save_state(surface) }
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

  /// Starts an isolated CSS group; restore composites the entire subtree once.
  public func effects(opacity: Double, blend: Int, filters: [[Double]], width: Double? = nil, height: Double? = nil) {
    let entries = filters.flatMap { $0.map(Float.init) }
    msk_effect_layer(surface, Float(opacity), Int32(blend), entries, filters.count,
                     Float(width ?? Double(self.width)), Float(height ?? Double(self.height)))
  }

  public func backdrop(width: Double, height: Double, radius: Double, blur: Double) {
    msk_backdrop(surface, Float(width), Float(height), Float(radius), Float(blur))
  }

  public func concatenate(_ matrix: [Double]) {
    precondition(matrix.count == 9)
    msk_concat(surface, matrix.map(Float.init))
  }

  public func clip(path: String) throws {
    guard msk_clip_path(surface, path) else { throw MotionError("Unsupported clip-path geometry") }
  }

  public func gradient(width: Double, height: Double, radius: Double, radial: Bool,
                       geometry: [Double], colors: [UInt32], stops: [Double], mask: Bool = false) throws {
    precondition(geometry.count == 4 && colors.count == stops.count)
    guard msk_gradient(surface, Float(width), Float(height), Float(radius), radial ? 1 : 0,
                       geometry.map(Float.init), colors, stops.map(Float.init), colors.count, mask ? 1 : 0)
    else { throw MotionError("Cannot draw gradient") }
  }

  // Mirrors the native shadow ABI, including geometry and paint options.
  // swiftlint:disable:next function_parameter_count
  public func shadow(width: Double, height: Double, radius: Double, x: Double, y: Double,
                     blur: Double, spread: Double, color: UInt32, inset: Bool) {
    msk_shadow(surface, Float(width), Float(height), Float(radius), Float(x), Float(y),
               Float(blur / 2), Float(spread), color, inset)
  }

  public func text(
    _ text: String, family: String, size: Double, color: UInt32, x: Double = 0, baseline: Double
  ) throws {
    guard msk_text(surface, text, family, Float(size), color, Float(x), Float(baseline)) else {
      throw MotionError("Skia could not resolve font: \(family)")
    }
  }

  public func paragraph(_ paragraph: Paragraph, x: Double = 0, y: Double = 0) {
    msk_paragraph_paint(surface, paragraph.handle, Float(x), Float(y))
  }

  /// Renders SVG bytes through Skia's SVG DOM with the system font manager.
  public func svg(_ data: Data, width: Double, height: Double) throws {
    let data = try SVGImage.prepare(data)
    let ok = data.withUnsafeBytes { bytes in
      msk_svg(surface, bytes.bindMemory(to: UInt8.self).baseAddress, data.count,
        Float(width), Float(height))
    }
    guard ok else { throw MotionError("Cannot decode SVG image") }
  }

  /// Draws premultiplied sRGB pixels through the same CPU/Metal painter as shapes.
  public func image(_ pixels: Data, pixelWidth: Int, pixelHeight: Int,
                    width: Double, height: Double, fit: String) throws {
    let ok = pixels.withUnsafeBytes { bytes in
      msk_image_rgba(surface, bytes.bindMemory(to: UInt8.self).baseAddress, pixels.count,
                    Int32(pixelWidth), Int32(pixelHeight), Float(width), Float(height),
                    fit == "cover" ? 1 : fit == "fill" ? 2 : 0)
    }
    guard ok else { throw MotionError("Cannot draw raster media") }
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
