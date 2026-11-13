import Foundation
import MotionCore
import SkiaKit

/// Deliberately bounded CSS grammar. Every parser consumes the entire value.
enum Effects {
  static let blendModes = ["normal", "multiply", "screen", "overlay", "darken", "lighten", "color-dodge",
                           "color-burn", "hard-light", "soft-light", "difference", "exclusion", "hue",
                           "saturation", "color", "luminosity"]

  static func split(_ text: String, separator: Character = ",") throws -> [String] {
    var depth = 0
    var parts = [String]()
    var part = ""
    for character in text {
      if character == "(" { depth += 1 }
      if character == ")" { depth -= 1 }
      guard depth >= 0 else { throw MotionError("ms/unsupported-css-value: \(text)") }
      if character == separator && depth == 0 {
        parts.append(part.trimmingCharacters(in: .whitespaces)); part = ""
      } else { part.append(character) }
    }
    guard depth == 0 else { throw MotionError("ms/unsupported-css-value: \(text)") }
    parts.append(part.trimmingCharacters(in: .whitespaces))
    return parts
  }

  static func number(_ text: String, unit: String = "", relative: Double? = nil) throws -> Double {
    var value = text.trimmingCharacters(in: .whitespaces)
    var factor = 1.0
    if value.hasSuffix("%"), let relative {
      value.removeLast(); factor = relative / 100
    } else if !unit.isEmpty && value.hasSuffix(unit) {
      value.removeLast(unit.count)
    } else if !unit.isEmpty && value != "0" {
      throw MotionError("Expected \(unit): \(text)")
    }
    guard let result = Double(value), result.isFinite, Float(result * factor).isFinite else {
      throw MotionError("ms/unsupported-css-value: \(text)")
    }
    return result * factor
  }

  struct Gradient {
    var radial: Bool
    var geometry: [Double]
    var colors: [UInt32]
    var stops: [Double]

    func draw(on canvas: Canvas, width: Double, height: Double, radius: Double = 0, mask: Bool = false) throws {
      try canvas.gradient(width: width, height: height, radius: radius, radial: radial,
                          geometry: geometry, colors: colors, stops: stops, mask: mask)
    }
  }

  static func gradient(_ text: String, width: Double, height: Double) throws -> Gradient {
    let radial = text.hasPrefix("radial-gradient(")
    let prefix = radial ? "radial-gradient(" : "linear-gradient("
    guard text.hasPrefix(prefix), text.hasSuffix(")") else { throw MotionError("Unsupported gradient: \(text)") }
    var parts = try split(String(text.dropFirst(prefix.count).dropLast()))
    var geometry: [Double]
    if radial {
      // An explicit ellipse is required; no browser-dependent extent keywords.
      let args = parts.removeFirst().split(separator: " ").map(String.init)
      guard args.count == 6, args[0] == "ellipse", args[3] == "at" else {
        throw MotionError("Use radial-gradient(ellipse <rx>px <ry>px at <x> <y>, ...)")
      }
      let radii = try [number(args[1], unit: "px"), number(args[2], unit: "px")]
      guard radii.allSatisfy({ $0 > 0 }) else { throw MotionError("Gradient radii must be positive") }
      geometry = try [number(args[4], unit: "px", relative: width), number(args[5], unit: "px", relative: height)] + radii
    } else {
      var angle = 180.0
      if parts[0].hasSuffix("deg") { angle = try number(parts.removeFirst(), unit: "deg") } else if parts[0].hasPrefix("to ") {
        let directions = ["to top": 0.0, "to right": 90, "to bottom": 180, "to left": 270]
        guard let direction = directions[parts.removeFirst()] else { throw MotionError("Unsupported gradient direction") }
        angle = direction
      }
      let radians = angle * .pi / 180
      let x = sin(radians), y = -cos(radians)
      let extent = abs(width * x) + abs(height * y)
      geometry = [width / 2 - x * extent / 2, height / 2 - y * extent / 2,
                  width / 2 + x * extent / 2, height / 2 + y * extent / 2]
    }
    guard (2...256).contains(parts.count) else { throw MotionError("Gradients need 2...256 stops") }
    var colors = [UInt32](), stops = [Double?]()
    for part in parts {
      let tokens = part.split(separator: " ").map(String.init)
      guard (1...2).contains(tokens.count) else { throw MotionError("Unsupported gradient stop: \(part)") }
      colors.append(try Style.color(tokens[0]))
      stops.append(tokens.count == 2 ? try number(tokens[1], unit: "%", relative: 1) : nil)
    }
    if stops[0] == nil { stops[0] = 0 }
    if stops[stops.count - 1] == nil { stops[stops.count - 1] = 1 }
    var previous = 0
    for index in 1..<stops.count where stops[index] != nil {
      guard stops[index]! >= stops[previous]!, stops[index]! <= 1, stops[previous]! >= 0 else {
        throw MotionError("Gradient stops must ascend within 0...100%")
      }
      for missing in (previous + 1)..<index {
        stops[missing] = stops[previous]! + (stops[index]! - stops[previous]!) * Double(missing - previous) / Double(index - previous)
      }
      previous = index
    }
    return Gradient(radial: radial, geometry: geometry, colors: colors, stops: stops.map { $0! })
  }

