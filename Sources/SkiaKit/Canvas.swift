import CSkia
import Foundation
import MotionCore

public final class Canvas {
  private let surface: UnsafeMutableRawPointer

  public init(width: Int, height: Int) throws {
    guard let handle = msk_create(Int32(clamping: width), Int32(clamping: height)) else {
      throw MotionError("Cannot allocate Skia raster surface")
    }
    surface = handle
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

  public func writePNG(to url: URL) throws {
    guard msk_png(surface, url.path) else { throw MotionError("Cannot write PNG: \(url.path)") }
  }
}
