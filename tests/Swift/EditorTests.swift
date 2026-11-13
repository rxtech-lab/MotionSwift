import CoreGraphics
import Foundation
import MotionCore
@testable import MotionEditor
import MotionSwiftUI
import Testing

private func target(_ style: [String: JSONValue], box: CGRect = CGRect(x: 48, y: 48, width: 220, height: 140))
  -> GestureTarget {
  GestureTarget(style: style, box: box, parent: CGRect(x: 0, y: 0, width: 640, height: 360))
}

@Suite struct GestureMappingTests {
  @Test func absoluteMoveEditsLeftAndTop() throws {
    let element = target(["position": .string("absolute"), "left": .number(48), "top": .number(48)])
    #expect(GestureMapper.keys(for: .move(dx: 0, dy: 0), target: element) == ["left", "top"])
    #expect(try GestureMapper.patch(for: .move(dx: 10.4, dy: -8), target: element)
      == ["left": .number(58), "top": .number(40)])
  }

  @Test func rightAndBottomAnchorsMoveInverted() throws {
    let element = target(["position": .string("absolute"), "right": .number(40), "bottom": .string("32px")])
    #expect(try GestureMapper.patch(for: .move(dx: 10, dy: 5), target: element)
      == ["right": .number(30), "bottom": .string("27px")])
  }

  @Test func missingOffsetsComeFromLayout() throws {
    let element = target(["position": .string("absolute")], box: CGRect(x: 100, y: 20, width: 10, height: 10))
    #expect(try GestureMapper.patch(for: .move(dx: 5, dy: 5), target: element) == ["left": .number(105), "top": .number(25)])
  }

  @Test func percentOffsetsAreRefused() {
    let element = target(["position": .string("absolute"), "left": .string("10%"), "top": .number(0)])
    #expect(throws: GestureRefusal.self) { try GestureMapper.patch(for: .move(dx: 1, dy: 1), target: element) }
  }

  @Test func flexMoveComposesTranslateAndKeepsOtherFunctions() throws {
    #expect(try GestureMapper.patch(for: .move(dx: 12, dy: -4), target: target([:]))
      == ["transform": .string("translate(12px, -4px)")])
    let rotated = target(["transform": .string("rotate(8deg) translateX(10px) translateY(2px) scale(1.5)")])
    #expect(try GestureMapper.patch(for: .move(dx: 5, dy: 5), target: rotated)
      == ["transform": .string("rotate(8deg) translate(15px, 7px) scale(1.5)")])
  }

  @Test func rotateEditsOnlyTheRotateFunction() throws {
    let element = target(["transform": .string("translate(4px, 4px) rotate(10deg)")])
    #expect(try GestureMapper.patch(for: .rotate(degrees: 35.04), target: element)
      == ["transform": .string("translate(4px, 4px) rotate(45deg)")])
    #expect(try GestureMapper.patch(for: .rotate(degrees: -15), target: target([:]))
      == ["transform": .string("rotate(-15deg)")])
  }

  @Test func resizeFromTopLeadingMovesAnchors() throws {
    let element = target(["position": .string("absolute"), "left": .number(48), "top": .number(48),
      "width": .number(220), "height": .number(140)])
    let gesture = CanvasGesture.resize(handle: .topLeading, dx: -20, dy: 10, keepsAspectRatio: false)
    #expect(Set(GestureMapper.keys(for: gesture, target: element)) == ["width", "height", "left", "top"])
    #expect(try GestureMapper.patch(for: gesture, target: element)
      == ["width": .number(240), "height": .number(130), "left": .number(28), "top": .number(58)])
  }

  @Test func resizeKeepsAspectRatio() throws {
    let element = target(["width": .number(220), "height": .number(140)])
    let patch = try GestureMapper.patch(
      for: .resize(handle: .bottomTrailing, dx: 110, dy: 0, keepsAspectRatio: true), target: element)
    #expect(patch == ["width": .number(330), "height": .number(210)])
  }

  @Test func snappingAlignsToCanvasCenterAndSiblings() {
    let box = CGRect(x: 100, y: 100, width: 100, height: 50)
    let result = Snapping.snap(
      box: box, translation: CGSize(width: 117, height: 0), siblings: [CGRect(x: 0, y: 147, width: 10, height: 10)],
      canvas: CGSize(width: 640, height: 360), threshold: 6)
    // The moved midX (267) is 3 px from the canvas center (320 - 50 = 270 after 120 px).
    #expect(result.translation.width == 120)
    #expect(result.guides.contains(SnapGuide(axis: .vertical, position: 320)))
    // maxY 150 is 2 px from the sibling's midY 152 (closer than its minY 147).
    #expect(result.translation.height == 2)
    #expect(result.guides.contains(SnapGuide(axis: .horizontal, position: 152)))
  }
}

