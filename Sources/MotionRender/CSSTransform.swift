import Foundation
import MotionCore

/// CSS transform lists multiply in source order. Each element is a flat plane;
/// preserve-3d scene graphs and perspective on ancestors are intentionally rejected.
enum CSSTransform {
  static let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

  static func multiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
    (0..<16).map { index in
      let row = index / 4, column = index % 4
      return (0..<4).reduce(0) { $0 + lhs[row * 4 + $1] * rhs[$1 * 4 + column] }
    }
  }

  static func matrix(_ text: String, width: Double, height: Double) throws -> [Double] {
    var matrix = identity
    for (name, arguments) in try Effects.functions(text) {
      let args = arguments.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
      var next = identity
      func require(_ counts: Set<Int>) throws {
        guard counts.contains(args.count) else { throw MotionError("Unsupported transform: \(name)(\(arguments))") }
      }
      func length(_ index: Int, _ relative: Double? = nil) throws -> Double {
        // Existing compositions use unitless translate values as CSS pixels.
        if let value = Double(args[index]), value.isFinite { return value }
        return try Effects.number(args[index], unit: "px", relative: relative)
      }
      func scalar(_ index: Int) throws -> Double { try Effects.number(args[index]) }
      func angle() throws -> Double {
        let arg = args[0]
        if arg.hasSuffix("deg") { return try Effects.number(arg, unit: "deg") * .pi / 180 }
        if arg.hasSuffix("rad") { return try Effects.number(arg, unit: "rad") }
        if arg.hasSuffix("turn") { return try Effects.number(arg, unit: "turn") * .pi * 2 }
        if arg == "0" { return 0 }
        throw MotionError("Unsupported transform angle: \(arg)")
      }
      switch name {
      case "translateX", "translateY", "translateZ":
        try require([1])
        let axis = name == "translateX" ? 3 : name == "translateY" ? 7 : 11
        next[axis] = try length(0, name == "translateX" ? width : name == "translateY" ? height : nil)
      case "translate", "translate3d":
        try require(name == "translate" ? [1, 2] : [3])
        next[3] = try length(0, width)
        next[7] = args.count > 1 ? try length(1, height) : 0
        if args.count == 3 { next[11] = try length(2) }
      case "scale", "scale3d":
        try require(name == "scale" ? [1, 2] : [3])
        next[0] = try scalar(0); next[5] = args.count > 1 ? try scalar(1) : next[0]
        if args.count == 3 { next[10] = try scalar(2) }
      case "scaleX", "scaleY", "scaleZ":
        try require([1]); next[name == "scaleX" ? 0 : name == "scaleY" ? 5 : 10] = try scalar(0)
      case "rotate", "rotateZ", "rotateX", "rotateY":
        try require([1]); let radians = try angle(), cosine = cos(radians), sine = sin(radians)
        if name == "rotateX" {
          next[5] = cosine; next[6] = -sine; next[9] = sine; next[10] = cosine
        } else if name == "rotateY" {
          next[0] = cosine; next[2] = sine; next[8] = -sine; next[10] = cosine
        } else {
          next[0] = cosine; next[1] = -sine; next[4] = sine; next[5] = cosine
        }
      case "skewX", "skewY":
        try require([1]); next[name == "skewX" ? 1 : 4] = tan(try angle())
      case "perspective":
        try require([1]); let distance = try length(0)
        guard distance > 0 else { throw MotionError("Perspective must be positive") }
        next[14] = -1 / max(1, distance)
      case "matrix":
        try require([6]); let values = try args.map { try Effects.number($0) }
        next = [values[0], values[2], 0, values[4], values[1], values[3], 0, values[5], 0, 0, 1, 0, 0, 0, 0, 1]
      case "matrix3d":
        try require([16]); let values = try args.map { try Effects.number($0) }
        next = (0..<16).map { values[($0 % 4) * 4 + $0 / 4] }
      default: throw MotionError("ms/unsupported-css-value: transform \(name)")
      }
      matrix = multiply(matrix, next)
    }
    guard matrix.allSatisfy({ $0.isFinite && Float($0).isFinite }) else { throw MotionError("Non-finite transform") }
    // x/y of a plane at z=0, divided by projected w.
    return [matrix[0], matrix[1], matrix[3], matrix[4], matrix[5], matrix[7], matrix[12], matrix[13], matrix[15]]
  }
}
