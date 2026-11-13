import CSkia
import Foundation
import MotionCore

/// Own one collection per rendering session. Register fonts before measuring any frame.
/// Failed registrations never enter the cache; changing bytes under an alias is rejected.
public final class FontCollection {
  let handle: UnsafeMutableRawPointer
  private var registered: [String: Data] = [:]

  public init() { handle = msk_fonts_create()! }
  deinit { msk_fonts_destroy(handle) }

  public func register(_ data: Data, family: String) throws {
    if let previous = registered[family] {
      guard previous == data else { throw MotionError("Font alias already registered: \(family)") }
      return
    }
    let success = data.withUnsafeBytes {
      msk_fonts_register(handle, $0.bindMemory(to: UInt8.self).baseAddress, data.count, family)
    }
    guard success else { throw MotionError("Cannot decode font: \(family)") }
    registered[family] = data
  }
}

public struct TextRun {
  public var text: String
  public var family: String
  public var size: Double
  public var weight: Int
  public var italic: Bool
  public var color: UInt32
  /// Multiplier, or zero for font metrics.
  public var lineHeight: Double
  public var letterSpacing: Double

  public init(_ text: String, family: String = "Arial", size: Double = 16, weight: Int = 400,
              italic: Bool = false, color: UInt32 = 0xFF00_0000,
              lineHeight: Double = 0, letterSpacing: Double = 0) {
    self.text = text
    self.family = family
    self.size = size
    self.weight = weight
    self.italic = italic
    self.color = color
    self.lineHeight = lineHeight
    self.letterSpacing = letterSpacing
  }
}

/// Retains precisely the shaped runs used for Yoga measurement and paint.
public final class Paragraph {
  let handle: UnsafeMutableRawPointer
  private let fonts: FontCollection
  public init(runs: [TextRun], fonts: FontCollection, alignment: String = "left") {
    self.fonts = fonts
    let alignment = ["center": 1, "right": 2, "end": 2, "justify": 3][alignment] ?? 0
    let builder = msk_paragraph_builder(fonts.handle, Int32(alignment))!
    for run in runs {
      msk_paragraph_add(builder, run.text, run.family, Float(run.size), Int32(clamping: run.weight),
                        run.italic, run.color, Float(run.lineHeight), Float(run.letterSpacing))
    }
    handle = msk_paragraph_build(builder)!
  }
  deinit { msk_paragraph_destroy(handle) }
  public func layout(width: Double) { msk_paragraph_layout(handle, Float(max(0, width))) }
  public var height: Double { Double(msk_paragraph_height(handle)) }
  public var intrinsicWidth: Double { Double(msk_paragraph_width(handle)) }
  public var baseline: Double { Double(msk_paragraph_baseline(handle)) }
}
