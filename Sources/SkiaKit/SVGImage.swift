import CoreText
import Foundation

/// Skia's primitive SVG shaper does not apply CSS letter spacing or switch fonts
/// for missing glyphs. Express these as SVG positioning and explicit font spans.
/// Geometry and rasterization still run entirely through Skia's SVG DOM.
enum SVGImage {
  static func prepare(_ data: Data) throws -> Data {
    let document = try XMLDocument(data: data, options: [.nodePreserveAll])
    for case let element as XMLElement in try document.nodes(forXPath: "//*[local-name()='text']") {
      // Nested text/tspan positioning is left to Skia. This normalization covers
      // plain text runs, including those produced by Film Studio's SVG serializer.
      guard let children = element.children, children.allSatisfy({ $0.kind == .text }),
        let text = element.stringValue, !text.isEmpty
      else { continue }
      let family = attribute("font-family", of: element) ?? "Helvetica Neue"
      let primary = family.split(separator: ",").first.map(String.init) ?? family
      let font = CTFontCreateWithName(
        primary.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) as CFString,
        Double(attribute("font-size", of: element) ?? "16") ?? 16, nil)
      let characters = Array(text)
      if let value = attribute("letter-spacing", of: element),
        let spacing = Double(value), spacing != 0, element.attribute(forName: "dx") == nil {
        // SVG relative offsets accumulate across characters. The initial offset
        // remains zero; spacing applies between characters, not before the run.
        let offsets = (["0"] + characters.dropFirst().map { _ in String(spacing) }).joined(separator: " ")
        element.addAttribute(XMLNode(kind: .attribute, options: []).named("dx", value: offsets))
      }
      var spans: [XMLNode] = []
      var changed = false
      for character in characters {
        let string = String(character)
        let units = Array(string.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        if CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) {
          let node = XMLNode(kind: .text)
          node.stringValue = string
          spans.append(node)
        } else {
          let fallback = CTFontCreateForString(font, string as CFString, CFRange(location: 0, length: units.count))
          let span = XMLElement(name: "tspan", stringValue: string)
          span.addAttribute(XMLNode(kind: .attribute, options: []).named(
            "font-family", value: CTFontCopyFamilyName(fallback) as String))
          spans.append(span)
          changed = true
        }
      }
      if changed { element.setChildren(spans) }
    }
    return document.xmlData
  }

  private static func attribute(_ name: String, of element: XMLElement) -> String? {
    if let value = element.attribute(forName: name)?.stringValue { return value }
    if let parent = element.parent as? XMLElement { return attribute(name, of: parent) }
    return nil
  }
}

private extension XMLNode {
  func named(_ name: String, value: String) -> XMLNode {
    self.name = name
    stringValue = value
    return self
  }
}
