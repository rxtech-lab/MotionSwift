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
    "objectFit",
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
      "backgroundColor", "fontFamily", "objectFit",
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
    try require("display", among: ["flex", "none"])
    try require("flexDirection", among: ["row", "column", "row-reverse", "column-reverse"])
    try require(
      "justifyContent",
      among: ["flex-start", "center", "flex-end", "space-between", "space-around", "space-evenly"])
    try require("alignItems", among: ["flex-start", "center", "flex-end", "stretch"])
    try require("alignSelf", among: ["flex-start", "center", "flex-end", "stretch"])
    try require("flexWrap", among: ["wrap", "nowrap"])
    try require("overflow", among: ["hidden", "visible"])
    try require("objectFit", among: ["contain", "cover", "fill"])
    if let origin = values["transformOrigin"], origin.string != "center" {
      throw MotionError("Only transformOrigin: center is implemented")
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

  static func color(_ value: String) throws -> UInt32 {
    let named: [String: UInt32] = [
      "transparent": 0, "black": 0xFF00_0000, "white": 0xFFFF_FFFF,
      "red": 0xFFFF_0000, "green": 0xFF00_8000, "blue": 0xFF00_00FF,
    ]
    if let color = named[value] { return color }
    guard value.hasPrefix("#") else {
      throw MotionError("Unsupported color: \(value); use hex colors")
    }
    var digits = String(value.dropFirst())
    if digits.count == 3 || digits.count == 4 { digits = digits.map { "\($0)\($0)" }.joined() }
    guard let raw = UInt32(digits, radix: 16) else {
      throw MotionError("Invalid hex color: \(value)")
    }
    if digits.count == 6 { return 0xFF00_0000 | raw }
    if digits.count == 8 { return (raw >> 8) | ((raw & 255) << 24) }
    throw MotionError("Invalid hex color: \(value)")
  }
}
