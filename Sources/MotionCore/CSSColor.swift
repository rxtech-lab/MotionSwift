import Foundation

/// sRGB CSS colors. Values are clamped and rounded to unpremultiplied ARGB8.
public enum CSSColor {
  // CSS named-color constants (sRGB), including aliases.
  private static let named: [String: UInt32] = [
      "transparent": 0,
      "aliceblue": 0xFFF0F8FF,
      "antiquewhite": 0xFFFAEBD7,
      "aqua": 0xFF00FFFF,
      "aquamarine": 0xFF7FFFD4,
      "azure": 0xFFF0FFFF,
      "beige": 0xFFF5F5DC,
      "bisque": 0xFFFFE4C4,
      "black": 0xFF000000,
      "blanchedalmond": 0xFFFFEBCD,
      "blue": 0xFF0000FF,
      "blueviolet": 0xFF8A2BE2,
      "brown": 0xFFA52A2A,
      "burlywood": 0xFFDEB887,
      "cadetblue": 0xFF5F9EA0,
      "chartreuse": 0xFF7FFF00,
      "chocolate": 0xFFD2691E,
      "coral": 0xFFFF7F50,
      "cornflowerblue": 0xFF6495ED,
      "cornsilk": 0xFFFFF8DC,
      "crimson": 0xFFDC143C,
      "cyan": 0xFF00FFFF,
      "darkblue": 0xFF00008B,
      "darkcyan": 0xFF008B8B,
      "darkgoldenrod": 0xFFB8860B,
      "darkgray": 0xFFA9A9A9,
      "darkgreen": 0xFF006400,
      "darkgrey": 0xFFA9A9A9,
      "darkkhaki": 0xFFBDB76B,
      "darkmagenta": 0xFF8B008B,
      "darkolivegreen": 0xFF556B2F,
      "darkorange": 0xFFFF8C00,
      "darkorchid": 0xFF9932CC,
      "darkred": 0xFF8B0000,
      "darksalmon": 0xFFE9967A,
      "darkseagreen": 0xFF8FBC8F,
      "darkslateblue": 0xFF483D8B,
      "darkslategray": 0xFF2F4F4F,
      "darkslategrey": 0xFF2F4F4F,
      "darkturquoise": 0xFF00CED1,
      "darkviolet": 0xFF9400D3,
      "deeppink": 0xFFFF1493,
      "deepskyblue": 0xFF00BFFF,
      "dimgray": 0xFF696969,
      "dimgrey": 0xFF696969,
      "dodgerblue": 0xFF1E90FF,
      "firebrick": 0xFFB22222,
      "floralwhite": 0xFFFFFAF0,
      "forestgreen": 0xFF228B22,
      "fuchsia": 0xFFFF00FF,
      "gainsboro": 0xFFDCDCDC,
      "ghostwhite": 0xFFF8F8FF,
      "gold": 0xFFFFD700,
      "goldenrod": 0xFFDAA520,
      "gray": 0xFF808080,
      "green": 0xFF008000,
      "greenyellow": 0xFFADFF2F,
      "grey": 0xFF808080,
      "honeydew": 0xFFF0FFF0,
      "hotpink": 0xFFFF69B4,
      "indianred": 0xFFCD5C5C,
      "indigo": 0xFF4B0082,
      "ivory": 0xFFFFFFF0,
      "khaki": 0xFFF0E68C,
      "lavender": 0xFFE6E6FA,
      "lavenderblush": 0xFFFFF0F5,
      "lawngreen": 0xFF7CFC00,
      "lemonchiffon": 0xFFFFFACD,
      "lightblue": 0xFFADD8E6,
      "lightcoral": 0xFFF08080,
      "lightcyan": 0xFFE0FFFF,
      "lightgoldenrodyellow": 0xFFFAFAD2,
      "lightgray": 0xFFD3D3D3,
      "lightgreen": 0xFF90EE90,
      "lightgrey": 0xFFD3D3D3,
      "lightpink": 0xFFFFB6C1,
      "lightsalmon": 0xFFFFA07A,
      "lightseagreen": 0xFF20B2AA,
      "lightskyblue": 0xFF87CEFA,
      "lightslategray": 0xFF778899,
      "lightslategrey": 0xFF778899,
      "lightsteelblue": 0xFFB0C4DE,
      "lightyellow": 0xFFFFFFE0,
      "lime": 0xFF00FF00,
      "limegreen": 0xFF32CD32,
      "linen": 0xFFFAF0E6,
      "magenta": 0xFFFF00FF,
      "maroon": 0xFF800000,
      "mediumaquamarine": 0xFF66CDAA,
      "mediumblue": 0xFF0000CD,
      "mediumorchid": 0xFFBA55D3,
      "mediumpurple": 0xFF9370DB,
      "mediumseagreen": 0xFF3CB371,
      "mediumslateblue": 0xFF7B68EE,
      "mediumspringgreen": 0xFF00FA9A,
      "mediumturquoise": 0xFF48D1CC,
      "mediumvioletred": 0xFFC71585,
      "midnightblue": 0xFF191970,
      "mintcream": 0xFFF5FFFA,
      "mistyrose": 0xFFFFE4E1,
      "moccasin": 0xFFFFE4B5,
      "navajowhite": 0xFFFFDEAD,
      "navy": 0xFF000080,
      "oldlace": 0xFFFDF5E6,
      "olive": 0xFF808000,
      "olivedrab": 0xFF6B8E23,
      "orange": 0xFFFFA500,
      "orangered": 0xFFFF4500,
      "orchid": 0xFFDA70D6,
      "palegoldenrod": 0xFFEEE8AA,
      "palegreen": 0xFF98FB98,
      "paleturquoise": 0xFFAFEEEE,
      "palevioletred": 0xFFDB7093,
      "papayawhip": 0xFFFFEFD5,
      "peachpuff": 0xFFFFDAB9,
      "peru": 0xFFCD853F,
      "pink": 0xFFFFC0CB,
      "plum": 0xFFDDA0DD,
      "powderblue": 0xFFB0E0E6,
      "purple": 0xFF800080,
      "rebeccapurple": 0xFF663399,
      "red": 0xFFFF0000,
      "rosybrown": 0xFFBC8F8F,
      "royalblue": 0xFF4169E1,
      "saddlebrown": 0xFF8B4513,
      "salmon": 0xFFFA8072,
      "sandybrown": 0xFFF4A460,
      "seagreen": 0xFF2E8B57,
      "seashell": 0xFFFFF5EE,
      "sienna": 0xFFA0522D,
      "silver": 0xFFC0C0C0,
      "skyblue": 0xFF87CEEB,
      "slateblue": 0xFF6A5ACD,
      "slategray": 0xFF708090,
      "slategrey": 0xFF708090,
      "snow": 0xFFFFFAFA,
      "springgreen": 0xFF00FF7F,
      "steelblue": 0xFF4682B4,
      "tan": 0xFFD2B48C,
      "teal": 0xFF008080,
      "thistle": 0xFFD8BFD8,
      "tomato": 0xFFFF6347,
      "turquoise": 0xFF40E0D0,
      "violet": 0xFFEE82EE,
      "wheat": 0xFFF5DEB3,
      "white": 0xFFFFFFFF,
      "whitesmoke": 0xFFF5F5F5,
      "yellow": 0xFFFFFF00,
      "yellowgreen": 0xFF9ACD32,
    ]

