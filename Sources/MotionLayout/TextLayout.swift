import Foundation
import MotionCore
import SkiaKit

/// HTML inline runs share one paragraph. Box-bearing inline spans require inline-box layout.
enum TextLayout {
  static let inherited = ["color", "fontSize", "fontFamily", "fontWeight", "fontStyle",
                          "lineHeight", "letterSpacing", "textAlign", "whiteSpace", "textTransform"]
  static func isInline(_ node: RenderNode) -> Bool {
    if node.type == "#text" || node.type == "br" { return true }
    guard ["span", "strong", "b", "em", "i"].contains(node.type) else { return false }
    if node.style["position"]?.string == "absolute" { return false }
    if ["flex", "inline-flex", "inline-block", "none"].contains(node.style["display"]?.string ?? "") {
      return false
    }
    return node.children.allSatisfy(isInline)
  }

  static func runs(_ node: RenderNode) throws -> [TextRun] {
    var result: [TextRun] = []
    var previousSpace = true
    func visit(_ node: RenderNode, isRoot: Bool) throws {
      let style = node.style
      if !isRoot && node.type == "span" {
        let unsupported = Set(style.keys).subtracting(inherited)
        guard unsupported.isEmpty else {
          throw MotionError("Inline text span box styles are unsupported: \(unsupported.sorted())")
        }
      }
      if node.type == "br" {
        result.append(TextRun("\n")); previousSpace = true; return
      }
      if let raw = node.text {
        let whitespace = style["whiteSpace"]?.string ?? "normal"
        guard ["normal", "pre", "pre-wrap", "nowrap"].contains(whitespace) else {
          throw MotionError("Unsupported whiteSpace: \(whitespace)")
        }
        var text = raw
        if whitespace == "normal" || whitespace == "nowrap" {
          text = ""
          for char in raw {
            if char.isWhitespace {
              if !previousSpace { text.append(" ") }
              previousSpace = true
            } else { text.append(char); previousSpace = false }
          }
        }
        switch style["textTransform"]?.string {
        case "uppercase": text = text.uppercased()
        case "lowercase": text = text.lowercased()
        case nil, "none": break
        default: throw MotionError("Unsupported textTransform")
        }
        let size = style["fontSize"]?.number ?? 16
        guard size.isFinite, size > 0 else { throw MotionError("fontSize must be positive") }
        let weightValue = style["fontWeight"]
        let weight = weightValue?.number ?? Double(weightValue?.string ?? "")
          ?? (weightValue?.string == "bold" ? 700 : 400)
        let lineHeight = try parseLineHeight(style["lineHeight"], fontSize: size)
        let spacing = try parseLetterSpacing(style["letterSpacing"], fontSize: size)
        let color = try CSSColor.parse(style["color"]?.string ?? "black")
        result.append(TextRun(text, family: families(style["fontFamily"]?.string ?? "Arial"),
                              size: size, weight: Int(weight), italic: style["fontStyle"]?.string == "italic",
                              color: color, lineHeight: lineHeight, letterSpacing: spacing))
      }
      for child in node.children { try visit(child, isRoot: false) }
    }
    try visit(node, isRoot: true)
    // Collapsible trailing spaces do not contribute to CSS line width.
    if ["normal", "nowrap"].contains(node.style["whiteSpace"]?.string ?? "normal"), !result.isEmpty {
      result[result.count - 1].text = result.last!.text.replacingOccurrences(of: " +$", with: "", options: .regularExpression)
    }
    return result
  }

  private static func parseLineHeight(_ value: JSONValue?, fontSize: Double) throws -> Double {
    guard let value else { return 0 }
    if let number = value.number { return number }
    guard let text = value.string else { throw MotionError("Unsupported lineHeight: \(value)") }
    if text == "normal" { return 0 }
    if text.hasSuffix("px"), let pixels = Double(text.dropLast(2)), pixels.isFinite {
      return pixels / fontSize
    }
    if text.hasSuffix("%"), let percent = Double(text.dropLast()), percent.isFinite {
      return percent / 100
    }
    if let multiplier = Double(text), multiplier.isFinite { return multiplier }
    throw MotionError("Unsupported lineHeight: \(text)")
  }

  private static func parseLetterSpacing(_ value: JSONValue?, fontSize: Double) throws -> Double {
    guard let value else { return 0 }
    if let number = value.number { return number }
    guard let text = value.string else { throw MotionError("Unsupported letterSpacing: \(value)") }
    if text == "normal" || text == "0" || text == "-0" { return 0 }
    if text.hasSuffix("px"), let pixels = Double(text.dropLast(2)), pixels.isFinite { return pixels }
    if text.hasSuffix("em"), let ems = Double(text.dropLast(2)), ems.isFinite { return ems * fontSize }
    throw MotionError("Unsupported letterSpacing: \(text)")
  }

  private static func families(_ value: String) -> String {
    value.split(separator: ",").map {
      let family = $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      return ["sans-serif": "Arial", "serif": "Times New Roman", "monospace": "Courier New"][family] ?? family
    }.joined(separator: ",")
  }

}
