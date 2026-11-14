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
  public let fonts = FontCollection()
  private let mediaDecoder = MediaDecoder()
  private var scene3D: SceneRenderer3D?
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

  /// Legacy data-URI SVGs retain their original SkSVG raster contract. CSS effects,
  /// inline vector hosts, and external SVG files use the stricter paint pipeline.
  private static let effectsKeys: Set<String> = [
    "opacity", "transform", "filter", "backdropFilter", "WebkitBackdropFilter",
    "boxShadow", "backgroundImage", "clipPath", "maskImage", "mixBlendMode",
  ]

  private static func usesEffects(_ node: RenderNode) -> Bool {
    if !effectsKeys.isDisjoint(with: node.style.keys)
      || (node.style["background"]?.string?.contains("gradient(") ?? false)
      || (node.style["borderRadius"]?.string?.contains(where: \.isWhitespace) ?? false) {
      return true
    }
    if node.type == "ms-svg" { return true }
    if node.type == "img", let src = node.src, !src.hasPrefix("data:"),
       (try? MediaSource.url(src).pathExtension.lowercased()) == "svg" { return true }
    return node.children.contains { usesEffects($0) }
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
    try canvas.prepareEffects(Self.usesEffects(node))
    canvas.clear()
    boxes = []
    let layout = try LayoutEngine.calculate(
      node, width: Double(composition.width), height: Double(composition.height), fonts: fonts)
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
    let origin = try style.origin(width: width, height: height)
    canvas.translate(origin.0, origin.1)
    canvas.concatenate(try CSSTransform.matrix(style.string("transform"), width: width, height: height))
    canvas.translate(-origin.0, -origin.1)
  }

  private struct PaintClip {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
  }

  private struct PaintEntry {
    let layout: LayoutNode
    let id: String
    let x: Double
    let y: Double
    let zIndex: Double
    let onlySelf: Bool
    let clips: [PaintClip]
  }

  /// Auto-z containers contribute their descendants to the nearest stacking context.
  /// Transform/opacity/effect groups remain atomic, as do explicit z-index contexts.
  private func stackingEntries(_ root: LayoutNode, id: String) -> [PaintEntry] {
    var entries: [PaintEntry] = []
    func visit(_ parent: LayoutNode, path: String, x: Double, y: Double, clips: [PaintClip], positioned: Bool) {
      for (index, child) in parent.children.enumerated() {
        let style = child.node.style
        let context = style["zIndex"]?.number != nil || (style["opacity"]?.number ?? 1) < 1
          || ["transform", "filter", "backdropFilter", "WebkitBackdropFilter", "clipPath", "maskImage"].contains {
            let value = style[$0]?.string ?? "none"
            return !value.isEmpty && value != "none"
          } || (style["mixBlendMode"]?.string ?? "normal") != "normal"

        let childPositioned = positioned || ["relative", "absolute"].contains(style["position"]?.string ?? "")
        let paintLevel = style["zIndex"]?.number ?? (context || childPositioned ? 0 : -0.5)
        let childID = "\(path).\(index)"
        entries.append(PaintEntry(layout: child, id: childID, x: x + child.x, y: y + child.y,
                                  zIndex: paintLevel, onlySelf: !context, clips: clips))
        if !context {
          let childClips = style["overflow"]?.string == "hidden"
            ? clips + [PaintClip(x: x + child.x, y: y + child.y, width: child.width, height: child.height)] : clips
          visit(child, path: childID, x: x + child.x, y: y + child.y, clips: childClips, positioned: childPositioned)
        }
      }
    }
    visit(root, path: id, x: 0, y: 0, clips: [], positioned: false)
    return entries.enumerated().sorted {
      $0.element.zIndex == $1.element.zIndex ? $0.offset < $1.offset : $0.element.zIndex < $1.element.zIndex
    }.map(\.element)
  }

  private func paint(_ layout: LayoutNode, id: String, origin: (Double, Double), onlySelf: Bool = false) throws {
    let node = layout.node
    let width = layout.width
    let height = layout.height
    if node.type == "ms-audio" { return }
    guard ["div", "span", "img", "ms-video", "ms-three", "ms-svg", "#text", "p", "h1", "h2", "h3", "h4", "h5", "h6", "br",
           "section", "header", "footer", "main", "strong", "b", "em", "i"].contains(node.type) else {
      throw MotionError("Unsupported element: \(node.type)")
    }
    let style = try Style(node.style)
    if style.string("display") == "none" { return }
    boxes.append(LayoutBox(id: id, x: origin.0, y: origin.1, width: width, height: height, source: node.source))
    let effects = try PaintEffects(style, width: width, height: height)
    canvas.saveState()
    defer { canvas.restore() }
    try transform(style, width: width, height: height)
    let group = try EffectGroup(effects, on: canvas)
    defer { group.restore() }
    let roundedBox = effects.gradient == nil && effects.shadows.isEmpty && effects.cornerClip == nil
      ? try BorderPainter.paintsOpaqueRoundedBox(style, radius: effects.radius) : false
    try effects.drawBackground(on: canvas, fill: !roundedBox)
    try BorderPainter.draw(style, canvas: canvas, width: width, height: height, radius: effects.radius, paintBackground: roundedBox)
    try paintContent(layout, id: id, origin: origin, style: style, effects: effects, onlySelf: onlySelf)
    try group.finish()
  }

  private func paintContent(
    _ layout: LayoutNode, id: String, origin: (Double, Double),
    style: Style, effects: PaintEffects, onlySelf: Bool
  ) throws {
    var clippedCorner = false
    if style.string("overflow") == "hidden" {
      canvas.clip(width: layout.width, height: layout.height)
      if let cornerClip = effects.cornerClip {
        try canvas.clip(path: cornerClip)
        canvas.save(opacity: 1)
        clippedCorner = true
      }
    }
    defer { if clippedCorner { canvas.restore() } }
    try paintMedia(layout.node, style: style, width: layout.width, height: layout.height)
    if let paragraph = layout.paragraph {
      paragraph.layout(width: layout.textWidth)
      canvas.paragraph(paragraph, x: layout.textX, y: layout.textY)
    }
    if !onlySelf { try paintChildren(layout, id: id, origin: origin) }
  }

  private func paintChildren(_ layout: LayoutNode, id: String, origin: (Double, Double)) throws {
      let entries = stackingEntries(layout, id: id)
      for entry in entries {
        canvas.saveState()
        for clip in entry.clips {
          canvas.translate(clip.x, clip.y)
          canvas.clip(width: clip.width, height: clip.height)
          canvas.translate(-clip.x, -clip.y)
        }
        canvas.translate(entry.x, entry.y)
        try paint(entry.layout, id: entry.id, origin: (origin.0 + entry.x, origin.1 + entry.y), onlySelf: entry.onlySelf)
        canvas.restore()
      }
  }

  private func paintMedia(_ node: RenderNode, style: Style, width: Double, height: Double) throws {
    if node.type == "ms-svg" {
      guard let src = node.src else { throw MotionError("Missing inline SVG document") }
      try canvas.svg(Data(src.utf8), width: width, height: height)
    }
    if node.type == "ms-three" {
      guard let scene = node.scene else { throw MotionError("<ThreeCanvas> did not commit a scene") }
      if scene3D == nil { scene3D = try SceneRenderer3D() }
      // R3F sizes the WebGL canvas in CSS pixels times the clamped device pixel ratio (Remotion's scale).
      let image = try scene3D!.render(scene, devicePixelRatio: pixelScale)
      try canvas.image(image.pixels, pixelWidth: image.width, pixelHeight: image.height,
                       width: width, height: height, fit: "fill")
    }
    if node.type == "img" || node.type == "ms-video" {
      guard let src = node.src else { throw MotionError("Missing media source") }
      if src.hasPrefix("data:image/svg+xml") || (try? MediaSource.url(src).pathExtension.lowercased()) == "svg" {
        guard style.string("objectFit") == "contain" else {
          throw MotionError("SVG images require objectFit: contain")
        }
        let bytes: Data
        do {
          bytes = src.hasPrefix("data:") ? try MediaSource.data(src) : try Data(contentsOf: MediaSource.url(src))
        } catch let error as MotionError {
          throw error
        } catch {
          throw MotionError("Cannot load SVG image: \(error.localizedDescription)")
        }
        try canvas.svg(bytes, width: width, height: height)
      } else {
        if node.type == "ms-video", node.media == nil { throw MotionError("Missing video timing") }
        if let image = try mediaDecoder.image(src, time: node.media?.time) {
          try canvas.image(image.pixels, pixelWidth: image.width, pixelHeight: image.height,
                           width: width, height: height, fit: style.string("objectFit", "fill"))
        }
      }
    }
  }

}