  struct Shadow {
    var x: Double, y: Double, blur: Double, spread: Double
    var color: UInt32
    var inset: Bool
  }

  static func shadows(_ text: String) throws -> [Shadow] {
    if text.isEmpty || text == "none" { return [] }
    return try split(text).map { value in
      var tokens = value.split(separator: " ").map(String.init)
      let inset = tokens.first == "inset" || tokens.last == "inset"
      if tokens.first == "inset" { tokens.removeFirst() } else if tokens.last == "inset" { tokens.removeLast() }
      guard (3...5).contains(tokens.count) else { throw MotionError("Unsupported box-shadow: \(text)") }
      let color = try Style.color(tokens.removeLast())
      let lengths = try tokens.map { try number($0, unit: "px") }
      let blur = lengths.count > 2 ? lengths[2] : 0
      guard blur >= 0 else { throw MotionError("Shadow blur must be nonnegative") }
      return Shadow(x: lengths[0], y: lengths[1], blur: blur,
                    spread: lengths.count > 3 ? lengths[3] : 0, color: color, inset: inset)
    }
  }

  static func functions(_ text: String) throws -> [(String, String)] {
    if text.isEmpty || text == "none" { return [] }
    let regex = try NSRegularExpression(pattern: #"([a-zA-Z0-9-]+)\(([^()]*)\)"#)
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    var consumed = ""
    let result = matches.map { match -> (String, String) in
      consumed += text[Range(match.range, in: text)!]
      return (String(text[Range(match.range(at: 1), in: text)!]), String(text[Range(match.range(at: 2), in: text)!]))
    }
    guard consumed.filter({ !$0.isWhitespace }) == text.filter({ !$0.isWhitespace }) else {
      throw MotionError("ms/unsupported-css-value: \(text)")
    }
    return result
  }

  static func filters(_ text: String) throws -> [[Double]] {
    try functions(text).map { name, argument in
      if name == "blur" {
        let sigma = try number(argument, unit: "px")
        guard sigma >= 0 else { throw MotionError("Blur must be nonnegative") }
        return [0, sigma] + Array(repeating: 0, count: 19)
      }
      if name == "drop-shadow" {
        let parsed = try shadows(argument)
        guard parsed.count == 1, argument.split(whereSeparator: \.isWhitespace).count <= 4,
              let shadow = parsed.first, shadow.spread == 0, !shadow.inset else {
          throw MotionError("drop-shadow requires one shadow without spread/inset")
        }
        let color = shadow.color
        return [2, shadow.x, shadow.y, shadow.blur,
                Double((color >> 16) & 255) / 255, Double((color >> 8) & 255) / 255,
                Double(color & 255) / 255, Double(color >> 24) / 255] + Array(repeating: 0, count: 13)
      }
      if name == "hue-rotate" {
        let angle = try number(argument, unit: "deg") * .pi / 180
        let cosine = cos(angle), sine = sin(angle)
        return [1,
          0.213 + cosine * 0.787 - sine * 0.213, 0.715 - cosine * 0.715 - sine * 0.715, 0.072 - cosine * 0.072 + sine * 0.928, 0, 0,
          0.213 - cosine * 0.213 + sine * 0.143, 0.715 + cosine * 0.285 + sine * 0.140, 0.072 - cosine * 0.072 - sine * 0.283, 0, 0,
          0.213 - cosine * 0.213 - sine * 0.787, 0.715 - cosine * 0.715 + sine * 0.715, 0.072 + cosine * 0.928 + sine * 0.072, 0, 0,
          0, 0, 0, 1, 0]
      }
      let amount = try number(argument, relative: 1)
      guard amount >= 0 else { throw MotionError("Filter amount must be nonnegative") }
      var matrix: [Double] = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]
      switch name {
      case "brightness": matrix[0] = amount; matrix[6] = amount; matrix[12] = amount
      case "contrast":
        matrix[0] = amount; matrix[6] = amount; matrix[12] = amount
        matrix[4] = 0.5 * (1 - amount); matrix[9] = matrix[4]; matrix[14] = matrix[4]
      case "opacity": matrix[18] = min(amount, 1)
      case "invert":
        let value = min(amount, 1)
        matrix[0] = 1 - 2 * value; matrix[6] = matrix[0]; matrix[12] = matrix[0]
        matrix[4] = value; matrix[9] = value; matrix[14] = value
      case "saturate", "grayscale":
        let saturation = name == "grayscale" ? 1 - min(amount, 1) : amount
        let luminance = name == "saturate" ? [0.213, 0.715, 0.072] : [0.2126, 0.7152, 0.0722]
        for row in 0..<3 {
          for column in 0..<3 { matrix[row * 5 + column] = luminance[column] * (1 - saturation) + (row == column ? saturation : 0) }
        }
      case "sepia":
        let value = min(amount, 1), sepia = [0.393, 0.769, 0.189, 0.349, 0.686, 0.168, 0.272, 0.534, 0.131]
        for row in 0..<3 {
          for column in 0..<3 { matrix[row * 5 + column] = sepia[row * 3 + column] * value + (row == column ? 1 - value : 0) }
        }
      default: throw MotionError("ms/unsupported-css-value: filter \(name)")
      }
      return [1] + matrix
    }
  }

