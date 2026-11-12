import Foundation
import MotionCore
import MotionRender
import MotionRuntime
import Testing

@Test func rejectsInvalidComposition() throws {
  let data = Data(##"{"id":"bad","width":0,"height":100,"fps":30,"durationInFrames":2}"##.utf8)
  let composition = try JSONDecoder().decode(Composition.self, from: data)
  #expect(throws: MotionError.self) { try composition.validate() }
}

@Test func rendersSkiaPNGAndRejectsUnknownStyles() throws {
  let composition = try JSONDecoder().decode(
    Composition.self,
    from: Data(
      ##"{"id":"boxes","width":16,"height":16,"fps":30,"durationInFrames":2}"##.utf8))
  let tree = try JSONDecoder().decode(
    RenderNode.self,
    from: Data(
      ##"{"type":"div","style":{"backgroundColor":"#ff0000"},"children":[]}"##.utf8))
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(
    "\(UUID().uuidString).png")
  defer { try? FileManager.default.removeItem(at: file) }
  let boxes = try Renderer(width: 16, height: 16).render(tree, composition: composition, to: file)
  #expect(boxes.count == 1)
  #expect(try Data(contentsOf: file).prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]))
  let unsupported = try JSONDecoder().decode(
    RenderNode.self,
    from: Data(
      ##"{"type":"div","style":{"filter":"blur(2px)"},"children":[]}"##.utf8))
  #expect(throws: MotionError.self) {
    _ = try Renderer(width: 16, height: 16).render(unsupported, composition: composition, to: file)
  }
}

@Test func rendererClearsPreviousFrameAndChecksDimensions() throws {
  let composition = try JSONDecoder().decode(
    Composition.self,
    from: Data(
      ##"{"id":"boxes","width":16,"height":16,"fps":30,"durationInFrames":2}"##.utf8))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let actual = directory.appendingPathComponent("actual.png")
  let expected = directory.appendingPathComponent("expected.png")
  let renderer = try Renderer(width: 16, height: 16)
  _ = try renderer.render(
    RenderNode(type: "div", style: ["backgroundColor": .string("#ff0000")]),
    composition: composition, to: actual)
  _ = try renderer.render(RenderNode(type: "div", style: [:]), composition: composition, to: actual)
  _ = try Renderer(width: 16, height: 16).render(
    RenderNode(type: "div", style: [:]), composition: composition, to: expected)
  #expect(try Data(contentsOf: actual) == Data(contentsOf: expected))
  #expect(throws: MotionError.self) {
    _ = try Renderer(width: 32, height: 32).render(
      RenderNode(type: "div", style: [:]), composition: composition, to: actual)
  }
}
