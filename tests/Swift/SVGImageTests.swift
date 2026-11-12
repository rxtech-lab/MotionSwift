import Foundation
import MotionCompiler
import MotionCore
import MotionRender
import MotionRuntime
import SkiaKit
import Testing

@Test func svgDataURICompilesRendersAndFitsOnBothBackends() throws {
  let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let project = repository.appendingPathComponent("tests/compiler-fixtures/svg-image")
  let runtime = try Runtime(bundle: Compiler(repository: repository).compile(
    project: project, entry: "input.tsx"))
  let composition = try #require(runtime.compositions().first)
  for backend in Backend.allCases {
    let renderer = try Renderer(width: 32, height: 32, backend: backend)
    for frame in [1, 0, 1] {
      let node = try runtime.frame(composition: composition, number: frame)
      #expect(node.children[0].children[0].src?.hasPrefix("data:image/svg+xml") == true)
      try renderer.draw(node, composition: composition)
      let pixels = try renderer.pixels()
      // A 2:1 SVG fits centrally into a square without stretching.
      #expect(Array(pixels[0..<4]) == [0, 0, 0, 0])
      let center = (16 * 32 + 16) * 4
      #expect(Array(pixels[center..<center + 4]) == (frame == 0 ? [255, 0, 0, 255] : [0, 0, 255, 255]))
      #expect(Array(pixels.suffix(4)) == [0, 0, 0, 0])
    }
    for src in ["https://example.com/a.svg", "data:image/png;base64,AAAA", "data:image/svg+xml,%ZZ"] {
      #expect(throws: MotionError.self) {
        try renderer.draw(RenderNode(type: "img", style: ["objectFit": .string("contain")], src: src),
          composition: composition)
      }
    }
  }
}

@Test func svgLetterSpacingChangesRenderedGlyphPositions() throws {
  let canvas = try Canvas(width: 200, height: 64)
  func extent(spacing: Int) throws -> Int {
    canvas.clear()
    let svg = """
      <svg xmlns="http://www.w3.org/2000/svg" width="200" height="64">
      <text x="0" y="40" font-family="Arial" font-size="32" letter-spacing="\(spacing)">AAA</text></svg>
      """
    try canvas.svg(Data(svg.utf8), width: 200, height: 64)
    let pixels = try canvas.rgba()
    return (0..<200).last { x in (0..<64).contains { y in pixels[(y * 200 + x) * 4 + 3] > 0 } } ?? 0
  }
  #expect(try extent(spacing: 8) - extent(spacing: 0) >= 15)
}