/// Copies the sample project so write-back never touches the repository.
@MainActor
private func temporarySample() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("motionswift-editor-\(UUID().uuidString)")
  try FileManager.default.copyItem(at: sampleProject, to: directory)
  return directory
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
  for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
  #expect(condition())
}

@MainActor
@Test func editorSelectsDragsWritesBackAndUndoesByteExactly() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let file = project.appendingPathComponent("src/Cards.tsx")
  let original = try String(contentsOf: file, encoding: .utf8)
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  try await waitUntil { model.player.displayedFrame != nil }

  model.select(at: CGPoint(x: 60, y: 60))
  #expect(model.selection == "src/Cards.tsx:6:3")
  #expect(model.selectionFeedback == 1)
  try await waitUntil { model.styles != nil }
  #expect(model.styles?.property("left")?.kind == .static)

  #expect(model.beginGesture(.move(dx: 0, dy: 0)))
  model.updateGesture(.move(dx: 30, dy: 12), snapThreshold: 0)
  #expect(model.player.previewOverrides["src/Cards.tsx:6:3"] == ["left": .number(78), "top": .number(60)])
  try await waitUntil { model.player.displayedFrame?.overridden == true }
  await model.endGesture(named: "Move")
  let moved = try String(contentsOf: file, encoding: .utf8)
  #expect(moved.contains("left: 78, top: 60, width: 220"))
  #expect(model.commitFeedback == 1)
  #expect(model.canUndo)
  try await waitUntil { model.player.displayedFrame?.overridden == false && model.selectedBox?.x == 78 }

  await model.undo()
  #expect(try String(contentsOf: file, encoding: .utf8) == original)
  #expect(model.canRedo)
  await model.redo()
  #expect(try String(contentsOf: file, encoding: .utf8) == moved)

  model.clearSelection()
  #expect(model.selection == nil)
  #expect(model.selectedPath == nil)
  #expect(model.selectedRect == nil)
  #expect(model.styles == nil)
  let feedback = model.selectionFeedback
  model.clearSelection()
  #expect(model.selectionFeedback == feedback)
}

@MainActor
@Test func editorRefusesAnimatedPropertiesWithExplanation() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Pulse")
  try await waitUntil { model.player.displayedFrame != nil }
  // The small square's top is interpolated; at frame 0 it sits at (32, 32).
  model.select(at: CGPoint(x: 40, y: 40))
  try await waitUntil { model.styles != nil }
  #expect(model.styles?.property("top")?.kind == .animated)
  #expect(model.beginGesture(.move(dx: 0, dy: 0)) == false)
  #expect(model.refusalFeedback == 1)
  #expect(model.notice?.message.contains("top is animated") == true)
}

@MainActor
@Test func editorRefusesWritesWhenTheFileChangedOnDisk() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let file = project.appendingPathComponent("src/Cards.tsx")
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  try await waitUntil { model.player.displayedFrame != nil }
  model.select(at: CGPoint(x: 60, y: 60))
  try await waitUntil { model.styles != nil }
  let external = try String(contentsOf: file, encoding: .utf8) + "\n// edited elsewhere\n"
  try external.write(to: file, atomically: true, encoding: .utf8)
  await model.setStyle("borderRadius", .number(8))
  #expect(try String(contentsOf: file, encoding: .utf8) == external)
  #expect(model.notice?.kind == .conflict)
}

