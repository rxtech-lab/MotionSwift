import Foundation
import MotionCore
import yoga

public struct LayoutNode {
  public let node: RenderNode
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double
  public let children: [LayoutNode]
}

/// Yoga nodes and their config belong to one calculation; no C handles escape into the painter.
public enum LayoutEngine {
  public static func calculate(_ input: RenderNode, width: Double, height: Double) throws
    -> LayoutNode {
    guard let config = YGConfigNew() else { throw MotionError("Cannot allocate Yoga config") }
    defer { YGConfigFree(config) }
    YGConfigSetUseWebDefaults(config, true)
    YGConfigSetPointScaleFactor(config, 0)
    let resolved = inherit(input, parent: [:])
    let root = try build(resolved, config: config)
    defer { YGNodeFreeRecursive(root) }
    YGNodeStyleSetWidth(root, Float(width))
    YGNodeStyleSetHeight(root, Float(height))
    YGNodeCalculateLayout(root, Float(width), Float(height), YGDirection.LTR)
    return snapshot(resolved, handle: root)
  }

  private static func inherit(_ node: RenderNode, parent: [String: JSONValue]) -> RenderNode {
    var values = node.style
    for key in ["color", "fontSize", "fontFamily"] where values[key] == nil {
      values[key] = parent[key]
    }
    return RenderNode(
      type: node.type, style: values, text: node.text, src: node.src, source: node.source,
      children: node.children.map { inherit($0, parent: values) })
  }

  private static func build(_ input: RenderNode, config: YGConfigRef) throws -> YGNodeRef {
    guard let node = YGNodeNewWithConfig(config) else {
      throw MotionError("Cannot allocate Yoga node")
    }
    do {
      try apply(input.style, to: node)
      for (index, child) in input.children.enumerated() {
        YGNodeInsertChild(node, try build(child, config: config), index)
      }
      return node
    } catch {
      YGNodeFreeRecursive(node)
      throw error
    }
  }

  private static func snapshot(_ input: RenderNode, handle: YGNodeRef) -> LayoutNode {
    let children = input.children.enumerated().map { index, child in
      snapshot(child, handle: YGNodeGetChild(handle, index)!)
    }
    return LayoutNode(
      node: input, x: Double(YGNodeLayoutGetLeft(handle)), y: Double(YGNodeLayoutGetTop(handle)),
      width: Double(YGNodeLayoutGetWidth(handle)), height: Double(YGNodeLayoutGetHeight(handle)),
      children: children)
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
        try dimension(value, points: { functions.0(node, $0) }, percent: { functions.1(node, $0) })
      }
    }
    let edges: [(String, YGEdge)] = [
      ("Left", YGEdge.left), ("Right", YGEdge.right), ("Top", YGEdge.top),
      ("Bottom", YGEdge.bottom),
    ]
    for (suffix, edge) in edges {
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
      "stretch": YGAlign.stretch,
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
}