  public static func parse(_ input: String, current: String = "black") throws -> UInt32 {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value == "currentcolor" { return try parse(current.lowercased() == "currentcolor" ? "black" : current) }
    if let color = named[value] { return color }
    if value.hasPrefix("#") {
      var digits = String(value.dropFirst())
      if digits.count == 3 || digits.count == 4 { digits = digits.map { "\($0)\($0)" }.joined() }
      if let raw = UInt32(digits, radix: 16) {
        if digits.count == 6 { return 0xFF000000 | raw }
        if digits.count == 8 { return raw >> 8 | (raw & 255) << 24 }
      }
    }
    if let start = value.firstIndex(of: "("), value.hasSuffix(")") {
      let name = String(value[..<start])
      let parts = value[value.index(after: start)..<value.index(before: value.endIndex)]
        .split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace }).map(String.init)
      if (3...4).contains(parts.count) {
        func number(_ part: String, scale: Double) -> Double? {
          part.hasSuffix("%") ? Double(part.dropLast()).map { $0 * scale / 100 } : Double(part)
        }
        let alpha = parts.count == 4 ? number(parts[3], scale: 1) : 1
        if let alpha, alpha.isFinite {
          var rgb: [Double] = []
          if name == "rgb" || name == "rgba" {
            rgb = parts.prefix(3).compactMap { number($0, scale: 255) }
          } else if name == "hsl" || name == "hsla" {
            let hue = parts[0].hasSuffix("deg") ? String(parts[0].dropLast(3)) : parts[0]
            if parts[1].hasSuffix("%"), parts[2].hasSuffix("%"),
              let hueDegrees = Double(hue), let saturationValue = number(parts[1], scale: 1),
              let lightnessValue = number(parts[2], scale: 1), hueDegrees.isFinite,
              saturationValue.isFinite, lightnessValue.isFinite {
              let saturation = min(1, max(0, saturationValue)), lightness = min(1, max(0, lightnessValue))
              let amplitude = saturation * min(lightness, 1-lightness)
              rgb = [0.0, 8, 4].map { offset in
                let position = (offset + hueDegrees/30).truncatingRemainder(dividingBy: 12)
                let wrapped = position < 0 ? position+12 : position
                return 255*(lightness-amplitude*max(-1, min(wrapped-3, 9-wrapped, 1)))
              }
            }
          }
          if rgb.count == 3 && rgb.allSatisfy(\.isFinite) {
            func byte(_ value: Double) -> UInt32 { UInt32(min(255, max(0, value)).rounded()) }
            return byte(alpha*255)<<24 | byte(rgb[0])<<16 | byte(rgb[1])<<8 | byte(rgb[2])
          }
        }
      }
    }
    throw MotionError("ms/unsupported-css-value: Unsupported color: \(input)")
  }
}
