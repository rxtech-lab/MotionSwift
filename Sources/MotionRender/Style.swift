import Foundation
import MotionCore

struct Style {
  let values: [String: JSONValue]
  static let allowed: Set<String> = [
    "position", "left", "top", "right", "bottom", "width", "height", "display", "flexDirection",
    "justifyContent", "alignItems", "alignSelf", "flexWrap", "flexGrow", "flexShrink", "flexBasis",
    "aspectRatio",
    "minWidth", "maxWidth", "minHeight", "maxHeight", "inset", "gap", "rowGap", "columnGap",
    "padding", "margin",
    "paddingLeft", "paddingRight", "paddingTop", "paddingBottom", "marginLeft", "marginRight",
    "marginTop", "marginBottom", "backgroundColor", "background", "opacity",
    "borderRadius", "overflow", "transform", "transformOrigin", "color", "fontSize", "fontFamily",
    "backgroundImage", "boxShadow", "filter", "backdropFilter", "mixBlendMode", "clipPath", "maskImage",
    "objectFit", "flex", "zIndex", "boxSizing", "pointerEvents", "userSelect", "cursor",
    "border", "borderTop", "borderRight", "borderBottom", "borderLeft",
    "borderWidth", "borderColor", "borderStyle",
    "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth",
    "borderTopColor", "borderRightColor", "borderBottomColor", "borderLeftColor",
    "borderTopStyle", "borderRightStyle", "borderBottomStyle", "borderLeftStyle",
    "fontWeight", "fontStyle", "lineHeight", "letterSpacing", "textAlign", "whiteSpace", "textTransform",
  ]

  init(_ values: [String: JSONValue]) throws {
    let unsupported = Set(values.keys).subtracting(Self.allowed)
    guard unsupported.isEmpty else {
      throw MotionError(
        "ms/unsupported-css-property: \(unsupported.sorted().joined(separator: ", "))")
    }
    self.values = values
    let strings: Set<String> = [
      "position", "display", "flexDirection", "justifyContent", "alignItems", "alignSelf",
      "flexWrap", "overflow", "transform", "transformOrigin", "color", "background",
      "cursor", "borderColor", "borderStyle", "borderTopColor", "borderRightColor", "borderBottomColor", "borderLeftColor",
      "borderTopStyle", "borderRightStyle", "borderBottomStyle", "borderLeftStyle",
      "backgroundColor", "fontFamily", "objectFit", "backgroundImage", "boxShadow", "filter",
      "backdropFilter", "mixBlendMode", "clipPath", "maskImage",
    ]
    let numbers: Set<String> = ["opacity", "fontSize", "flexGrow", "flexShrink", "aspectRatio"]
    for (key, value) in values {
      if strings.contains(key), value.string == nil {
        throw MotionError("\(key) requires a string")
      }
      if numbers.contains(key), value.number == nil {
        throw MotionError("\(key) requires a number")
      }
      if value.string == nil && value.number == nil {
        throw MotionError("Invalid style value: \(key)")
      }
    }
    for (key, value) in values {
      if case .number(let number) = value, !number.isFinite {
        throw MotionError("Non-finite style: \(key)")
      }
    }
    try require("position", among: ["absolute", "relative"])
    try require("display", among: ["flex", "inline-flex", "inline", "inline-block", "none"])
    try require("flexDirection", among: ["row", "column", "row-reverse", "column-reverse"])
    try require(
      "justifyContent",
      among: ["flex-start", "center", "flex-end", "space-between", "space-around", "space-evenly"])
    try require("alignItems", among: ["flex-start", "center", "flex-end", "stretch", "baseline"])
    try require("alignSelf", among: ["flex-start", "center", "flex-end", "stretch", "baseline"])
    try require("flexWrap", among: ["wrap", "nowrap"])
    try require("overflow", among: ["hidden", "visible"])
    try require("objectFit", among: ["contain", "cover", "fill"])
    try require("boxSizing", among: ["border-box", "content-box"])
    try require("pointerEvents", among: ["auto", "none"])
    try require("userSelect", among: ["auto", "none", "text", "all"])
    if let zIndex = values["zIndex"], zIndex.string != "auto" {
      guard let number = zIndex.number, number.rounded() == number else {
        throw MotionError("ms/unsupported-css-value: zIndex requires an integer or auto")
      }
    }
  }

  func require(_ key: String, among choices: Set<String>) throws {
    if let value = values[key], !choices.contains(value.string ?? "") {
      throw MotionError("Unsupported \(key): \(value)")
    }
  }

  func string(_ key: String, _ fallback: String = "") -> String { values[key]?.string ?? fallback }

  func length(_ key: String, relativeTo parent: Double, fallback: Double = 0) throws -> Double {
    guard let value = values[key] else { return fallback }
    if let number = value.number { return number }
    if let text = value.string {
      if text.hasSuffix("%"), let number = Double(text.dropLast()) { return number * parent / 100 }
      if text.hasSuffix("px"), let number = Double(text.dropLast(2)) { return number }
    }
    throw MotionError("Unsupported length for \(key): \(value)")
  }

  static func color(_ value: String) throws -> UInt32 { try CSSColor.parse(value) }

  func origin(width: Double, height: Double) throws -> (Double, Double) {
    let tokens = string("transformOrigin", "center").split(separator: " ").map(String.init)
    guard (1...2).contains(tokens.count) else { throw MotionError("Unsupported transformOrigin") }
    var x = tokens[0], y = tokens.count == 2 ? tokens[1] : "center"
    if ["top", "bottom"].contains(x) || ["left", "right"].contains(y) { swap(&x, &y) }
    // Parse lengths without constructing a validated style with an unknown key.
    func resolve(_ text: String, size: Double, low: String, high: String) throws -> Double {
      if text == "center" { return size/2 }
      if text == low { return 0 }
      if text == high { return size }
      if text.hasSuffix("%"), let number = Double(text.dropLast()), number.isFinite { return size*number/100 }
      if text.hasSuffix("px"), let number = Double(text.dropLast(2)), number.isFinite { return number }
      if text == "0" { return 0 }
      throw MotionError("ms/unsupported-css-value: transformOrigin")
    }
    return (try resolve(x, size: width, low: "left", high: "right"),
            try resolve(y, size: height, low: "top", high: "bottom"))
  }
}
