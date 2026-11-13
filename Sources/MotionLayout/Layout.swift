import Foundation
import MotionCore
import yoga
import SkiaKit

public struct LayoutNode {
  public let node: RenderNode
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double
  public let children: [LayoutNode]
  public var paragraph: Paragraph?
  public var textX: Double = 0
  public var textY: Double = 0
}

/// Yoga nodes and their config belong to one calculation; no C handles escape into the painter.
public enum LayoutEngine {
  public static func calculate(_ input: RenderNode, width: Double, height: Double, fonts: FontCollection = FontCollection()) throws
    -> LayoutNode {
    guard let config = YGConfigNew() else { throw MotionError("Cannot allocate Yoga config") }
    defer { YGConfigFree(config) }
    YGConfigSetUseWebDefaults(config, true)
    YGConfigSetPointScaleFactor(config, 0)
    let resolved = try inherit(input, parent: [:])
    var paragraphs: [YGNodeRef: Paragraph] = [:]
    let root = try build(resolved, config: config, fonts: fonts, paragraphs: &paragraphs)
    defer { YGNodeFreeRecursive(root) }
    YGNodeStyleSetWidth(root, Float(width))
    YGNodeStyleSetHeight(root, Float(height))
    YGNodeCalculateLayout(root, Float(width), Float(height), YGDirection.LTR)
    return snapshot(resolved, handle: root, paragraphs: paragraphs)
  }

  private static func inherit(_ node: RenderNode, parent: [String: JSONValue]) throws -> RenderNode {
    var values = try BoxStyle.normalized(node.style)
    for key in TextLayout.inherited where values[key] == nil {
      values[key] = parent[key]
    }
    if values["color"]?.string?.lowercased() == "currentcolor" {
      values["color"] = parent["color"] ?? .string("black")
    }
    if values["fontSize"] == nil { values["fontSize"] = .number(16) }
    if values["fontFamily"] == nil { values["fontFamily"] = .string("Arial") }
    let headings: [String: Double] = ["h1": 2, "h2": 1.5, "h3": 1.17, "h4": 1, "h5": 0.83, "h6": 0.67]
    if let scale = headings[node.type] {
      let size = node.style["fontSize"]?.number ?? (parent["fontSize"]?.number ?? 16) * scale
      values["fontSize"] = .number(size)
      if node.style["fontWeight"] == nil { values["fontWeight"] = .number(700) }
      let margins = ["h1": 0.67, "h2": 0.83, "h3": 1.0, "h4": 1.33, "h5": 1.67, "h6": 2.33]
      for key in ["marginTop", "marginBottom"] where values[key] == nil && values["margin"] == nil {
        values[key] = .number(size * (margins[node.type] ?? 1))
      }
    }
    if node.type == "p" {
      for key in ["marginTop", "marginBottom"] where values[key] == nil && values["margin"] == nil {
        values[key] = values["fontSize"]
      }
    }
    if ["strong", "b"].contains(node.type), node.style["fontWeight"] == nil { values["fontWeight"] = .number(700) }
    if ["em", "i"].contains(node.type), node.style["fontStyle"] == nil { values["fontStyle"] = .string("italic") }
    return RenderNode(
      type: node.type, style: values, text: node.text, src: node.src, source: node.source, media: node.media,
      scene: node.scene, children: try node.children.map { try inherit($0, parent: values) })
  }

