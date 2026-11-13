import Foundation
import MotionCore
import SkiaKit

/// Border strips use the same expanded widths that reserve space in Yoga.
enum BorderPainter {
  static func paintsOpaqueRoundedBox(_ style: Style, radius: Double) throws -> Bool {
    guard radius > 0, let width = style.values["borderTopWidth"]?.number, width > 0 else { return false }
    let sides = ["Top", "Right", "Bottom", "Left"]
    guard sides.allSatisfy({ style.values["border" + $0 + "Width"]?.number == width }) else { return false }
    let colors = try sides.map {
      try CSSColor.parse(style.string("border" + $0 + "Color", "currentColor"), current: style.string("color", "black"))
    }
    let background = try CSSColor.parse(style.string("backgroundColor", style.string("background", "transparent")),
                                        current: style.string("color", "black"))
    return colors.allSatisfy({ $0 == colors[0] }) && colors[0] >> 24 == 255 && background >> 24 == 255
  }

  static func draw(_ style: Style, canvas: Canvas, width: Double, height: Double, radius: Double,
                   paintBackground: Bool = false) throws {
    let sides = ["Top", "Right", "Bottom", "Left"]
    let widths = sides.map { style.values["border" + $0 + "Width"]?.number ?? 0 }
    guard widths.contains(where: { $0 > 0 }) else { return }
    let colors = try sides.map {
      try CSSColor.parse(style.string("border" + $0 + "Color", "currentColor"), current: style.string("color", "black"))
    }
    func color(_ argb: UInt32) -> String {
      "rgba(\((argb >> 16) & 255),\((argb >> 8) & 255),\(argb & 255),\(Double(argb >> 24)/255))"
    }
    let top = widths[0], right = widths[1], bottom = widths[2], left = widths[3]
    if paintBackground {
      // Paint the opaque outer border first so background AA cannot tint its silhouette.
      canvas.rectangle(width: width, height: height, radius: radius, color: colors[0])
      let background = try CSSColor.parse(style.string("backgroundColor", style.string("background", "transparent")),
                                          current: style.string("color", "black"))
      canvas.rectangle(x: left, y: top, width: max(0, width-left-right), height: max(0, height-top-bottom),
                       radius: max(0, radius-top), color: background)
      return
    }
    var shapes = ""
    if radius > 0 {
      guard widths.allSatisfy({ $0 == top }), colors.allSatisfy({ $0 == colors[0] }) else {
        throw MotionError("ms/unsupported-css-value: rounded borders require uniform width and color")
      }
      func roundedPath(x: Double, y: Double, width: Double, height: Double, radius: Double) -> String {
        let edge = min(max(0, radius), max(0, min(width, height)/2))
        let right = x + width, bottom = y + height
        return "M\(x+edge) \(y)H\(right-edge)A\(edge) \(edge) 0 0 1 \(right) \(y+edge)"
          + "V\(bottom-edge)A\(edge) \(edge) 0 0 1 \(right-edge) \(bottom)"
          + "H\(x+edge)A\(edge) \(edge) 0 0 1 \(x) \(bottom-edge)"
          + "V\(y+edge)A\(edge) \(edge) 0 0 1 \(x+edge) \(y)Z"
      }
      let outer = roundedPath(x: 0, y: 0, width: width, height: height, radius: radius)
      let inner = roundedPath(x: top, y: top, width: max(0, width-2*top), height: max(0, height-2*top), radius: max(0, radius-top))
      shapes = "<path d='\(outer) \(inner)' fill-rule='evenodd' fill='\(color(colors[0]))'/>"
    } else if colors.allSatisfy({ $0 == colors[0] }) {
      let outer = "M0 0H\(width)V\(height)H0Z"
      let inner = "M\(left) \(top)H\(max(left, width-right))V\(max(top, height-bottom))H\(left)Z"
      shapes = "<path d='\(outer) \(inner)' fill-rule='evenodd' fill='\(color(colors[0]))'/>"
    } else {
      let background = (try? CSSColor.parse(style.string("backgroundColor", style.string("background", "transparent")),
                                            current: style.string("color", "black"))) ?? 0
      let integerEdges = [width, height] + widths
      let seams = background >> 24 == 255 && integerEdges.allSatisfy { $0.rounded() == $0 && $0 >= 0 && $0 <= 16384 }
      let rendering = seams ? " shape-rendering='crispEdges'" : ""
      let paths = [
        "M0 0H\(width)L\(width-right) \(top)H\(left)Z",
        "M\(width) 0V\(height)L\(width-right) \(height-bottom)V\(top)Z",
        "M0 \(height)H\(width)L\(width-right) \(height-bottom)H\(left)Z",
        "M0 0V\(height)L\(left) \(height-bottom)V\(top)Z",
      ]
      for index in sides.indices where widths[index] > 0 {
        shapes += "<path d='\(paths[index])' fill='\(color(colors[index]))'\(rendering)/>"
      }
      if seams { shapes += seamPixels(width: width, height: height, widths: widths, colors: colors, background: background) }
    }
    let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='\(width)' height='\(height)'>\(shapes)</svg>"
    try canvas.svg(Data(svg.utf8), width: width, height: height)
  }

  /// Chrome shares the coverage of integer border joins between adjacent side colors.
  /// Independent antialiased polygons would composite that coverage twice and darken joins.
  private static func seamPixels(width: Double, height: Double, widths: [Double], colors: [UInt32], background: UInt32) -> String {
    func composite(_ color: UInt32, shift: UInt32) -> Double {
      let alpha = Double(color >> 24)/255
      return (Double((color >> shift) & 255)*alpha + Double((background >> shift) & 255)*(1-alpha)).rounded()
    }
    func mixed(_ first: Int, _ second: Int) -> String {
      let channels = [UInt32(16), 8, 0].map {
        Int(((composite(colors[first], shift: $0)+composite(colors[second], shift: $0))/2).rounded())
      }
      return "rgb(\(channels[0]),\(channels[1]),\(channels[2]))"
    }
    var result = ""
    for (side, vertical, horizontal, first, second) in [
      (0, widths[0], widths[3], 0, 3), (1, widths[0], widths[1], 0, 1),
      (2, widths[2], widths[3], 2, 3), (3, widths[2], widths[1], 2, 1),
    ] where vertical > 0 && horizontal > 0 {
      for row in 0..<Int(vertical) {
        let progress = (Double(row)+0.5)/vertical
        let distance = horizontal*(side < 2 ? progress : 1-progress)
        let x = floor(side == 0 || side == 2 ? distance : width-distance)
        let y = side < 2 ? Double(row) : height-vertical+Double(row)
        result += "<rect x='\(x)' y='\(y)' width='1' height='1' fill='\(mixed(first, second))'/>"
      }
    }
    return result
  }

}
