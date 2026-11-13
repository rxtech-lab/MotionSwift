import Foundation
import MotionCore
import MotionLayout
import SkiaKit

public struct LayoutBox: Codable, Sendable, Equatable {
  /// Tree path of the node, for example `0.1.2`.
  public let id: String
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double
  /// Editor source stamp of the node, when the bundle was compiled with stamps.
  public var source: String?

  public init(id: String, x: Double, y: Double, width: Double, height: Double, source: String? = nil) {
    self.id = id
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.source = source
  }
}

/// Strict Phase 0 box painter. Unsupported styles fail instead of silently drawing incorrect output.
/// A renderer owns one Skia surface and is not thread-safe; parallel renders use one per worker.
public final class Renderer {
  private let mediaDecoder = MediaDecoder()
  private let canvas: Canvas
  private let size: (Int, Int)
  private let pixelScale: Double
  private var boxes: [LayoutBox] = []

  /// `width`/`height` are composition (CSS) pixels; the surface is `scale` times larger,
  /// matching Remotion's `scale` render option. Layout boxes stay in CSS pixels.
  public init(width: Int, height: Int, scale: Double = 1, backend: Backend = .cpu) throws {
    let pixels = try Self.pixelSize(width: width, height: height, scale: scale)
    canvas = try Canvas(width: pixels.width, height: pixels.height, backend: backend)
    size = (width, height)
    pixelScale = scale
  }

  /// Output pixel dimensions for a composition size at `scale`.
  public static func pixelSize(width: Int, height: Int, scale: Double) throws
    -> (width: Int, height: Int) {
    let scaled = ((Double(width) * scale).rounded(), (Double(height) * scale).rounded())
    guard scale.isFinite, scale > 0, scaled.0 >= 1, scaled.1 >= 1, scaled.0 <= 16384,
      scaled.1 <= 16384
    else { throw MotionError("Invalid render scale: \(scale)") }
    return (Int(scaled.0), Int(scaled.1))
  }

  public var backend: Backend { canvas.backend }
  public var pixelWidth: Int { canvas.width }
  public var pixelHeight: Int { canvas.height }

  /// Paints one frame into the surface and returns its layout boxes.
  @discardableResult
  public func draw(_ node: RenderNode, composition: Composition) throws -> [LayoutBox] {
    guard composition.width == size.0, composition.height == size.1 else {
      throw MotionError("Composition and surface dimensions differ")
    }
    canvas.clear()
    boxes = []
    let layout = try LayoutEngine.calculate(
      node, width: Double(composition.width), height: Double(composition.height))
    canvas.save()
    defer { canvas.restore() }
    if pixelScale != 1 { canvas.scale(pixelScale, pixelScale) }
    try paint(layout, id: "0", origin: (0, 0))
    return boxes
  }

  public func render(_ node: RenderNode, composition: Composition, to url: URL) throws
    -> [LayoutBox] {
    let result = try draw(node, composition: composition)
    try canvas.writePNG(to: url)
    return result
  }

  /// Unpremultiplied RGBA8888 pixels of the last drawn frame.
  public func pixels() throws -> Data { try canvas.rgba() }
  public func videoFrame() throws -> MetalVideoFrame { try canvas.videoFrame() }

  private func transform(_ style: Style, width: Double, height: Double) throws {
    let value = style.string("transform")
    if value.isEmpty || value == "none" { return }
    let expression = try NSRegularExpression(pattern: #"([A-Za-z]+)\(([^)]+)\)"#)
    let matches = expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
    var consumed = ""
    canvas.translate(width / 2, height / 2)
    for match in matches {
      guard let nameRange = Range(match.range(at: 1), in: value),
        let argRange = Range(match.range(at: 2), in: value),
        let fullRange = Range(match.range, in: value)
      else { continue }
      consumed += value[fullRange]
      let name = String(value[nameRange])
      let args = value[argRange].split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
      let unit = name == "rotate" ? "deg" : "px"
      let numbers = args.compactMap {
        Double($0.hasSuffix(unit) ? String($0.dropLast(unit.count)) : $0)
      }
      guard numbers.count == args.count, !numbers.isEmpty else {
        throw MotionError("Unsupported transform: \(value)")
      }
      switch name {
      case "translateX" where numbers.count == 1: canvas.translate(numbers[0], 0)
      case "translateY" where numbers.count == 1: canvas.translate(0, numbers[0])
      case "translate" where numbers.count <= 2:
        canvas.translate(numbers[0], numbers.count == 2 ? numbers[1] : 0)
      case "rotate" where numbers.count == 1: canvas.rotate(numbers[0])
      case "scale" where numbers.count <= 2:
        canvas.scale(numbers[0], numbers.count == 2 ? numbers[1] : numbers[0])
      default: throw MotionError("Unsupported transform: \(value)")
      }
    }
    guard consumed.filter({ !$0.isWhitespace }) == value.filter({ !$0.isWhitespace }) else {
      throw MotionError("Unsupported transform: \(value)")
    }
    canvas.translate(-width / 2, -height / 2)
  }

  private func paint(_ layout: LayoutNode, id: String, origin: (Double, Double)) throws {
    let node = layout.node
    let width = layout.width
    let height = layout.height
    if node.type == "ms-audio" { return }
    if node.type == "#text" {
      throw MotionError("Paragraph text layout is not implemented in this Phase 0 painter")
    }
    guard ["div", "span", "img", "ms-video"].contains(node.type) else {
      throw MotionError("Unsupported element: \(node.type)")
    }
    let style = try Style(node.style)
    if style.string("display") == "none" { return }
    boxes.append(LayoutBox(id: id, x: origin.0, y: origin.1, width: width, height: height, source: node.source))
    let opacity = try style.length("opacity", relativeTo: 1, fallback: 1)
    guard (0...1).contains(opacity) else { throw MotionError("Opacity must be in 0...1") }
    canvas.save(opacity: opacity)
    defer { canvas.restore() }
    try transform(style, width: width, height: height)
    if style.string("overflow") == "hidden" { canvas.clip(width: width, height: height) }
    let background = style.string("backgroundColor", style.string("background", "transparent"))
    let radius = try style.length("borderRadius", relativeTo: min(width, height))
    canvas.rectangle(
      width: width, height: height, radius: radius, color: try Style.color(background))
    if node.type == "img" || node.type == "ms-video" {
      guard let src = node.src else { throw MotionError("Missing media source") }
      if src.hasPrefix("data:image/svg+xml") {
        guard style.string("objectFit") == "contain" else {
          throw MotionError("SVG images require objectFit: contain")
        }
        try canvas.svg(MediaSource.data(src), width: width, height: height)
      } else {
        if node.type == "ms-video", node.media == nil { throw MotionError("Missing video timing") }
        if let image = try mediaDecoder.image(src, time: node.media?.time) {
          try canvas.image(image.pixels, pixelWidth: image.width, pixelHeight: image.height,
                           width: width, height: height, fit: style.string("objectFit", "fill"))
        }
      }
    }
    for (index, child) in layout.children.enumerated() {
      canvas.save()
      canvas.translate(child.x, child.y)
      try paint(child, id: "\(id).\(index)", origin: (origin.0 + child.x, origin.1 + child.y))
      canvas.restore()
    }
  }
}