@MainActor
@Test func editorTimelinePersistsTimingAndKeyframesRendersAndUndoes() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let file = project.appendingPathComponent("src/Cards.tsx")
  let original = try String(contentsOf: file, encoding: .utf8)
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  try await waitUntil { model.player.displayedFrame != nil }
  let source = "src/Cards.tsx:6:3"
  let track = try #require(model.timelineTracks.first { $0.src == source })
  model.selectTrack(track)
  try await waitUntil { model.styles != nil }
  #expect(model.selection == source)
  #expect(model.timelineTracks.count == 4)

  await model.setTiming(of: source, start: 10, duration: 50)
  await model.setKeyframe(of: source, key: "left", frame: 10, value: 48)
  await model.setKeyframe(of: source, key: "left", frame: 30, value: 148)
  let saved = try String(contentsOf: file, encoding: .utf8)
  #expect(saved.contains("data-ms-timeline"))
  let hidden = try await model.player.render(frame: 9)
  #expect(!hidden.layout.contains { $0.source == source })
  let visible = try await model.player.render(frame: 20)
  #expect(visible.layout.first { $0.source == source }?.x == 98)
  let ended = try await model.player.render(frame: 60)
  #expect(!ended.layout.contains { $0.source == source })
  #expect(model.timelineTracks.contains { $0.src == source })

  await model.setTiming(of: source, start: 10, duration: 5)
  #expect(model.notice?.kind == .refusal)
  #expect(try String(contentsOf: file, encoding: .utf8) == saved)
  await model.setKeyframe(of: source, key: "left", frame: 30, value: 999)
  #expect(model.notice?.kind == .refusal)
  #expect(try String(contentsOf: file, encoding: .utf8) == saved)

  // Moving retains local keyframes, and shortening cannot silently discard them.
  await model.setTiming(of: source, start: 20, duration: 50)
  let moved = try await model.player.render(frame: 30)
  #expect(moved.layout.first { $0.source == source }?.x == 98)
  await model.undo()
  await model.undo()
  await model.undo()
  await model.undo()
  #expect(try String(contentsOf: file, encoding: .utf8) == original)
  await model.redo()
  #expect(model.selectedTrack?.start == 10)
}

@MainActor
@Test func editorTimelineCanAnimateWithoutExplicitDurationAndDeleteFinalKeyframe() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  try await waitUntil { model.player.displayedFrame != nil }
  let source = "src/Cards.tsx:6:3"
  await model.setKeyframe(of: source, key: "left", frame: 0, value: 120)
  #expect(model.objectTracks.first { $0.src == source }?.keyframes["left"]?.count == 1)
  let animated = try await model.player.render(frame: 10)
  #expect(animated.layout.first { $0.source == source }?.x == 120)
  await model.removeKeyframe(of: source, key: "left", frame: 0)
  let restored = try await model.player.render(frame: 10)
  #expect(restored.layout.first { $0.source == source }?.x == 48)
  await model.undo()
  let undone = try await model.player.render(frame: 10)
  #expect(undone.layout.first { $0.source == source }?.x == 120)
}

