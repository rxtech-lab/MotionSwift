import Foundation
import MotionCore
import MotionLayout
import MotionRender
import Testing

private func box(_ style: [String: JSONValue], _ children: [RenderNode] = []) -> RenderNode {
  RenderNode(type: "div", style: style, children: children)
}

@Test func boxBordersReserveSpaceAndHonorSizing() throws {
  let child = box(["width": .number(40), "height": .number(20), "border": .string("4px solid red"), "boxSizing": .string("content-box")])
  let borderBox = box(["width": .number(40), "height": .number(20), "border": .string("4px solid red"),
                       "boxSizing": .string("border-box")])
  let root = box(["flexDirection": .string("row"), "alignItems": .string("flex-start")], [child, borderBox])
  let layout = try LayoutEngine.calculate(root, width: 200, height: 100)
  #expect(layout.children[0].width == 48)
  #expect(layout.children[0].height == 28)
  #expect(layout.children[1].width == 40)
  #expect(layout.children[1].x == 48)
}

@Test func boxFlexShorthandMatchesBrowserReference() throws {
  let root = box(["flexDirection": .string("row"), "gap": .number(10)], [
    box(["flex": .number(1)]), box(["flex": .string("2 1 0%")]),
    box(["flex": .string("none"), "width": .number(40)]),
  ])
  let layout = try LayoutEngine.calculate(root, width: 240, height: 50)
  #expect(layout.children.map(\.width) == [60, 120, 40])
  #expect(layout.children.map(\.x) == [0, 70, 200])
}