  private static func build(_ input: RenderNode, config: YGConfigRef, fonts: FontCollection,
                            paragraphs: inout [YGNodeRef: Paragraph], flexItem: Bool = false) throws -> YGNodeRef {
    guard let node = YGNodeNewWithConfig(config) else {
      throw MotionError("Cannot allocate Yoga node")
    }
    do {
      try apply(input.style, to: node)
      if ["inline", "inline-block"].contains(input.style["display"]?.string ?? "") {
        guard flexItem, input.children.allSatisfy(TextLayout.isInline) else {
          throw MotionError("ms/unsupported-css-value: inline/inline-block supports only leaf or paragraph flex items")
        }
      }
      if input.style["display"]?.string == "inline-flex" && input.children.contains(where: { $0.type == "#text" }) {
        throw MotionError("ms/unsupported-css-value: inline text requires paragraph layout")
      }
      if input.type == "#text" || (!input.children.isEmpty && input.children.allSatisfy(TextLayout.isInline)) {
        let paragraph = Paragraph(runs: try TextLayout.runs(input), fonts: fonts,
                                  alignment: input.style["textAlign"]?.string ?? "left")
        paragraphs[node] = paragraph
        YGNodeSetContext(node, Unmanaged.passUnretained(paragraph).toOpaque())
        YGNodeSetMeasureFunc(node, { node, width, mode, _, _ in
          let paragraph = Unmanaged<Paragraph>.fromOpaque(YGNodeGetContext(node)!).takeUnretainedValue()
          paragraph.layout(width: mode == YGMeasureMode.undefined ? 1_000_000 : Double(width))
          return YGSize(width: Float(mode == YGMeasureMode.exactly ? Double(width) : min(paragraph.intrinsicWidth,
                            mode == YGMeasureMode.undefined ? 1_000_000 : Double(width))), height: Float(paragraph.height))
        })
        YGNodeSetBaselineFunc(node, { node, width, _ in
          let paragraph = Unmanaged<Paragraph>.fromOpaque(YGNodeGetContext(node)!).takeUnretainedValue()
          paragraph.layout(width: Double(width))
          return Float(paragraph.baseline)
        })
      } else {
        for (index, child) in input.children.enumerated() {
          YGNodeInsertChild(node, try build(child, config: config, fonts: fonts, paragraphs: &paragraphs,
            flexItem: ["flex", "inline-flex"].contains(input.style["display"]?.string ?? "")), index)
        }
      }
      return node
    } catch {
      YGNodeFreeRecursive(node)
      throw error
    }
  }

  private static func snapshot(_ input: RenderNode, handle: YGNodeRef,
                               paragraphs: [YGNodeRef: Paragraph]) -> LayoutNode {
    let paragraph = paragraphs[handle]
    let children = paragraph == nil ? input.children.enumerated().map { index, child in
      snapshot(child, handle: YGNodeGetChild(handle, index)!, paragraphs: paragraphs)
    } : []
    let left = Double(YGNodeLayoutGetPadding(handle, YGEdge.left))
    let right = Double(YGNodeLayoutGetPadding(handle, YGEdge.right))
    let width = Double(YGNodeLayoutGetWidth(handle))
    paragraph?.layout(width: max(0, width - left - right))
    return LayoutNode(
      node: input, x: Double(YGNodeLayoutGetLeft(handle)), y: Double(YGNodeLayoutGetTop(handle)),
      width: width, height: Double(YGNodeLayoutGetHeight(handle)),
      children: children, paragraph: paragraph, textX: left,
      textY: Double(YGNodeLayoutGetPadding(handle, YGEdge.top)))
  }

  private static func dimension(
    _ value: JSONValue, points: (Float) -> Void, percent: (Float) -> Void
  ) throws {
    if let number = value.number, number.isFinite, Float(number).isFinite {
      points(Float(number))
      return
    }
    if let string = value.string {
      if string.hasSuffix("%"), let number = Float(string.dropLast()), number.isFinite {
        percent(number)
        return
      }
      if string.hasSuffix("px"), let number = Float(string.dropLast(2)), number.isFinite {
        points(number)
        return
      }
    }
    throw MotionError("Unsupported layout length: \(value)")
  }

