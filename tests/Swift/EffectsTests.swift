import Foundation
@testable import MotionCore
@testable import MotionRender
import SkiaKit
import Testing

@Test func cssEffectsRejectUnsupportedValues() throws {
  for value in ["conic-gradient(red, blue)", "linear-gradient(red 80%, blue 10%)", "linear-gradient(red 2px, blue)"] {
    #expect(throws: (any Error).self) { try Effects.gradient(value, width: 40, height: 20) }
  }
  for value in ["blur(-1px)", "url(#filter)", "brightness(1) trailing", "drop-shadow(1px 2px -1px red)",
                "drop-shadow(1px 2px red, 2px 3px blue)", "drop-shadow(1px 2px 3px 0px red)"] {
    #expect(throws: (any Error).self) { try Effects.filters(value) }
  }
  #expect(throws: (any Error).self) { try Effects.clip("inset(1px round 2px)", width: 40, height: 20) }
  #expect(throws: (any Error).self) { try CSSTransform.matrix("rotateX(20deg) garbage", width: 40, height: 20) }
  #expect(throws: (any Error).self) { try Style(["textShadow": .string("1px 2px red")]) }
}

@Test func cssEffectsParseGradientsAndPerspective() throws {
  let gradient = try Effects.gradient("linear-gradient(90deg, #ff0000, #00ff00, #0000ff)", width: 40, height: 20)
  #expect(gradient.stops == [0, 0.5, 1])
  #expect(abs(gradient.geometry[0]) < 0.0001)
  let diagonal = try Effects.gradient("linear-gradient(to bottom right, rgba(255, 0, 0, 0.8) 0%, transparent 100%)",
                                      width: 100, height: 100)
  #expect(diagonal.colors.count == 2)
  for radial in [
    "radial-gradient(circle, rgba(255, 255, 255, 0.9) 0%, transparent 70%)",
    "radial-gradient(circle at 30% 30%, #ff8844, #223344)",
    "radial-gradient(ellipse at center, rgba(80, 160, 255, 0.5) 0%, transparent 70%)",
    "radial-gradient(120% 90% at 22% 88%, #44aaee 0%, transparent 55%)",
  ] {
    let parsed = try Effects.gradient(radial, width: 200, height: 100)
    #expect(parsed.radial)
    #expect(parsed.geometry.count == 4 && parsed.geometry[2] > 0 && parsed.geometry[3] > 0)
  }
  let matrix = try CSSTransform.matrix("perspective(100px) rotateY(60deg)", width: 40, height: 20)
  #expect(abs(matrix[0] - 0.5) < 0.0001)
  #expect(matrix[6] > 0)
  #expect(try Effects.shadows("2px 3px 4px 1px #00000080, inset 0px 1px #ffffff").count == 2)
  #expect(try Effects.shadows("0 12px 32px rgba(0, 0, 0, 0.35)").count == 1)
  #expect(try Effects.filters("drop-shadow(0px 4px 12px rgba(0, 0, 0, 0.45))").count == 1)
}

@Test func multiCornerRadiusAndWebkitBackdropRenderOnBothBackends() throws {
  let composition = Composition(id: "Corners", width: 40, height: 40, fps: 30, durationInFrames: 1)
  for backend in Backend.allCases {
    let renderer = try Renderer(width: 40, height: 40, backend: backend)
    let node = RenderNode(type: "div", style: ["backgroundColor": .string("#ffffff")], children: [
      RenderNode(type: "div", style: [
        "position": .string("absolute"), "left": .number(4), "top": .number(4),
        "width": .number(32), "height": .number(32),
        "borderRadius": .string("12px 12px 0 0"),
        "background": .string("linear-gradient(180deg, #ff0000 0%, #ff0000 100%)"),
      ]),
      RenderNode(type: "div", style: [
        "position": .string("absolute"), "left": .number(0), "top": .number(20),
        "width": .number(40), "height": .number(20),
        "WebkitBackdropFilter": .string("blur(2px)"),
        "opacity": .number(0.5),
      ]),
      RenderNode(type: "div", style: [
        "position": .string("absolute"), "left": .number(0), "top": .number(0),
        "width": .number(40), "height": .number(20),
        "backdropFilter": .string("blur(8px)"),
        "opacity": .number(0),
      ]),
    ])
    try renderer.draw(node, composition: composition)
    let pixels = [UInt8](try renderer.pixels())
    // Top-left corner (4, 4) is clipped outside the 12px top-left radius; bottom-left (4, 35) is square red.
    #expect(pixels[(4 * 40 + 4) * 4 + 1] == 255)
    #expect(pixels[(35 * 40 + 5) * 4] == 255)
  }
}

@Test func effectsCompositeSubtreesOnBothBackends() throws {
  let composition = Composition(id: "Effects", width: 48, height: 32, fps: 30, durationInFrames: 1)
  for backend in Backend.allCases {
    let renderer = try Renderer(width: 48, height: 32, backend: backend)
    let node = RenderNode(type: "div", style: ["backgroundColor": .string("#ffffff")], children: [
      RenderNode(type: "div", style: ["position": .string("absolute"), "width": .number(32), "height": .number(32),
        "backgroundColor": .string("#ff0000"), "filter": .string("invert(1)"),
        "clipPath": .string("inset(0px 16px 0px 0px)"), "opacity": .number(0.5)])])
    try renderer.draw(node, composition: composition)
    let pixels = [UInt8](try renderer.pixels())
    #expect(pixels[(8 * 48 + 8) * 4] == 128)
    #expect(pixels[(8 * 48 + 8) * 4 + 1] == 255)
    #expect(pixels[(8 * 48 + 24) * 4] == 255)
  }
}

