import CoreGraphics
import Foundation
import MotionCore
import MotionPortable
import MotionRender
import MotionSwiftUI
import Observation

/// The visual editor for one TSX project directory: selection, canvas gestures with live preview
/// overrides, write-back of static style literals, undo/redo and hot reload.
///
/// Sources compile with the portable compiler and editor stamps, so editing works the same on
/// iOS, iPadOS and macOS. Every edit is written to the TSX file; the source stays the truth.
public enum EditorNoticeKind: Sendable { case info, refusal, conflict, failure }

@MainActor
@Observable
public final class EditorModel {
  public enum Status: Equatable, Sendable {
    case idle, compiling, saving
    case failed(String)
  }

  /// A transient status overlay message.
  public struct Notice: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let kind: EditorNoticeKind
    public let message: String
  }

  public private(set) var isCapturingKeyframe = false
  public private(set) var keyframeDraft: [String: JSONValue] = [:]
  private var draftFrame: Int?
  private var draftSource: String?

  public private(set) var objectTracks: [ObjectTrack] = []
  public private(set) var timelineSources: Set<String> = []

  public let player: MotionPlayer
  public let project: URL
  public let entry: String
  public private(set) var files: [String: String] = [:]
  public private(set) var status: Status = .idle
  public private(set) var notice: Notice?
  /// Source stamp of the selected element and the layout-box path of the picked instance.
  public private(set) var selection: String?
  public private(set) var selectedPath: String?
  public private(set) var styles: StyleSummary?
  public private(set) var guides: [SnapGuide] = []
  public private(set) var isGesturing = false
  public var snapsToGuides = true
  public private(set) var canUndo = false
  public private(set) var canRedo = false
  /// Haptic triggers (`.sensoryFeedback`): selection, snap, commit and refusal.
  public private(set) var selectionFeedback = 0
  public private(set) var snapFeedback = 0
  public private(set) var commitFeedback = 0
  public private(set) var refusalFeedback = 0

  @ObservationIgnored private let service = EditService()
  @ObservationIgnored private var undoStack: [Change] = []
  @ObservationIgnored private var redoStack: [Change] = []
  @ObservationIgnored private var gestureTarget: GestureTarget?
  @ObservationIgnored private var gesturePatch: [String: JSONValue] = [:]
  @ObservationIgnored private var noticeTask: Task<Void, Never>?

  private struct Change {
    let name: String
    let operations: [EditOperation]
  }

  public init(project: URL, entry: String, configuration: MotionPlayer.Configuration = .init()) {
    self.project = project
    self.entry = entry
    player = MotionPlayer(configuration: configuration)
  }

  deinit { service.stop() }

  // MARK: Loading

  /// Reads the project from disk and compiles it with editor stamps.
  public func open(compositionID: String? = nil) async {
    status = .compiling
    do {
      let project = project
      files = try await Task.detached { try PortableCompiler.sources(in: project) }.value
    } catch {
      status = .failed(String(describing: error))
      return
    }
    await player.load(.portable(project: project, entry: entry, stamp: true), compositionID: compositionID)
    status = finish()
    await refreshStyles()
    await refreshTimeline()
  }

  private func finish() -> Status {
    if case .failed(let message) = player.status { return .failed(message) }
    return .idle
  }

  private func reload() async {
    status = .compiling
    await player.reload(.portable(project: project, entry: entry, stamp: true))
    status = finish()
    await refreshStyles()
    await refreshTimeline()
  }

  // MARK: Selection

  /// The layout box of the selection in the displayed frame.
  public var selectedBox: LayoutBox? {
    guard let selection, let layout = player.displayedFrame?.layout else { return nil }
    return layout.first { $0.id == selectedPath && $0.source == selection } ?? layout.first { $0.source == selection }
  }

  /// How many rendered instances share the selected source element (for example in a `map`).
  public var selectionInstances: Int {
    guard let selection else { return 0 }
    return player.displayedFrame?.layout.filter { $0.source == selection }.count ?? 0
  }

  /// The selected box after its static translate/scale transform, for handles and hit testing.
  public var selectedRect: CGRect? {
    guard let box = selectedBox else { return nil }
    return visualRect(box)
  }

  /// Selects the topmost stamped element under `point` (composition pixels), in reverse paint order.
  public func select(at point: CGPoint) {
    let hit = hitTest(point)
    if hit?.source != selection || hit?.id != selectedPath {
      discardKeyframeDraft()
      selection = hit?.source
      selectedPath = hit?.id
      selectionFeedback += 1
      Task { await refreshStyles() }
    }
  }

  public func clearSelection() {
    guard selection != nil else { return }
    discardKeyframeDraft()
    selection = nil
    selectedPath = nil
    styles = nil
    selectionFeedback += 1
  }

  public func hitTest(_ point: CGPoint) -> LayoutBox? {
    guard let layout = player.displayedFrame?.layout else { return nil }
    return layout.reversed().first { box in
      box.id != "0" && box.source != nil && visualRect(box).contains(point)
    }
  }

  func visualRect(_ box: LayoutBox) -> CGRect {
    let rect = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
    guard let style = player.displayedFrame?.tree.node(at: box.id)?.style,
      let list = try? TransformList(style["transform"])
    else { return rect }
    var result = rect
    for function in list.functions {
      let numbers = function.arguments.compactMap { Double($0.replacingOccurrences(of: "px", with: "")) }
      switch function.name {
      case "translate": result = result.offsetBy(dx: numbers.first ?? 0, dy: numbers.count > 1 ? numbers[1] : 0)
      case "translateX": result = result.offsetBy(dx: numbers.first ?? 0, dy: 0)
      case "translateY": result = result.offsetBy(dx: 0, dy: numbers.first ?? 0)
      case "scale":
        let sx = numbers.first ?? 1
        let sy = numbers.count > 1 ? numbers[1] : sx
        result = CGRect(
          x: result.midX - result.width * sx / 2, y: result.midY - result.height * sy / 2,
          width: result.width * sx, height: result.height * sy)
      default: continue
      }
    }
    return result
  }

  private func refreshStyles() async {
    guard let selection, let stamp = SourceStamp(selection), let source = files[stamp.file] else {
      styles = nil
      return
    }
    let summary = try? await service.perform { try $0.styles(source: source, src: selection) }
    guard self.selection == selection, files[stamp.file] == source else { return }
    styles = summary
  }

}