  private static func apply(_ style: [String: JSONValue], to node: YGNodeRef) throws {
    try applyDimensions(style, to: node)
    if style["boxSizing"]?.string == "content-box" {
      YGNodeStyleSetBoxSizing(node, YGBoxSizing.contentBox)
    }
    let edges: [(String, YGEdge)] = [
      ("Left", YGEdge.left), ("Right", YGEdge.right), ("Top", YGEdge.top),
      ("Bottom", YGEdge.bottom),
    ]
    for (suffix, edge) in edges {
      if let width = style["border" + suffix + "Width"]?.number {
        YGNodeStyleSetBorder(node, edge, Float(width))
      }
      if let value = style[suffix.lowercased()] ?? style["inset"] {
        try dimension(
          value, points: { YGNodeStyleSetPosition(node, edge, $0) },
          percent: { YGNodeStyleSetPositionPercent(node, edge, $0) })
      }
      for prefix in ["padding", "margin"] {
        if let value = style[prefix + suffix] ?? style[prefix] {
          if prefix == "padding" {
            try dimension(
              value, points: { YGNodeStyleSetPadding(node, edge, $0) },
              percent: { YGNodeStyleSetPaddingPercent(node, edge, $0) })
          } else {
            try dimension(
              value, points: { YGNodeStyleSetMargin(node, edge, $0) },
              percent: { YGNodeStyleSetMarginPercent(node, edge, $0) })
          }
        }
      }
    }
    for (key, gutter) in [
      ("gap", YGGutter.all), ("rowGap", YGGutter.row), ("columnGap", YGGutter.column),
    ] {
      if let value = style[key] {
        try dimension(
          value, points: { YGNodeStyleSetGap(node, gutter, $0) },
          percent: { YGNodeStyleSetGapPercent(node, gutter, $0) })
      }
    }
    for (key, setter) in [
      "flexGrow": YGNodeStyleSetFlexGrow, "flexShrink": YGNodeStyleSetFlexShrink,
      "aspectRatio": YGNodeStyleSetAspectRatio,
    ] {
      if let value = style[key] {
        guard let number = value.number else { throw MotionError("\(key) requires a number") }
        setter(node, Float(number))
      }
    }
    if let direction = style["flexDirection"]?.string {
      let choices = [
        "row": YGFlexDirection.row, "column": YGFlexDirection.column,
        "row-reverse": YGFlexDirection.rowReverse, "column-reverse": YGFlexDirection.columnReverse,
      ]
      guard let value = choices[direction] else {
        throw MotionError("Invalid flexDirection: \(direction)")
      }
      YGNodeStyleSetFlexDirection(node, value)
    }
    if let value = style["position"]?.string {
      YGNodeStyleSetPositionType(
        node, value == "absolute" ? YGPositionType.absolute : YGPositionType.relative)
    }
    if style["display"]?.string == "none" { YGNodeStyleSetDisplay(node, YGDisplay.none) }
    let align = [
      "flex-start": YGAlign.flexStart, "center": YGAlign.center, "flex-end": YGAlign.flexEnd,
      "stretch": YGAlign.stretch, "baseline": YGAlign.baseline,
    ]
    if let key = style["alignItems"]?.string, let value = align[key] {
      YGNodeStyleSetAlignItems(node, value)
    }
    if let key = style["alignSelf"]?.string, let value = align[key] {
      YGNodeStyleSetAlignSelf(node, value)
    }
    let justify = [
      "flex-start": YGJustify.flexStart, "center": YGJustify.center, "flex-end": YGJustify.flexEnd,
      "space-between": YGJustify.spaceBetween, "space-around": YGJustify.spaceAround,
      "space-evenly": YGJustify.spaceEvenly,
    ]
    if let key = style["justifyContent"]?.string, let value = justify[key] {
      YGNodeStyleSetJustifyContent(node, value)
    }
    if let wrap = style["flexWrap"]?.string {
      YGNodeStyleSetFlexWrap(node, wrap == "wrap" ? YGWrap.wrap : YGWrap.noWrap)
    }
  }

  private static func applyDimensions(_ style: [String: JSONValue], to node: YGNodeRef) throws {
    let dimensions: [String: ((YGNodeRef, Float) -> Void, (YGNodeRef, Float) -> Void)] = [
      "width": (YGNodeStyleSetWidth, YGNodeStyleSetWidthPercent),
      "height": (YGNodeStyleSetHeight, YGNodeStyleSetHeightPercent),
      "minWidth": (YGNodeStyleSetMinWidth, YGNodeStyleSetMinWidthPercent),
      "maxWidth": (YGNodeStyleSetMaxWidth, YGNodeStyleSetMaxWidthPercent),
      "minHeight": (YGNodeStyleSetMinHeight, YGNodeStyleSetMinHeightPercent),
      "maxHeight": (YGNodeStyleSetMaxHeight, YGNodeStyleSetMaxHeightPercent),
      "flexBasis": (YGNodeStyleSetFlexBasis, YGNodeStyleSetFlexBasisPercent),
    ]
    for (key, functions) in dimensions {
      if let value = style[key] {
        if key == "flexBasis" && value.string == "auto" { YGNodeStyleSetFlexBasisAuto(node); continue }
        try dimension(value, points: { functions.0(node, $0) }, percent: { functions.1(node, $0) })
      }
    }
  }

}