  static func clip(_ text: String, width: Double, height: Double) throws -> String? {
    if text.isEmpty || text == "none" { return nil }
    let functions = try functions(text)
    guard functions.count == 1 else { throw MotionError("Unsupported clip-path: \(text)") }
    let (name, argument) = functions[0]
    let tokens = argument.split(separator: " ").map(String.init)
    switch name {
    case "path":
      guard argument.first == "'", argument.last == "'" else { throw MotionError("Use path('...')") }
      return String(argument.dropFirst().dropLast())
    case "polygon":
      let points = try split(argument).map { point -> String in
        let pair = point.split(separator: " ").map(String.init)
        guard pair.count == 2 else { throw MotionError("Invalid polygon point") }
        return try "\(number(pair[0], unit: "px", relative: width)) \(number(pair[1], unit: "px", relative: height))"
      }
      guard points.count >= 3 else { throw MotionError("Polygon requires three points") }
      return "M" + points.joined(separator: "L") + "Z"
    case "inset":
      guard (1...4).contains(tokens.count) else { throw MotionError("Unsupported inset clip") }
      let top = try number(tokens[0], unit: "px", relative: height)
      let right = try number(tokens.count > 1 ? tokens[1] : tokens[0], unit: "px", relative: width)
      let bottom = try number(tokens.count > 2 ? tokens[2] : tokens[0], unit: "px", relative: height)
      let left = try number(tokens.count > 3 ? tokens[3] : tokens.count > 1 ? tokens[1] : tokens[0], unit: "px", relative: width)
      return "M\(left) \(top)H\(max(left, width - right))V\(max(top, height - bottom))H\(left)Z"
    case "circle", "ellipse":
      let radii = name == "circle" ? 1 : 2
      guard tokens.count == radii + 3, tokens[radii] == "at" else { throw MotionError("Use explicit radii and at x y") }
      let rx = try number(tokens[0], unit: "px", relative: name == "circle" ? hypot(width, height) / sqrt(2) : width)
      let ry = name == "circle" ? rx : try number(tokens[1], unit: "px", relative: height)
      let x = try number(tokens[radii + 1], unit: "px", relative: width)
      let y = try number(tokens[radii + 2], unit: "px", relative: height)
      guard rx >= 0, ry >= 0 else { throw MotionError("Negative clip radius") }
      return "M\(x - rx) \(y)A\(rx) \(ry) 0 1 0 \(x + rx) \(y)A\(rx) \(ry) 0 1 0 \(x - rx) \(y)Z"
    default: throw MotionError("ms/unsupported-css-value: clip-path \(text)")
    }
  }
}
