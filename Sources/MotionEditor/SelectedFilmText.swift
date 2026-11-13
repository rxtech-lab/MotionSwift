import Foundation
import MotionCore
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads the SVG text rendered by the showcase's source-owned EditableLayer adapter.
/// This supplies the initial draft even for working copies created before text controls existed.
enum SelectedFilmText {
  static func content(in node: RenderNode) -> String? { reader(in: node)?.text }

  static func fontSize(in node: RenderNode) -> Double? { reader(in: node)?.fontSize }

  private static func reader(in node: RenderNode) -> TextReader? {
    if let src = node.src, src.hasPrefix("data:image/svg+xml"),
       let comma = src.firstIndex(of: ","),
       let svg = String(src[src.index(after: comma)...]).removingPercentEncoding {
      let reader = TextReader()
      let parser = XMLParser(data: Data(svg.utf8))
      parser.delegate = reader
      if parser.parse(), reader.found { return reader }
    }
    return node.children.lazy.compactMap { reader(in: $0) }.first
  }

  private final class TextReader: NSObject, XMLParserDelegate {
    var text = ""
    var found = false
    var fontSize: Double?
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
      if elementName == "text", fontSize == nil { fontSize = attributes["font-size"].flatMap(Double.init) }
      if elementName == "text" || depth > 0 {
        depth += 1
        found = true
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      if depth > 0 { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
      if depth > 0 { depth -= 1 }
    }
  }
}