@MainActor
@Test func editorCapturesCurrentPoseAtPlayheadAndPreservesEarlierKeyframes() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let file = project.appendingPathComponent("src/Cards.tsx")
  let original = try String(contentsOf: file, encoding: .utf8)
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  try await waitUntil { model.player.displayedFrame != nil }
  model.select(at: CGPoint(x: 60, y: 60))
  try await waitUntil { model.styles != nil }
  let source = try #require(model.selection)

  await model.captureKeyframe()
  #expect(model.selectedTrack?.keyframes["left"] == [.init(frame: 0, value: 48)])
  #expect(model.selectedTrack?.keyframes["top"] == [.init(frame: 0, value: 48)])
  #expect(model.selectedTrack?.keyframes["width"] == [.init(frame: 0, value: 220)])
  let firstCapture = try String(contentsOf: file, encoding: .utf8)
  // Seek and capture without waiting for the coalesced display frame to catch up.
  model.scrub(to: 30)
  await model.setStyle("left", .number(148))
  #expect(try String(contentsOf: file, encoding: .utf8) == firstCapture)
  #expect(model.keyframeDraft["left"] == .number(148))
  await model.captureKeyframe()
  #expect(model.keyframeDraft.isEmpty)
  #expect(model.selectedTrack?.keyframes["left"] == [.init(frame: 0, value: 48), .init(frame: 30, value: 148)])
  let middle = try await model.player.render(frame: 15)
  #expect(middle.layout.first { $0.source == source }?.x == 98)

  // Capture the evaluated interpolation, rather than the original source literal (48).
  model.scrub(to: 15)
  await model.captureKeyframe()
  #expect(model.selectedTrack?.keyframes["left"]?.first { $0.frame == 15 }?.value == 98)
  await model.setStyle("left", .number(108))
  await model.captureKeyframe()
  #expect(model.selectedTrack?.keyframes["left"]?.count == 3)
  #expect(model.selectedTrack?.keyframes["left"]?.first { $0.frame == 15 }?.value == 108)
  await model.undo()
  #expect(model.selectedTrack?.keyframes["left"]?.first { $0.frame == 15 }?.value == 98)
  await model.undo()
  await model.undo()
  #expect(try String(contentsOf: file, encoding: .utf8) == firstCapture)
  await model.undo()
  #expect(try String(contentsOf: file, encoding: .utf8) == original)
}

@MainActor
@Test func editorCapturesCanvasAdjustmentsAndDiscardsUncapturedPosesOnScrub() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  try await waitUntil { model.player.displayedFrame != nil }
  model.select(at: CGPoint(x: 60, y: 60))
  try await waitUntil { model.styles != nil }
  await model.captureKeyframe()
  model.scrub(to: 20)
  try await waitUntil { model.player.displayedFrame?.frame == 20 }
  #expect(model.beginGesture(.move(dx: 0, dy: 0)))
  model.updateGesture(.move(dx: 50, dy: 12), snapThreshold: 0)
  await model.endGesture(named: "Move")
  #expect(model.keyframeDraft["left"] == .number(98))
  #expect(model.keyframeDraft["top"] == .number(60))
  await model.captureKeyframe()
  #expect(model.selectedTrack?.keyframes["left"]?.last?.value == 98)
  #expect(model.selectedTrack?.keyframes["top"]?.last?.value == 60)
  await model.setStyle("left", .number(999))
  model.scrub(to: 0)
  #expect(model.keyframeDraft.isEmpty)
  #expect(model.player.previewOverrides.isEmpty)
  let first = try await model.player.render(frame: 0)
  #expect(first.layout.first { $0.source == model.selection }?.x == 48)
}

@Test func cornerRotationTracksPointerFromEveryCornerWithoutSeamJumps() {
  for start in [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)] {
    var rotation = CornerRotationDrag(center: .zero, start: start)
    let quarterTurn = CGPoint(x: -start.y, y: start.x)
    #expect(abs(rotation.update(to: quarterTurn) - 90) < 0.001)
    #expect(abs(rotation.update(to: CGPoint(x: -start.x, y: -start.y)) - 180) < 0.001)
  }
  var seam = CornerRotationDrag(center: .zero, start: CGPoint(x: -100, y: 1))
  #expect(abs(seam.update(to: CGPoint(x: -100, y: -1))) < 2)
}

@MainActor
@Test func editorCornerRotationWritesTransformAndUndoes() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let file = project.appendingPathComponent("src/Cards.tsx")
  let original = try String(contentsOf: file, encoding: .utf8)
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  try await waitUntil { model.player.displayedFrame != nil }
  model.select(at: CGPoint(x: 60, y: 60))
  try await waitUntil { model.styles != nil }
  #expect(model.beginGesture(.rotate(degrees: 0)))
  model.updateGesture(.rotate(degrees: 45))
  await model.endGesture(named: "Rotate")
  #expect(try String(contentsOf: file, encoding: .utf8).contains("rotate(45deg)"))
  await model.undo()
  #expect(try String(contentsOf: file, encoding: .utf8) == original)
}

