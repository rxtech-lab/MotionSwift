import Foundation
import MotionCore
import MotionPortable
import MotionRender
import MotionSwiftUI

extension EditorModel {
  // MARK: Timeline & Keyframes

  /// The canvas and timeline share source selection, playhead, writes, notices and undo history.
  public var selectedTrack: ObjectTrack? { objectTracks.first { $0.src == selection } }

  public var timelineTracks: [ObjectTrack] {
    objectTracks.filter { track in
      timelineSources.contains(trackGroup(track)) || track.owner == player.composition?.id
    }
  }

  /// Remember source files as they appear; timed-out objects remain on the timeline.
  public func observeTimelineFrame() {
    guard let frame = player.displayedFrame, !objectTracks.isEmpty else { return }
    var bySource: [String: String] = [:]
    for track in objectTracks {
      let group = trackGroup(track)
      if !timelineSources.contains(group) { bySource[track.src] = group }
    }
    guard !bySource.isEmpty else { return }
    var discovered: Set<String> = []
    for element in frame.tree.threeEditorElements {
      if let group = bySource[element.source] { discovered.insert(group) }
    }
    for element in frame.tree.editorElements {
      if let group = bySource[element.source] { discovered.insert(group) }
    }
    for box in frame.layout {
      if let source = box.source, let group = bySource[source] { discovered.insert(group) }
    }
    if !discovered.isEmpty { timelineSources.formUnion(discovered) }
  }

  private func trackGroup(_ track: ObjectTrack) -> String {
    "\(SourceStamp(track.src)?.file ?? "")#\(track.owner ?? "")"
  }

  public func resetTimelineSelection() {
    clearSelection()
    timelineSources = []
  }

  func refreshTimeline() async {
    let snapshot = files
    do {
      objectTracks = try await service.perform { compiler in
        try snapshot.keys.sorted().filter { ["tsx", "jsx"].contains(URL(fileURLWithPath: $0).pathExtension) }
          .flatMap { try compiler.timeline(source: snapshot[$0]!, file: $0) }
      }
      observeTimelineFrame()
    } catch { show(.failure, "Cannot read timeline: \(error)") }
    await refreshCameraRigs()
  }

  public func selectTrack(_ track: ObjectTrack) {
    guard !isGesturing else { return }
    player.pause()
    if selection != track.src { discardKeyframeDraft() }
    selection = track.src
    selectedPath = player.displayedFrame?.layout.first { $0.source == track.src }?.id
    styles = nil
    textContent = nil
    selectionFeedback += 1
    Task { await refreshStyles() }
  }

  public func scrub(to frame: Int) {
    discardKeyframeDraft()
    player.pause()
    player.seek(to: frame)
  }

  public func setTiming(of source: String, start: Int, duration: Int) async {
    guard let track = objectTracks.first(where: { $0.src == source }), let composition = player.composition else { return }
    if let reason = track.reason { refuse(reason); return }
    let limit = min(track.limit ?? composition.durationInFrames, composition.durationInFrames)
    guard start >= track.offset, duration > 0, start <= limit - duration else {
      refuse("Keep the object inside its composition or enclosing Sequence"); return
    }
    var timing = track.timing
    guard timing.keyframes.values.allSatisfy({ $0.allSatisfy { $0.frame < duration } }) else {
      refuse("Move or remove keyframes beyond the new duration first"); return
    }
    timing.from = start - track.offset
    timing.duration = duration
    await writeTiming(source, timing, name: "Object Timing")
  }

  public func setKeyframe(of source: String, key: String, frame: Int, value: Double,
                          easing: String = "linear", replacing oldFrame: Int? = nil) async {
    guard let track = objectTracks.first(where: { $0.src == source }), let composition = player.composition else { return }
    if let reason = track.reason { refuse(reason); return }
    let local = frame - track.start
    guard local >= 0, frame < track.end(in: composition.durationInFrames), value.isFinite,
      ["linear", "hold"].contains(easing) else { refuse("Keyframe must be inside the object"); return }
    var timing = track.timing
    var points = timing.keyframes[key] ?? []
    if let oldFrame { points.removeAll { $0.frame == oldFrame } }
    if points.contains(where: { $0.frame == local }), oldFrame != local {
      refuse("A keyframe already exists at this frame"); return
    }
    points.removeAll { $0.frame == local }
    points.append(.init(frame: local, value: value, easing: easing))
    timing.keyframes[key] = points.sorted { $0.frame < $1.frame }
    await writeTiming(source, timing, name: oldFrame == nil ? "Add Keyframe" : "Edit Keyframe")
  }

  public func removeKeyframe(of source: String, key: String, frame: Int) async {
    guard let track = objectTracks.first(where: { $0.src == source }) else { return }
    if let reason = track.reason { refuse(reason); return }
    var timing = track.timing
    timing.keyframes[key]?.removeAll { $0.frame == frame }
    if timing.keyframes[key]?.isEmpty == true { timing.keyframes.removeValue(forKey: key) }
    await writeTiming(source, timing, name: "Delete Keyframe")
  }

