import Foundation

/// Shared expansion keeps Yoga's border widths identical to the painter's widths.
public enum BoxStyle {
  public static func normalized(_ input: [String: JSONValue]) throws -> [String: JSONValue] {
    var style = input
    if let flex = input["flex"] {
      let values = try flexValues(flex)
      style["flexGrow"] = input["flexGrow"] ?? .number(values.grow)
      style["flexShrink"] = input["flexShrink"] ?? .number(values.shrink)
      style["flexBasis"] = input["flexBasis"] ?? values.basis
    }
    guard input.keys.contains(where: { $0.hasPrefix("border") && $0 != "borderRadius" }) else { return style }
    for side in ["Top", "Right", "Bottom", "Left"] {
      var width = 3.0
      var color = "currentColor"
      var line = "none"
      for key in ["border", "border" + side] {
        if let value = input[key] {
          guard let text = value.string else { throw MotionError("\(key) requires a string") }
          // Functional colors may contain spaces. Separate only outside parentheses.
          var depth = 0
          var token = ""
          var tokens: [String] = []
          for character in text {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if character.isWhitespace && depth == 0 {
              if !token.isEmpty { tokens.append(token); token = "" }
            } else { token.append(character) }
          }
          if !token.isEmpty { tokens.append(token) }
          width = 3; color = "currentColor"; line = "none"
          var colorCount = 0
          for part in tokens {
            if ["dashed", "dotted", "double", "groove", "ridge", "inset", "outset"].contains(part) {
              throw MotionError("ms/unsupported-css-value: unsupported border style \(part)")
            }
            if ["solid", "none", "hidden"].contains(part) {
              line = part
            } else if let number = Double(part.hasSuffix("px") ? String(part.dropLast(2)) : part) {
              width = number
            } else {
              colorCount += 1
              guard colorCount == 1 else { throw MotionError("ms/unsupported-css-value: border shorthand") }
              color = part
            }
          }
        }
      }
      if let value = input["border" + side + "Width"] ?? input["borderWidth"] {
        guard let number = value.number ?? value.string.flatMap({ Double($0.hasSuffix("px") ? String($0.dropLast(2)) : $0) }) else {
          throw MotionError("ms/unsupported-css-value: border width")
        }
        width = number
      }
      color = (input["border" + side + "Color"] ?? input["borderColor"])?.string ?? color
      line = (input["border" + side + "Style"] ?? input["borderStyle"])?.string ?? line
      guard ["solid", "none", "hidden"].contains(line), width.isFinite, Float(width).isFinite, width >= 0 else {
        throw MotionError("ms/unsupported-css-value: only nonnegative solid/none/hidden borders are supported")
      }
      style["border" + side + "Width"] = .number(line == "solid" ? width : 0)
      style["border" + side + "Color"] = .string(color)
    }
    return style
  }

  private struct FlexValues {
    let grow: Double
    let shrink: Double
    let basis: JSONValue
  }

  private static func flexValues(_ flex: JSONValue) throws -> FlexValues {
    let parts = flex.string?.split(separator: " ").map(String.init) ?? []
    if let number = flex.number, number >= 0 {
      return FlexValues(grow: number, shrink: 1, basis: .string("0%"))
    }
    switch parts {
    case ["none"]: return FlexValues(grow: 0, shrink: 0, basis: .string("auto"))
    case ["auto"]: return FlexValues(grow: 1, shrink: 1, basis: .string("auto"))
    case ["initial"]: return FlexValues(grow: 0, shrink: 1, basis: .string("auto"))
    default: break
    }
    guard (1...3).contains(parts.count), let grow = Double(parts[0]), grow >= 0 else {
      throw MotionError("ms/unsupported-css-value: flex")
    }
    if parts.count == 1 { return FlexValues(grow: grow, shrink: 1, basis: .string("0%")) }
    if let shrink = Double(parts[1]), shrink >= 0 {
      return FlexValues(grow: grow, shrink: shrink, basis: .string(parts.count == 3 ? parts[2] : "0%"))
    }
    if parts.count == 2 { return FlexValues(grow: grow, shrink: 1, basis: .string(parts[1])) }
    throw MotionError("ms/unsupported-css-value: flex")
  }

}