extension EditorModel {
  // MARK: Gestures

  /// Starts a gesture on the selection. Returns false (with a refusal overlay and haptic) when the
  /// properties it would write are animated, bound or computed.
  @discardableResult
  public func beginGesture(_ gesture: CanvasGesture) -> Bool {
    guard status == .idle, !isGesturing, let selection, let box = selectedBox, let frame = player.displayedFrame,
      let node = frame.tree.node(at: box.id)
    else { return false }
    let parentPath = box.id.split(separator: ".").dropLast().joined(separator: ".")
    let parent = frame.layout.first { $0.id == parentPath }
    let target = GestureTarget(
      style: node.style.merging(keyframeDraft) { _, new in new }, box: CGRect(x: box.x, y: box.y, width: box.width, height: box.height),
      parent: parent.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) } ?? .zero)
    if let reason = refusal(for: GestureMapper.keys(for: gesture, target: target), source: selection) {
      refuse(reason)
      return false
    }
    player.pause()
    gestureTarget = target
    gesturePatch = [:]
    isGesturing = true
    return true
  }

  private func refusal(for keys: [String], source: String) -> String? {
    guard let styles else { return "The selection's source is still loading" }
    guard styles.editable else { return "The style of this element is an expression; edit it in code" }
    for key in keys {
      guard let property = styles.property(key) else { continue }
      switch property.kind {
      case .static: continue
      case .animated: return "\(key) is animated; edit its keyframes on the timeline"
      case .bound: return "\(key) is bound to a variable; edit its definition in code"
      case .computed: return "\(key) is computed; edit it in code"
      }
    }
    return nil
  }

  /// Updates the live preview. Moves snap to canvas and sibling guides within `threshold` pixels.
  public func updateGesture(_ gesture: CanvasGesture, snapThreshold threshold: Double = 6) {
    guard isGesturing, let target = gestureTarget, let composition = player.composition else { return }
    var gesture = gesture
    if case .move(let dx, let dy) = gesture, snapsToGuides {
      let siblings = (player.displayedFrame?.layout ?? []).filter {
        $0.id != selectedPath && $0.id != "0" && !(selectedPath.map($0.id.hasPrefix) ?? false)
      }.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
      let start = selectedRect ?? target.box
      let snapped = Snapping.snap(
        box: start, translation: CGSize(width: dx, height: dy), siblings: siblings,
        canvas: CGSize(width: composition.width, height: composition.height), threshold: threshold)
      if Set(snapped.guides) != Set(guides), !snapped.guides.isEmpty { snapFeedback += 1 }
      guides = snapped.guides
      gesture = .move(dx: snapped.translation.width, dy: snapped.translation.height)
    }
    do {
      gesturePatch = try GestureMapper.patch(for: gesture, target: target)
      if let selection { player.setPreviewOverrides([selection: keyframeDraft.merging(gesturePatch) { _, new in new }]) }
    } catch {
      cancelGesture()
      refuse(String(describing: error))
    }
  }

  public func cancelGesture() {
    isGesturing = false
    guides = []
    gestureTarget = nil
    gesturePatch = [:]
    restoreKeyframeDraft()
  }

  /// Writes the gesture as one `setStyle` per changed key, as one undo step.
  public func endGesture(named name: String) async {
    guard isGesturing, let selection, let target = gestureTarget else { return }
    let patch = gesturePatch.filter { target.style[$0.key] != $0.value }
    isGesturing = false
    guides = []
    gestureTarget = nil
    gesturePatch = [:]
    guard !patch.isEmpty else {
      restoreKeyframeDraft()
      return
    }
    if patch.keys.contains(where: { selectedTrack?.keyframes[$0] != nil }) {
      guard patch.values.allSatisfy({ $0.number != nil }) else {
        restoreKeyframeDraft()
        refuse("Keyframe capture currently supports numeric styles"); return
      }
      stageKeyframeStyle(patch)
      return
    }
    let operations = patch.keys.sorted().map { EditOperation.setStyle(selection, $0, patch[$0]!) }
    if await apply(operations, name: name, from: .user) == false { player.setPreviewOverrides([:]) }
  }

  // MARK: Inspector edits

  public func setStyle(_ key: String, _ value: JSONValue) async {
    guard let selection else { return }
    if selectedTrack?.keyframes[key] != nil {
      guard status == .idle else { return }
      guard value.number?.isFinite == true else { refuse("Keyframed attributes must have numeric values"); return }
      player.pause()
      stageKeyframeStyle([key: value])
      return
    }
    await apply([.setStyle(selection, key, value)], name: "Set \(key)", from: .user)
  }

  public func removeStyle(_ key: String) async {
    guard let selection else { return }
    if selectedTrack?.keyframes[key] != nil { refuse("Remove keyframes before removing \(key)"); return }
    await apply([.removeStyle(selection, key)], name: "Remove \(key)", from: .user)
  }

}