  private func writeTiming(_ source: String, _ timing: ObjectTiming, name: String) async {
    do { await apply([try .setTimeline(source, timing)], name: name, from: .user) } catch { show(.failure, String(describing: error)) }
  }

  /// Captures the evaluated style at the requested playhead, never a stale displayed frame.
  /// All numeric attributes are saved together as one source edit and one undo step.
  public func captureKeyframe() async {
    observeKeyframePlayhead()
    guard status == .idle, !isGesturing, !isCapturingKeyframe,
      let source = selection, let track = selectedTrack, let composition = player.composition,
      let stamp = SourceStamp(source), let text = files[stamp.file] else { return }
    if let reason = track.reason { refuse(reason); return }
    let frame = player.currentFrame
    guard frame >= track.start, frame < track.end(in: composition.durationInFrames) else {
      refuse("Move the playhead inside the object before adding a keyframe"); return
    }
    player.pause()
    isCapturingKeyframe = true
    defer { isCapturingKeyframe = false }
    let draft = keyframeDraft
    let path = selectedPath
    do {
      let summary = try await service.perform { try $0.styles(source: text, src: source) }
      let rendered = try await player.render(frame: frame)
      guard selection == source, player.currentFrame == frame, files[stamp.file] == text,
        keyframeDraft == draft, player.composition?.id == composition.id, status == .idle else { return }
      let evaluated: [String: JSONValue]?
      if summary.isThree {
        evaluated = rendered.tree.threeEditorElements.first { $0.source == source }?.properties
      } else if summary.isMap {
        evaluated = rendered.tree.editorElements.first { $0.source == source }?.properties
      } else {
        let box = rendered.layout.first { $0.id == path && $0.source == source }
          ?? rendered.layout.first { $0.source == source }
        evaluated = box.flatMap { rendered.tree.node(at: $0.id)?.style }
      }
      guard let evaluated else { refuse("The selected object is not visible at this frame"); return }
      let current = evaluated.merging(draft) { _, new in new }
      var timing = track.timing
      var captured = 0
      var operations: [EditOperation] = []
      let capturable: Set<String> = summary.isMap
        ? MapCatalog.keyframeKeys(summary.type)
        : Set(summary.properties.filter { $0.kind == .static && $0.value?.number != nil }.map(\.key))
      for key in capturable.union(draft.keys).sorted() {
        guard let value = current[key]?.number, value.isFinite else { continue }
        if !summary.isMap, summary.property(key) == nil { operations.append(.setStyle(source, key, .number(value))) }
        let local = frame - track.start
        var points = timing.keyframes[key] ?? []
        let easing = points.first { $0.frame == local }?.easing ?? "linear"
        points.removeAll { $0.frame == local }
        points.append(.init(frame: local, value: value, easing: easing))
        timing.keyframes[key] = points.sorted { $0.frame < $1.frame }
        captured += 1
      }
      guard captured > 0 else { refuse("This object has no editable numeric style attributes to capture"); return }
      operations.append(try .setTimeline(source, timing))
      await apply(operations, name: "Keyframe at frame \(frame)", from: .user)
    } catch { show(.failure, "Could not capture keyframe: \(error)") }
  }

  /// Current inspector value, including unsaved canvas/inspector adjustments at this frame.
  public var detectedStyleProperties: [StyleSummary.Property] {
    guard let styles else { return [] }
    if styles.isPropDomain { return styles.properties }
    let resolved = selectedBox.flatMap { player.displayedFrame?.tree.node(at: $0.id)?.style } ?? [:]
    return styles.detectedProperties(resolved: resolved)
  }

  public func currentStyleValue(_ key: String) -> JSONValue? {
    if let draft = keyframeDraft[key] { return draft }
    if styles?.isThree == true, let value = player.displayedFrame?.tree.threeEditorElements
      .first(where: { $0.source == selection })?.properties[key] { return value }
    if styles?.isMap == true, let value = mapPreview[key].map(JSONValue.number) ?? selectedMapElement?.properties[key] { return value }
    if let box = selectedBox, let value = player.displayedFrame?.tree.node(at: box.id)?.style[key] { return value }
    return styles?.property(key)?.value
  }

  func stageKeyframeStyle(_ patch: [String: JSONValue]) {
    guard let source = selection else { return }
    if draftFrame != player.currentFrame || draftSource != source { discardKeyframeDraft() }
    draftSource = source
    draftFrame = player.currentFrame
    keyframeDraft.merge(patch) { _, new in new }
    restoreKeyframeDraft()
    show(.info, "Style preview updated. Click Add Keyframe to save at this frame.")
  }

  func restoreKeyframeDraft() {
    player.setPreviewOverrides(selection.map { keyframeDraft.isEmpty ? [:] : [$0: keyframeDraft] } ?? [:])
  }

  public func discardKeyframeDraft() {
    guard !keyframeDraft.isEmpty else { return }
    keyframeDraft = [:]
    draftFrame = nil
    draftSource = nil
    player.setPreviewOverrides([:])
  }

  /// Transport controls can change the frame directly, outside timeline scrubbing.
  public func observeKeyframePlayhead() {
    if draftFrame != nil, draftFrame != player.currentFrame { discardKeyframeDraft() }
  }
}
