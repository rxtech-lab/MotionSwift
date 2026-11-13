import Foundation
import MotionCore
import SkiaKit

/// HTML inline runs share one paragraph. Box-bearing inline spans require inline-box layout.
enum TextLayout {
  static let inherited = ["color", "fontSize", "fontFamily", "fontWeight", "fontStyle",
                          "lineHeight", "letterSpacing", "textAlign", "whiteSpace", "textTransform"]
  static func isInline(_ node: RenderNode) -> Bool {
    ["#text", "span", "br", "strong", "b", "em", "i"].contains(node.type)
      && node.children.allSatisfy(isInline)
  }

  static func runs(_ node: RenderNode) throws -> [TextRun] {
    var result: [TextRun] = []
    var previousSpace = true
    func visit(_ node: RenderNode) throws {
      let style = node.style
      if node.type == "span" {
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
        var lineHeight = style["lineHeight"]?.number ?? 0
        if let value = style["lineHeight"]?.string, value != "normal" {
          guard value.hasSuffix("px"), let pixels = Double(value.dropLast(2)) else {
            throw MotionError("Unsupported lineHeight: \(value)")
          }
          lineHeight = pixels / size
        }
        let color = try CSSColor.parse(style["color"]?.string ?? "black")
        result.append(TextRun(text, family: families(style["fontFamily"]?.string ?? "Arial"),
                              size: size, weight: Int(weight), italic: style["fontStyle"]?.string == "italic",
                              color: color, lineHeight: lineHeight,
                              letterSpacing: style["letterSpacing"]?.number ?? 0))
      }
      for child in node.children { try visit(child) }
    }
    try visit(node)
    // Collapsible trailing spaces do not contribute to CSS line width.
    if (node.style["whiteSpace"]?.string ?? "normal") == "normal", !result.isEmpty {
      result[result.count - 1].text = result.last!.text.replacingOccurrences(of: " +$", with: "", options: .regularExpression)
    }
    return result
  }

  private static func families(_ value: String) -> String {
    value.split(separator: ",").map {
      let family = $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      return ["sans-serif": "Arial", "serif": "Times New Roman", "monospace": "Courier New"][family] ?? family
    }.joined(separator: ",")
  }

}
