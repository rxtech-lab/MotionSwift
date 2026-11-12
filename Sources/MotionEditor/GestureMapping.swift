import CoreGraphics
import Foundation
import MotionCore

/// A canvas gesture in composition (CSS) pixels.
public enum CanvasGesture: Equatable, Sendable {
  case move(dx: Double, dy: Double)
  case resize(handle: ResizeHandle, dx: Double, dy: Double, keepsAspectRatio: Bool)
  case rotate(degrees: Double)
}

public enum ResizeHandle: String, CaseIterable, Sendable {
  case topLeading, topTrailing, bottomLeading, bottomTrailing

  var movesLeadingEdge: Bool { self == .topLeading || self == .bottomLeading }
  var movesTopEdge: Bool { self == .topLeading || self == .topTrailing }
}

/// Why a gesture cannot be written back. Shown to the user instead of rewriting surprising source.
public struct GestureRefusal: Error, Equatable, CustomStringConvertible, Sendable {
  public let description: String
  public init(_ message: String) { description = message }
}

/// The element a gesture edits: its style as written (reconciled at the current frame), its layout
/// box and its parent's box, all in composition pixels.
public struct GestureTarget: Sendable {
  public var style: [String: JSONValue]
  public var box: CGRect
  public var parent: CGRect

  public init(style: [String: JSONValue], box: CGRect, parent: CGRect) {
    self.style = style
    self.box = box
    self.parent = parent
  }

  var isAbsolute: Bool { style["position"]?.string == "absolute" }
}

/// Maps gestures to style patches (see docs/editor.md → Canvas editing). The same patch drives the
/// live preview override and, on gesture end, one `setStyle` operation per key.
public enum GestureMapper {
  /// Style keys the gesture would write, so the editor can refuse before the gesture starts.
  public static func keys(for gesture: CanvasGesture, target: GestureTarget) -> [String] {
    switch gesture {
    case .move:
      guard target.isAbsolute else { return ["transform"] }
      return [horizontalAnchor(target.style), verticalAnchor(target.style)]
    case .resize(let handle, _, _, _):
      var keys = ["width", "height"]
      if target.isAbsolute {
        let horizontal = horizontalAnchor(target.style)
        if (horizontal == "left") == handle.movesLeadingEdge { keys.append(horizontal) }
        let vertical = verticalAnchor(target.style)
        if (vertical == "top") == handle.movesTopEdge { keys.append(vertical) }
      }
      return keys
    case .rotate:
      return ["transform"]
    }
  }

  public static func patch(for gesture: CanvasGesture, target: GestureTarget) throws -> [String: JSONValue] {
    var patch: [String: JSONValue] = [:]
    switch gesture {
    case .move(let dx, let dy):
      if target.isAbsolute {
        let horizontal = horizontalAnchor(target.style)
        let vertical = verticalAnchor(target.style)
        patch[horizontal] = try offset(target, horizontal, by: horizontal == "left" ? dx : -dx)
        patch[vertical] = try offset(target, vertical, by: vertical == "top" ? dy : -dy)
      } else {
        // Flex children move with a translate so their siblings stay put.
        var functions = try TransformList(target.style["transform"])
        functions.translate(by: dx, dy)
        patch["transform"] = .string(functions.description)
      }
    case .resize(let handle, let dx, let dy, let keepsAspectRatio):
      let width = target.box.width
      let height = target.box.height
      var newWidth = width + (handle.movesLeadingEdge ? -dx : dx)
      var newHeight = height + (handle.movesTopEdge ? -dy : dy)
      if keepsAspectRatio, width > 0, height > 0 {
        let scale = max(newWidth / width, newHeight / height)
        newWidth = width * scale
        newHeight = height * scale
      }
      newWidth = max(1, newWidth.rounded())
      newHeight = max(1, newHeight.rounded())
      patch["width"] = try length(newWidth, like: target.style["width"])
      patch["height"] = try length(newHeight, like: target.style["height"])
      if target.isAbsolute {
        let horizontal = horizontalAnchor(target.style)
        // Moving the anchored edge shifts the anchor by the size change.
        if horizontal == "left", handle.movesLeadingEdge {
          patch["left"] = try offset(target, "left", by: width - newWidth)
        } else if horizontal == "right", !handle.movesLeadingEdge {
          patch["right"] = try offset(target, "right", by: width - newWidth)
        }
        let vertical = verticalAnchor(target.style)
        if vertical == "top", handle.movesTopEdge {
          patch["top"] = try offset(target, "top", by: height - newHeight)
        } else if vertical == "bottom", !handle.movesTopEdge {
          patch["bottom"] = try offset(target, "bottom", by: height - newHeight)
        }
      }
    case .rotate(let degrees):
      var functions = try TransformList(target.style["transform"])
      functions.rotate(by: degrees)
      patch["transform"] = .string(functions.description)
    }
    return patch
  }