@Test func boxPaintOrderIsStableAndPreservesSourcePaths() throws {
  let composition = try JSONDecoder().decode(Composition.self, from: Data(
    #"{"id":"Order","width":16,"height":16,"fps":30,"durationInFrames":1}"#.utf8))
  let renderer = try Renderer(width: 16, height: 16)
  func layer(_ color: String, _ zIndex: Double) -> RenderNode {
    box(["position": .string("absolute"), "inset": .number(0), "backgroundColor": .string(color), "zIndex": .number(zIndex)])
  }
  let boxes = try renderer.draw(box([:], [layer("red", 2), layer("blue", 1), layer("lime", 2)]), composition: composition)
  #expect(boxes.map(\.id) == ["0", "0.1", "0.0", "0.2"])
  #expect(Array(try renderer.pixels().prefix(4)) == [0, 255, 0, 255])
}

@Test func boxDiagnosticsRejectUnsupportedContracts() throws {
  for style: [String: JSONValue] in [
    ["border": .string("3px dashed red")], ["flex": .string("invalid")],
    ["transformOrigin": .string("left top 20px")], ["zIndex": .number(1.5)],
    ["pointerEvents": .string("painted")],
  ] {
    let composition = try JSONDecoder().decode(Composition.self, from: Data(
      #"{"id":"Bad","width":16,"height":16,"fps":30,"durationInFrames":1}"#.utf8))
    #expect(throws: MotionError.self) { try Renderer(width: 16, height: 16).draw(box(style), composition: composition) }
  }
}

@Test func boxDescendantZIndexEscapesAutoButRespectsExplicitContexts() throws {
  let composition = try JSONDecoder().decode(Composition.self, from: Data(
    #"{"id":"Nested","width":16,"height":16,"fps":30,"durationInFrames":1}"#.utf8))
  let high = box(["position": .string("absolute"), "inset": .number(0), "zIndex": .number(10),
                  "backgroundColor": .string("red")])
  let middle = box(["position": .string("absolute"), "inset": .number(0), "zIndex": .number(2),
                    "backgroundColor": .string("blue")])
  let renderer = try Renderer(width: 16, height: 16)
  _ = try renderer.draw(box([:], [box(["position": .string("absolute"), "inset": .number(0)], [high]), middle]),
                        composition: composition)
  #expect(Array(try renderer.pixels().prefix(4)) == [255, 0, 0, 255])
  _ = try renderer.draw(box([:], [box(["position": .string("absolute"), "inset": .number(0), "zIndex": .number(1)], [high]), middle]),
                        composition: composition)
  #expect(Array(try renderer.pixels().prefix(4)) == [0, 0, 255, 255])
}

@Test func boxColorSyntaxAndCurrentColorAreDeterministic() throws {
  #expect(try CSSColor.parse(" RebeccaPurple ") == 0xFF663399)
  #expect(try CSSColor.parse("rgb(100% 0% 0% / 50%)") == 0x80FF0000)
  #expect(try CSSColor.parse("hsl(120deg 100% 50% / 25%)") == 0x4000FF00)
  #expect(try CSSColor.parse("#1234") == 0x44112233)
  #expect(try CSSColor.parse("currentColor", current: "orange") == 0xFFFFA500)
  #expect(try CSSColor.parse("currentColor", current: "currentcolor") == 0xFF000000)
  #expect(throws: MotionError.self) { try CSSColor.parse("color(display-p3 1 0 0)") }
  #expect(throws: MotionError.self) { try CSSColor.parse("hsl(120 50 50)") }
}

@Test func boxPositionedAutoPaintsAboveStaticFlow() throws {
  let composition = try JSONDecoder().decode(Composition.self, from: Data(
    #"{"id":"Auto","width":16,"height":16,"fps":30,"durationInFrames":1}"#.utf8))
  let renderer = try Renderer(width: 16, height: 16)
  _ = try renderer.draw(box(["display": .string("flex")], [
    box(["position": .string("absolute"), "inset": .number(0), "backgroundColor": .string("red")]),
    box(["width": .number(16), "height": .number(16), "backgroundColor": .string("blue")]),
  ]), composition: composition)
  #expect(Array(try renderer.pixels().prefix(4)) == [255, 0, 0, 255])
}

@Test func boxInlineFlexItemsAreBlockifiedAndFlowOutsideFlexIsRejected() throws {
  let root = box(["display": .string("flex")], [
    box(["display": .string("inline"), "width": .number(40), "height": .number(20)]),
    box(["display": .string("inline-block"), "width": .number(60), "height": .number(20)]),
  ])
  let layout = try LayoutEngine.calculate(root, width: 200, height: 50)
  #expect(layout.children.map(\.width) == [40, 60])
  #expect(layout.children.map(\.x) == [0, 40])
  #expect(throws: MotionError.self) {
    try LayoutEngine.calculate(box([:], [box(["display": .string("inline-block")])]), width: 200, height: 50)
  }
}

@Test func boxBorderJoinsShareCoverageInsteadOfDarkening() throws {
  let composition = try JSONDecoder().decode(Composition.self, from: Data(
    #"{"id":"Joins","width":100,"height":80,"fps":30,"durationInFrames":1}"#.utf8))
  let renderer = try Renderer(width: 100, height: 80)
  _ = try renderer.draw(box(["backgroundColor": .string("rebeccapurple"),
    "border": .string("4px solid rgba(255, 255, 255, 0.5)"),
    "borderTop": .string("8px solid red"), "borderLeftColor": .string("lime")]), composition: composition)
  let pixels = try renderer.pixels()
  let topRight = (0*100+99)*4
  let bottomLeft = (76*100+3)*4
  // Reference channel values sampled from Chrome's CSS border joins.
  #expect(Array(pixels[topRight..<topRight+4]) == [217, 77, 102, 255])
  #expect(Array(pixels[bottomLeft..<bottomLeft+4]) == [90, 204, 102, 255])
}

@Test func blockFlowSpacingShorthandsAutoMarginsAndIntrinsicPillsMatchHTML() throws {
  let block = box(["padding": .string("10px 20px 30px 40px")], [
    box(["height": .number(24)]),
    box(["height": .number(16), "margin": .string("6px 0")]),
  ])
  let blockLayout = try LayoutEngine.calculate(block, width: 300, height: 200)
  #expect(blockLayout.children[0].x == 40)
  #expect(blockLayout.children[0].y == 10)
  #expect(blockLayout.children[0].width == 240)
  #expect(blockLayout.children[1].y == 40)

  let row = box(["display": .string("flex"), "padding": .string("0 24px"), "alignItems": .string("center")], [
    box(["width": .number(40), "height": .number(20)]),
    box(["width": .number(50), "height": .number(20), "marginLeft": .string("auto")]),
  ])
  let rowLayout = try LayoutEngine.calculate(row, width: 300, height: 60)
  #expect(rowLayout.children[0].x == 24)
  #expect(rowLayout.children[1].x == 226)

  func pill(_ label: String, padded: Bool) -> RenderNode {
    var style: [String: JSONValue] = [
      "fontSize": .number(48), "fontWeight": .number(800), "letterSpacing": .string("0.02em"),
    ]
    if padded { style["padding"] = .string("8px 20px") }
    return RenderNode(type: "div", style: style, children: [RenderNode(type: "#text", style: [:], text: label)])
  }
  let pills = box(["display": .string("flex"), "alignItems": .string("flex-start")], [
    pill("Performance", padded: false),
    pill("Performance", padded: true),
    pill("10X", padded: true),
  ])
  let pillLayout = try LayoutEngine.calculate(pills, width: 1200, height: 400)
  #expect(abs(pillLayout.children[1].height - (pillLayout.children[0].height + 16)) < 1)
  #expect(abs(pillLayout.children[2].height - pillLayout.children[1].height) < 1)
}