@MainActor
@Test func editorDetectsSpreadStylesAtCurrentFrameAndAgentGroups() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let file = project.appendingPathComponent("src/Cards.tsx")
  let source = try String(contentsOf: file, encoding: .utf8)
  let updated = source.replacingOccurrences(
    of: "left: 48, top: 48, width: 220",
    with: "left: 48, top: 48, ...{width: 220, color: '#fca311', fontSize: 24}")
    .replacingOccurrences(of: "<div style=", with: "<div data-ms-properties={{color: {label: 'Brand color', group: 'Brand'}}} style=")
  #expect(updated != source)
  try updated.write(to: file, atomically: true, encoding: .utf8)
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  try await waitUntil { model.player.displayedFrame != nil }
  model.select(at: CGPoint(x: 60, y: 60))
  try await waitUntil { model.styles != nil }
  #expect(model.detectedStyleProperties.first { $0.key == "width" }?.kind == .computed)
  #expect(model.detectedStyleProperties.first { $0.key == "fontSize" }?.value == .number(24))
  #expect(model.currentStyleValue("color") == .string("#fca311"))
  #expect(model.styles?.label(for: "color") == "Brand color")
  #expect(model.styles?.group(for: "color") == "Brand")
  await model.setStyle("width", .number(300))
  #expect(model.notice?.kind == .refusal)
  #expect(try String(contentsOf: file, encoding: .utf8) == updated)
}

@MainActor
@Test func editorTextSavesReloadsUndoesAndProtectsExternalChanges() async throws {
  let project = try temporarySample()
  defer { try? FileManager.default.removeItem(at: project) }
  let file = project.appendingPathComponent("src/Cards.tsx")
  let original = """
    import React from 'react';
    import {AbsoluteFill} from 'remotion';
    export const Cards = () => <AbsoluteFill>
      <div style={{position: 'absolute', left: 48, top: 48, fontSize: 24}}>原始文字</div>
    </AbsoluteFill>;
    """
  try original.write(to: file, atomically: true, encoding: .utf8)
  let model = EditorModel(project: project, entry: "src/index.ts", configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  try await waitUntil { model.player.displayedFrame != nil }
  let target = try #require(await model.textEditTarget(at: CGPoint(x: 55, y: 55)))
  #expect(target.text == "原始文字")
  #expect(target.fontSize == 24)
  #expect(target.expectedSource == original)
  #expect(target.rect == model.selectedRect)
  #expect(!model.player.isPlaying)
  #expect(try String(contentsOf: file, encoding: .utf8) == original)
  let selection = target.source
  #expect(model.textContent?.editable == true)
  #expect(model.textContent?.value == "原始文字")
  #expect(await model.setText(target.text, source: selection, expectedSource: original))
  #expect(!model.canUndo)
  #expect(model.commitFeedback == 0)
  #expect(try String(contentsOf: file, encoding: .utf8) == original)
  let replacement = "新的文字 <&> {hello} 😀"
  // Clicking away may change selection before the native editor resigns focus.
  model.clearSelection()
  #expect(await model.setText(replacement, source: selection, expectedSource: original, requiresSelection: false))
  model.select(at: CGPoint(x: 55, y: 55))
  try await waitUntil { model.textContent != nil }
  #expect(model.textContent?.value == replacement)
  #expect(model.canUndo)
  let saved = try String(contentsOf: file, encoding: .utf8)
  #expect(saved.contains(replacement))
  await model.undo()
  #expect(try String(contentsOf: file, encoding: .utf8) == original)
  #expect(model.textContent?.value == "原始文字")
  await model.redo()
  #expect(try String(contentsOf: file, encoding: .utf8) == saved)
  #expect(model.textContent?.value == replacement)
  // A stale sheet must not overwrite an edit performed since the sheet opened.
  #expect(await model.setText("stale", source: selection, expectedSource: original) == false)
  #expect(model.notice?.kind == .conflict)
  // Changes on disk are protected even if the in-memory draft is still current.
  let external = saved + "\n// external edit\n"
  try external.write(to: file, atomically: true, encoding: .utf8)
  #expect(await model.setText("overwrite", source: selection, expectedSource: saved) == false)
  #expect(model.notice?.kind == .conflict)
  #expect(try String(contentsOf: file, encoding: .utf8) == external)
}
