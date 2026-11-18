import Foundation
import MotionCore
@testable import MotionEditor
import MotionSwiftUI
import Testing

private let bg5Fixtures = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures/bg5")

@MainActor
@Suite struct BG5EditingTests {
  @Test(arguments: [
    ("english", "Until you hit.", "The render is ready."),
    ("chinese", "直到你按下渲染。", "渲染已完成。"),
  ])
  func editsTimelineTitleAndRendersTheSavedChange(variant: String, originalText: String, editedText: String) async throws {
    let project = FileManager.default.temporaryDirectory.appendingPathComponent("motionswift-bg5-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: bg5Fixtures.appendingPathComponent(variant), to: project)
    defer { try? FileManager.default.removeItem(at: project) }
    let file = project.appendingPathComponent("src/Composition.tsx")
    let original = try String(contentsOf: file, encoding: .utf8)

    let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 0.25))
    await model.open(compositionID: "Main")
    #expect(model.status == .idle)
    let track = try #require(model.timelineTracks.first { $0.label == "Title" && $0.preview == originalText })

    // The title is gated by the current frame in the actual composition.
    try await waitForFrame(model, number: 0)
    #expect(!containsText(originalText, in: model.player.displayedFrame?.tree))
    model.scrub(to: 60)
    try await waitForFrame(model, number: 60, text: originalText)

    model.selectTrack(track)
    for _ in 0..<500 {
      if model.textContent != nil { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(model.selection == track.src)
    try #require(model.canEditText)
    #expect(model.selectedTextValue == originalText)
    try #require(await model.setText(editedText, source: track.src, expectedSource: original))
    let saved = try String(contentsOf: file, encoding: .utf8)
    // The title literal is the only source change. The 3D passes and title timing stay intact.
    let oldChildren = variant == "english" ? "{\"\(originalText)\"}" : originalText
    #expect(saved == original.replacingOccurrences(of: ">\(oldChildren)</Title>", with: ">{\"\(editedText)\"}</Title>"))
    try await waitForFrame(model, number: 60, text: editedText)
    #expect(!containsText(originalText, in: model.player.displayedFrame?.tree))

    await model.undo()
    #expect(try String(contentsOf: file, encoding: .utf8) == original)
    try await waitForFrame(model, number: 60, text: originalText)

    await model.redo()
    #expect(try String(contentsOf: file, encoding: .utf8) == saved)
    try await waitForFrame(model, number: 60, text: editedText)
  }

  private func waitForFrame(_ model: EditorModel, number: Int, text: String? = nil) async throws {
    for _ in 0..<500 {
      if let frame = model.player.displayedFrame, frame.frame == number,
         text.map({ containsText($0, in: frame.tree) }) ?? true { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Expected BG 5 frame \(number) with text \(text ?? "(any)")")
    throw CancellationError()
  }

  private func containsText(_ text: String, in node: RenderNode?) -> Bool {
    guard let node else { return false }
    return node.text == text || node.children.contains { containsText(text, in: $0) }
  }
}