  static func horizontalAnchor(_ style: [String: JSONValue]) -> String {
    style["left"] == nil && style["right"] != nil ? "right" : "left"
  }

  static func verticalAnchor(_ style: [String: JSONValue]) -> String {
    style["top"] == nil && style["bottom"] != nil ? "bottom" : "top"
  }

  /// The current offset for `key` (from style, or derived from layout), moved by `delta`.
  private static func offset(_ target: GestureTarget, _ key: String, by delta: Double) throws -> JSONValue {
    let current: Double
    if let value = target.style[key] {
      current = try pixels(value, key: key)
    } else {
      switch key {
      case "left": current = target.box.minX - target.parent.minX
      case "top": current = target.box.minY - target.parent.minY
      case "right": current = target.parent.maxX - target.box.maxX
      default: current = target.parent.maxY - target.box.maxY
      }
    }
    return try length((current + delta).rounded(), like: target.style[key])
  }

  static func pixels(_ value: JSONValue, key: String) throws -> Double {
    if let number = value.number { return number }
    if let string = value.string?.trimmingCharacters(in: .whitespaces) {
      if string.hasSuffix("px"), let number = Double(string.dropLast(2)) { return number }
      if let number = Double(string) { return number }
    }
    throw GestureRefusal("\(key) uses \(value.description); only pixel values can be dragged")
  }

  /// Keeps the value's form: numbers stay numbers, `"24px"` stays a px string.
  private static func length(_ value: Double, like previous: JSONValue?) throws -> JSONValue {
    if let previous, previous.number == nil {
      _ = try pixels(previous, key: "value")
      return .string("\(format(value))px")
    }
    return .number(value)
  }

  static func format(_ value: Double) -> String {
    let rounded = (value * 1000).rounded() / 1000
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
  }
}

/// A parsed CSS transform list. Editing changes only the matching function and keeps the order
/// of the others (docs/editor.md → Transform composition).
struct TransformList: CustomStringConvertible, Equatable {
  struct Function: Equatable {
    var name: String
    var arguments: [String]
  }

  var functions: [Function]

  init(_ value: JSONValue?) throws {
    guard let value, value != .null else {
      functions = []
      return
    }
    guard let string = value.string else { throw GestureRefusal("transform must be a string to edit it") }
    if string.trimmingCharacters(in: .whitespaces) == "none" {
      functions = []
      return
    }
    let expression = try NSRegularExpression(pattern: #"([A-Za-z]+)\(([^)]*)\)"#)
    let range = NSRange(string.startIndex..., in: string)
    var parsed: [Function] = []
    var consumed = ""
    for match in expression.matches(in: string, range: range) {
      guard let full = Range(match.range, in: string), let name = Range(match.range(at: 1), in: string),
        let arguments = Range(match.range(at: 2), in: string)
      else { continue }
      consumed += string[full]
      parsed.append(Function(
        name: String(string[name]),
        arguments: string[arguments].split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)))
    }
    guard consumed.filter({ !$0.isWhitespace }) == string.filter({ !$0.isWhitespace }) else {
      throw GestureRefusal("transform \"\(string)\" cannot be parsed for editing")
    }
    functions = parsed
  }