@Test func curvedAndPolygonClipsRenderOnBothBackends() throws {
  for backend in Backend.allCases {
    for geometry in ["circle(40px at 60px 60px)", "ellipse(50px 40px at 60px 60px)",
                     "polygon(60px 4px, 116px 60px, 60px 116px, 4px 60px)"] {
      let canvas = try Canvas(width: 120, height: 120, backend: backend)
      canvas.saveState()
      try canvas.clip(path: #require(try Effects.clip(geometry, width: 120, height: 120)))
      canvas.save()
      canvas.rectangle(width: 120, height: 120, radius: 0, color: 0xffff0000)
      canvas.restore()
      canvas.restore()
      let pixels = [UInt8](try canvas.rgba())
      #expect(Array(pixels[(60 * 120 + 60) * 4..<(60 * 120 + 60) * 4 + 4]) == [255, 0, 0, 255])
      #expect(pixels[3] == 0)
    }
  }
}

@Test func svgHostAndExternalImageRenderOnBothBackends() throws {
  let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\"><rect width=\"16\" height=\"16\" fill=\"#ff0000\"/></svg>"
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".svg")
  try Data(svg.utf8).write(to: file)
  defer { try? FileManager.default.removeItem(at: file) }
  let composition = Composition(id: "SVG", width: 16, height: 16, fps: 30, durationInFrames: 1)
  for backend in Backend.allCases {
    for node in [RenderNode(type: "ms-svg", style: [:], src: svg),
                 RenderNode(type: "img", style: ["objectFit": .string("contain")], src: file.path)] {
      let renderer = try Renderer(width: 16, height: 16, backend: backend)
      try renderer.draw(node, composition: composition)
      #expect(Array(try renderer.pixels().prefix(4)) == [255, 0, 0, 255])
    }
  }
}

@Test func maskAndBlendPreserveThePaintedBackdrop() throws {
  let composition = Composition(id: "Composite", width: 32, height: 16, fps: 30, durationInFrames: 1)
  for backend in Backend.allCases {
    let renderer = try Renderer(width: 32, height: 16, backend: backend)
    let node = RenderNode(type: "div", style: ["backgroundColor": .string("#808080")], children: [
      RenderNode(type: "div", style: ["position": .string("absolute"), "width": .number(16), "height": .number(16),
        "backgroundColor": .string("#ff0000"), "mixBlendMode": .string("multiply")]),
      RenderNode(type: "div", style: ["position": .string("absolute"), "left": .number(16),
        "width": .number(16), "height": .number(16), "backgroundColor": .string("#ff0000"),
        "maskImage": .string("linear-gradient(90deg, #00000000 0%, #000000ff 100%)")])])
    try renderer.draw(node, composition: composition)
    let pixels = [UInt8](try renderer.pixels())
    #expect(Array(pixels[(8 * 32 + 8) * 4..<(8 * 32 + 8) * 4 + 4]) == [128, 0, 0, 255])
    #expect(pixels[(8 * 32 + 17) * 4 + 1] > pixels[(8 * 32 + 30) * 4 + 1])
    #expect(pixels[(8 * 32 + 17) * 4 + 3] == 255)
  }
}

@Test func backdropBlurSamplesPreviouslyPaintedStripes() throws {
  let composition = Composition(id: "Backdrop", width: 32, height: 16, fps: 30, durationInFrames: 1)
  for backend in Backend.allCases {
    let renderer = try Renderer(width: 32, height: 16, backend: backend)
    let stripes = (0..<8).map { index in
      RenderNode(type: "div", style: ["position": .string("absolute"), "left": .number(Double(index * 4)),
        "width": .number(2), "height": .number(16), "backgroundColor": .string("#000000")])
    }
    let glass = RenderNode(type: "div", style: ["position": .string("absolute"), "left": .number(8),
      "width": .number(16), "height": .number(16), "backdropFilter": .string("blur(2px)")])
    try renderer.draw(RenderNode(type: "div", style: ["backgroundColor": .string("#ffffff")],
                                 children: stripes + [glass]), composition: composition)
    let pixels = [UInt8](try renderer.pixels())
    #expect(pixels[(8 * 32 + 1) * 4] == 0)
    #expect(pixels[(8 * 32 + 17) * 4] > 50)
    #expect(pixels[(8 * 32 + 17) * 4] < 200)
  }
}

@Test func retainedRendererRestoresLegacySVGAfterEffectsFrame() throws {
  let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">
      <defs><linearGradient id="g"><stop stop-color="#ff7744"/>
        <stop offset="1" stop-color="#4488ff"/></linearGradient></defs>
      <rect width="24" height="24" rx="5" fill="url(#g)"/>
    </svg>
    """
  let legacy = RenderNode(type: "img", style: ["objectFit": .string("contain")],
                          src: "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString())
  let effect = RenderNode(type: "div", style: ["backgroundColor": .string("#ffffff"), "filter": .string("invert(1)")])
  let composition = Composition(id: "Switch", width: 24, height: 24, fps: 30, durationInFrames: 3)
  for backend in Backend.allCases {
    let renderer = try Renderer(width: 24, height: 24, backend: backend)
    try renderer.draw(legacy, composition: composition)
    let expected = try renderer.pixels()
    try renderer.draw(effect, composition: composition)
    #expect(try renderer.pixels() != expected)
    try renderer.draw(legacy, composition: composition)
    #expect(try renderer.pixels() == expected)
  }
}
