import Foundation
import MotionCore

/// The property picker only offers styles supported by the native renderer.
struct StylePropertyDefinition: Identifiable {
  enum Control {
    case length, number, opacity, color, text
    case options([String])
  }

  let id: String
  let control: Control

  static let all: [Self] = {
    var result: [Self] = []
    func add(_ keys: String, _ control: Control) {
      result += keys.split(separator: " ").map { Self(id: String($0), control: control) }
    }
    add("left top right bottom width height minWidth maxWidth minHeight maxHeight inset", .length)
    add("gap rowGap columnGap padding margin paddingLeft paddingRight paddingTop paddingBottom", .length)
    add("marginLeft marginRight marginTop marginBottom borderRadius flexBasis", .length)
    add("fontSize flexGrow flexShrink aspectRatio", .number)
    add("opacity", .opacity)
    add("color backgroundColor background", .color)
    add("fontFamily transform content", .text)
    add("position", .options(["relative", "absolute"]))
    add("display", .options(["flex", "none"]))
    add("flexDirection", .options(["row", "column", "row-reverse", "column-reverse"]))
    add("justifyContent", .options(["flex-start", "center", "flex-end", "space-between", "space-around", "space-evenly"]))
    add("alignItems alignSelf", .options(["stretch", "flex-start", "center", "flex-end"]))
    add("flexWrap", .options(["nowrap", "wrap"]))
    add("overflow", .options(["visible", "hidden"]))
    add("objectFit", .options(["fill", "contain", "cover"]))
    add("transformOrigin", .options(["center"]))
    return result.sorted { $0.id < $1.id }
  }()

  static func find(_ key: String) -> Self? { all.first { $0.id == key } }

  static func matching(_ query: String) -> [Self] {
    all.filter { query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) }
  }

  var defaultValue: JSONValue {
    switch control {
    case .options(let choices): return .string(choices[0])
    case .color: return .string("#ffffff")
    case .text: return .string(id == "transform" ? "none" : "Helvetica")
    case .opacity: return .number(1)
    case .number: return .number(id == "aspectRatio" ? 1 : id == "fontSize" ? 16 : 0)
    case .length: return .number(0)
    }
  }

  func value(text: String, unit: String) -> JSONValue? {
    switch control {
    case .length, .number, .opacity:
      guard let number = Double(text), number.isFinite else { return nil }
      if case .opacity = control, !(0...1).contains(number) { return nil }
      if id == "aspectRatio", number <= 0 { return nil }
      if ["fontSize", "flexGrow", "flexShrink"].contains(id), number < 0 { return nil }
      if case .length = control, unit == "%" { return .string("\(text)%") }
      return .number(number)
    case .options(let choices): return choices.contains(text) ? .string(text) : nil
    case .color: return Self.rgba(text) == nil ? nil : .string(text)
    case .text: return text.isEmpty ? nil : .string(text)
    }
  }

  static func rgba(_ text: String) -> [Double]? {
    let named = ["transparent": "#00000000", "black": "#000000", "white": "#ffffff",
                 "red": "#ff0000", "green": "#008000", "blue": "#0000ff"]
    let hex = named[text] ?? text
    guard hex.hasPrefix("#") else { return nil }
    var digits = String(hex.dropFirst())
    if digits.count == 3 || digits.count == 4 { digits = digits.map { "\($0)\($0)" }.joined() }
    if digits.count == 6 { digits += "ff" }
    guard digits.count == 8, let raw = UInt32(digits, radix: 16) else { return nil }
    return [24, 16, 8, 0].map { Double((raw >> $0) & 255) / 255 }
  }
}
