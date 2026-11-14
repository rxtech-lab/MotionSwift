import Foundation
import MotionCore
import SkiaKit

/// Parsed paint contract, independent of layout and paragraph ownership.
struct PaintEffects {
  let width: Double
  let height: Double
  let radius: Double
  let cornerClip: String?
  let opacity: Double
  let blend: Int
  let filters: [[Double]]
  let gradient: Effects.Gradient?
  let mask: Effects.Gradient?
  let shadows: [Effects.Shadow]
  let clip: String?
  let backdropBlur: Double
  let background: UInt32

  init(_ style: Style, width: Double, height: Double) throws {
    self.width = width
    self.height = height
    let rawOpacity = try style.length("opacity", relativeTo: 1, fallback: 1)
    guard rawOpacity.isFinite else { throw MotionError("Opacity must be finite") }
    opacity = min(max(rawOpacity, 0), 1)
    filters = try Effects.filters(style.string("filter"))
    guard let blend = Effects.blendModes.firstIndex(of: style.string("mixBlendMode", "normal")) else {
      throw MotionError("ms/unsupported-css-value: mixBlendMode")
    }
    self.blend = blend
    let corners = try style.cornerRadii(width: width, height: height)
    radius = corners.uniform
    cornerClip = corners.clipPath
    let backgroundText = style.string("background", "transparent")
    let gradientText = style.string("backgroundImage", backgroundText.contains("gradient(") ? backgroundText : "none")
    gradient = gradientText == "none" ? nil : try Effects.gradient(gradientText, width: width, height: height)
    let maskText = style.string("maskImage", "none")
    mask = maskText == "none" ? nil : try Effects.gradient(maskText, width: width, height: height)
    shadows = try Effects.shadows(style.string("boxShadow"))
    clip = try Effects.clip(style.string("clipPath"), width: width, height: height)
    let backdropRaw = style.string("backdropFilter", style.string("WebkitBackdropFilter"))
    let backdrop = try Effects.functions(backdropRaw)
    guard backdrop.isEmpty || (backdrop.count == 1 && backdrop[0].0 == "blur") else {
      throw MotionError("ms/unsupported-css-value: backdropFilter supports blur(px)")
    }
    backdropBlur = backdrop.isEmpty ? 0 : try Effects.number(backdrop[0].1, unit: "px")
    guard backdropBlur >= 0 else { throw MotionError("Backdrop blur must be nonnegative") }
    guard backdropBlur == 0 || (filters.isEmpty && mask == nil && blend == 0) else {
      throw MotionError("ms/unsupported-css-value: backdropFilter cannot combine with filter/mask/blend")
    }
    background = try CSSColor.parse(
      style.string("backgroundColor", gradient == nil ? backgroundText : "transparent"), current: style.string("color", "black"))
  }

  func drawBackground(on canvas: Canvas, fill: Bool = true) throws {
    for shadow in shadows.reversed() where !shadow.inset { draw(shadow, on: canvas) }
    if let cornerClip {
      try canvas.clip(path: cornerClip)
      canvas.save(opacity: 1)
      defer { canvas.restore() }
      if fill { canvas.rectangle(width: width, height: height, radius: 0, color: background) }
      if let gradient { try gradient.draw(on: canvas, width: width, height: height, radius: 0) }
      for shadow in shadows.reversed() where shadow.inset { draw(shadow, on: canvas) }
      return
    }
    if fill { canvas.rectangle(width: width, height: height, radius: radius, color: background) }
    if let gradient { try gradient.draw(on: canvas, width: width, height: height, radius: radius) }
    for shadow in shadows.reversed() where shadow.inset { draw(shadow, on: canvas) }
  }

  private func draw(_ shadow: Effects.Shadow, on canvas: Canvas) {
    canvas.shadow(width: width, height: height, radius: radius, x: shadow.x, y: shadow.y,
                  blur: shadow.blur, spread: shadow.spread, color: shadow.color, inset: shadow.inset)
  }
}

/// Balances the group stack on success and on any descendant render error.
final class EffectGroup {
  private let effects: PaintEffects
  private let canvas: Canvas
  private var layers = 0

  init(_ effects: PaintEffects, on canvas: Canvas) throws {
    self.effects = effects
    self.canvas = canvas
    if let clip = effects.clip { try canvas.clip(path: clip) }
    if effects.backdropBlur > 0 {
      canvas.backdrop(width: effects.width, height: effects.height, radius: effects.radius, blur: effects.backdropBlur)
    }
    if effects.filters.isEmpty && effects.blend == 0 && effects.mask == nil {
      canvas.save(opacity: effects.opacity)
    } else {
      canvas.effects(opacity: effects.opacity, blend: effects.blend, filters: effects.mask == nil ? effects.filters : [],
                     width: effects.width, height: effects.height)
    }
    layers = 1
    if effects.mask != nil { canvas.clip(width: effects.width, height: effects.height) }
    if effects.mask != nil && !effects.filters.isEmpty {
      canvas.effects(opacity: 1, blend: 0, filters: effects.filters, width: effects.width, height: effects.height)
      layers += 1
    }
  }

  func finish() throws {
    if layers == 2 { canvas.restore(); layers -= 1 }
    if let mask = effects.mask { try mask.draw(on: canvas, width: effects.width, height: effects.height, mask: true) }
  }

  func restore() {
    while layers > 0 { canvas.restore(); layers -= 1 }
  }
}