extension EditorModel {
  // MARK: Undo

  public var undoActionName: String? { undoStack.last?.name }
  public var redoActionName: String? { redoStack.last?.name }

  public func undo() async {
    guard status == .idle, let change = undoStack.popLast() else { return }
    updateUndoState()
    await apply(change.operations, name: change.name, from: .undo)
  }

  public func redo() async {
    guard status == .idle, let change = redoStack.popLast() else { return }
    updateUndoState()
    await apply(change.operations, name: change.name, from: .redo)
  }

  private enum Origin { case user, undo, redo }

  private func updateUndoState() {
    canUndo = !undoStack.isEmpty
    canRedo = !redoStack.isEmpty
  }

  // MARK: Write-back

  /// Applies operations in order, writes the touched files, records the inverse and hot-reloads.
  @discardableResult
  private func apply(_ operations: [EditOperation], name: String, from origin: Origin) async -> Bool {
    guard status == .idle else { return false }
    player.pause()
    status = .saving
    let snapshot = files
    let result: Result<(files: [String: String], inverses: [EditOperation]), any Error>
    do {
      result = .success(try await service.perform { compiler in
        var files = snapshot
        var inverses: [EditOperation] = []
        for operation in operations {
          guard let source = files[operation.file] else { throw MotionError("Unknown source file \(operation.file)") }
          let edited = try compiler.edit(source: source, operation: operation)
          files[operation.file] = edited.source
          inverses.insert(edited.inverse, at: 0)
        }
        return (files, inverses)
      })
    } catch {
      result = .failure(error)
    }
    switch result {
    case .failure(let error):
      status = .idle
      if let error = error as? EditError, error.isRefusal { refuse(error.reason) } else if let error = error as? EditError,
        error.isStale {
        show(.conflict, "Source changed, reselect: \(error.reason)")
        await open(compositionID: player.composition?.id)
      } else {
        show(.failure, String(describing: error))
      }
      return false
    case .success(let edited):
      let changed = edited.files.filter { snapshot[$0.key] != $0.value }
      do {
        for (file, source) in changed {
          let url = project.appendingPathComponent(file)
          // Never overwrite edits made outside the editor since the last load.
          let disk = try String(contentsOf: url, encoding: .utf8)
          guard disk == snapshot[file] else {
            status = .idle
            show(.conflict, "\(file) changed on disk; reloaded it. Repeat the edit.")
            await open(compositionID: player.composition?.id)
            return false
          }
          try source.write(to: url, atomically: true, encoding: .utf8)
        }
      } catch {
        status = .idle
        show(.failure, "Could not save: \(error)")
        return false
      }
      discardKeyframeDraft()
      files = edited.files
      let change = Change(name: name, operations: edited.inverses)
      switch origin {
      case .user:
        undoStack.append(change)
        redoStack.removeAll()
      case .undo: redoStack.append(change)
      case .redo: undoStack.append(change)
      }
      updateUndoState()
      commitFeedback += 1
      await reload()
      show(.info, origin == .undo ? "Undid \(name)" : origin == .redo ? "Redid \(name)" : "Saved \(name)")
      return true
    }
  }