  var description: String {
    functions.map { "\($0.name)(\($0.arguments.joined(separator: ", ")))" }.joined(separator: " ")
  }

  private static func number(_ argument: String, unit: String) throws -> Double {
    let trimmed = argument.hasSuffix(unit) ? String(argument.dropLast(unit.count)) : argument
    guard let value = Double(trimmed) else { throw GestureRefusal("Cannot edit transform argument \(argument)") }
    return value
  }

  /// Combines translate/translateX/translateY into one translate at the first one's position.
  mutating func translate(by dx: Double, _ dy: Double) {
    var x = dx
    var y = dy
    var position: Int?
    var kept: [Function] = []
    for function in functions {
      switch function.name {
      case "translate":
        x += (try? Self.number(function.arguments.first ?? "0", unit: "px")) ?? 0
        if function.arguments.count > 1 { y += (try? Self.number(function.arguments[1], unit: "px")) ?? 0 }
      case "translateX": x += (try? Self.number(function.arguments.first ?? "0", unit: "px")) ?? 0
      case "translateY": y += (try? Self.number(function.arguments.first ?? "0", unit: "px")) ?? 0
      default:
        kept.append(function)
        continue
      }
      position = position ?? kept.count
    }
    let combined = Function(
      name: "translate", arguments: ["\(GestureMapper.format(x.rounded()))px", "\(GestureMapper.format(y.rounded()))px"])
    kept.insert(combined, at: position ?? 0)
    functions = kept
  }

  mutating func rotate(by degrees: Double) {
    if let index = functions.firstIndex(where: { $0.name == "rotate" }) {
      let current = (try? Self.number(functions[index].arguments.first ?? "0", unit: "deg")) ?? 0
      functions[index].arguments = ["\(GestureMapper.format(((current + degrees) * 10).rounded() / 10))deg"]
    } else {
      functions.append(Function(name: "rotate", arguments: ["\(GestureMapper.format((degrees * 10).rounded() / 10))deg"]))
    }
  }
}

/// A snapping guide in composition pixels.
public struct SnapGuide: Equatable, Hashable, Sendable {
  public enum Axis: Sendable { case vertical, horizontal }
  public let axis: Axis
  public let position: Double
}

public enum Snapping {
  /// Adjusts a move so the box's edges or center align with the canvas or sibling edges/centers
  /// within `threshold` pixels. Returns the adjusted translation and the active guides.
  public static func snap(
    box: CGRect, translation: CGSize, siblings: [CGRect], canvas: CGSize, threshold: Double
  ) -> (translation: CGSize, guides: [SnapGuide]) {
    let moved = box.offsetBy(dx: translation.width, dy: translation.height)
    let xTargets: [Double] = [0, canvas.width / 2, canvas.width] + siblings.flatMap { [$0.minX, $0.midX, $0.maxX] }
    let yTargets: [Double] = [0, canvas.height / 2, canvas.height] + siblings.flatMap { [$0.minY, $0.midY, $0.maxY] }
    func best(_ lines: [Double], _ targets: [Double]) -> (delta: Double, target: Double)? {
      var result: (delta: Double, target: Double)?
      for line in lines {
        for target in targets where abs(target - line) <= threshold {
          if result == nil || abs(target - line) < abs(result!.delta) { result = (target - line, target) }
        }
      }
      return result
    }
    var adjusted = translation
    var guides: [SnapGuide] = []
    if let x = best([moved.minX, moved.midX, moved.maxX], xTargets) {
      adjusted.width += x.delta
      guides.append(SnapGuide(axis: .vertical, position: x.target))
    }
    if let y = best([moved.minY, moved.midY, moved.maxY], yTargets) {
      adjusted.height += y.delta
      guides.append(SnapGuide(axis: .horizontal, position: y.target))
    }
    return (adjusted, guides)
  }
}

extension JSONValue {
  var description: String {
    switch self {
    case .number(let value): return GestureMapper.format(value)
    case .string(let value): return "\"\(value)\""
    case .bool(let value): return String(value)
    case .null: return "null"
    case .array: return "an array"
    case .object: return "an object"
    }
  }
}