  private func refuse(_ reason: String) {
    refusalFeedback += 1
    show(.refusal, reason)
  }

  private func show(_ kind: EditorNoticeKind, _ message: String) {
    let notice = Notice(kind: kind, message: message)
    self.notice = notice
    noticeTask?.cancel()
    noticeTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(kind == .info ? 1.6 : 3.5))
      guard !Task.isCancelled, let self, self.notice?.id == notice.id else { return }
      self.notice = nil
    }
  }
}

extension EditorModel {
  /// The canvas and timeline share source selection, playhead, writes, notices and undo history.
  public var selectedTrack: ObjectTrack? { objectTracks.first { $0.src == selection } }

  public var timelineTracks: [ObjectTrack] {
    objectTracks.filter { track in
      timelineSources.contains(trackGroup(track)) || track.owner == player.composition?.id
    }
  }

  /// Remember source files as they appear; timed-out objects remain on the timeline.
  public func observeTimelineFrame() {
    for box in player.displayedFrame?.layout ?? [] {
      if let source = box.source, let track = objectTracks.first(where: { $0.src == source }) {
        timelineSources.insert(trackGroup(track))
      }
    }
  }

  private func trackGroup(_ track: ObjectTrack) -> String {
    "\(SourceStamp(track.src)?.file ?? "")#\(track.owner ?? "")"
  }

  public func resetTimelineSelection() {
    clearSelection()
    timelineSources = []
  }

  private func refreshTimeline() async {
    let snapshot = files
    do {
      objectTracks = try await service.perform { compiler in
        try snapshot.keys.sorted().filter { ["tsx", "jsx"].contains(URL(fileURLWithPath: $0).pathExtension) }
          .flatMap { try compiler.timeline(source: snapshot[$0]!, file: $0) }
      }
      observeTimelineFrame()
    } catch { show(.failure, "Cannot read timeline: \(error)") }
  }

  public func selectTrack(_ track: ObjectTrack) {
    guard !isGesturing else { return }
    player.pause()
    if selection != track.src { discardKeyframeDraft() }
    selection = track.src
    selectedPath = player.displayedFrame?.layout.first { $0.source == track.src }?.id
    styles = nil
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
}

extension EditorModel {
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
      let box = rendered.layout.first { $0.id == path && $0.source == source }
        ?? rendered.layout.first { $0.source == source }
      guard let box, let node = rendered.tree.node(at: box.id) else {
        refuse("The selected object is not visible at this frame"); return
      }
      let current = node.style.merging(draft) { _, new in new }
      var timing = track.timing
      var captured = 0
      var operations: [EditOperation] = []
      for key in Set(summary.properties.filter { $0.kind == .static && $0.value?.number != nil }.map(\.key))
        .union(draft.keys).sorted() {
        guard let value = current[key]?.number, value.isFinite else { continue }
        if summary.property(key) == nil { operations.append(.setStyle(source, key, .number(value))) }
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
    let resolved = selectedBox.flatMap { player.displayedFrame?.tree.node(at: $0.id)?.style } ?? [:]
    return styles.detectedProperties(resolved: resolved)
  }

  public func currentStyleValue(_ key: String) -> JSONValue? {
    if let draft = keyframeDraft[key] { return draft }
    if let box = selectedBox, let value = player.displayedFrame?.tree.node(at: box.id)?.style[key] { return value }
    return styles?.property(key)?.value
  }

  private func stageKeyframeStyle(_ patch: [String: JSONValue]) {
    guard let source = selection else { return }
    if draftFrame != player.currentFrame || draftSource != source { discardKeyframeDraft() }
    draftSource = source
    draftFrame = player.currentFrame
    keyframeDraft.merge(patch) { _, new in new }
    restoreKeyframeDraft()
    show(.info, "Style preview updated. Click Add Keyframe to save at this frame.")
  }

  private func restoreKeyframeDraft() {
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
