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

  public internal(set) var isCapturingKeyframe = false
  public internal(set) var keyframeDraft: [String: JSONValue] = [:]
  var draftFrame: Int?
  var draftSource: String?

  public internal(set) var objectTracks: [ObjectTrack] = []
  public internal(set) var timelineSources: Set<String> = []

  public let player: MotionPlayer
  public let project: URL
  public let entry: String
  public private(set) var files: [String: String] = [:]
  public private(set) var status: Status = .idle
  public private(set) var notice: Notice?
  /// Source stamp of the selected element and the layout-box path of the picked instance.
  public internal(set) var selection: String?
  public internal(set) var selectedPath: String?
  public internal(set) var styles: StyleSummary?
  public internal(set) var textContent: TextSummary?
  public private(set) var guides: [SnapGuide] = []
  public internal(set) var isGesturing = false
  public var snapsToGuides = true
  public private(set) var canUndo = false
  public private(set) var canRedo = false
  /// Haptic triggers (`.sensoryFeedback`): selection, snap, commit and refusal.
  public internal(set) var selectionFeedback = 0
  public private(set) var snapFeedback = 0
  public private(set) var commitFeedback = 0
  public private(set) var refusalFeedback = 0

  @ObservationIgnored let service = EditService()
  @ObservationIgnored private var undoStack: [Change] = []
  @ObservationIgnored private var redoStack: [Change] = []
  @ObservationIgnored private var gestureTarget: GestureTarget?
  @ObservationIgnored private var gesturePatch: [String: JSONValue] = [:]
  @ObservationIgnored private var noticeTask: Task<Void, Never>?
  /// 3D camera and drag state, see `EditorModel+Three.swift`.
  var three = ThreeEditing()
  @ObservationIgnored var threeWork = ThreeWork()
  var mapState = MapEditing()  // See EditorModel+Map.swift.

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
    if compositionID != player.composition?.id { resetTimelineSelection() }
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

  /// The selected box after its static translate/scale transform, for handles and hit testing.
  public var selectedRect: CGRect? {
    guard styles?.isPropDomain != true, selectedMapElement == nil else { return nil }
    guard let box = selectedBox else { return nil }
    return visualRect(box)
  }

  /// Selects the topmost stamped element under `point` (composition pixels), in reverse paint order.
  public func select(at point: CGPoint) {
    let hit = hitTest(point)
    if hit?.source != selection || hit?.id != selectedPath {
      discardKeyframeDraft()
      textContent = nil
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
    textContent = nil
    selectionFeedback += 1
  }

  public func hitTest(_ point: CGPoint) -> LayoutBox? {
    guard let frame = player.displayedFrame else { return nil }
    return frame.layout.reversed().first { box in
      box.id != "0" && box.source != nil && !ignoresPointerEvents(at: box.id, in: frame.tree)
        && visualRect(box).contains(point)
    }
  }

  private func ignoresPointerEvents(at id: String, in tree: RenderNode) -> Bool {
    var current: RenderNode? = tree
    if current?.style["pointerEvents"]?.string == "none" { return true }
    for part in id.split(separator: ".").dropFirst() {
      guard let index = Int(part), let children = current?.children, children.indices.contains(index) else { return false }
      current = children[index]
      if current?.style["pointerEvents"]?.string == "none" { return true }
    }
    return false
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

  func refreshStyles() async {
    guard let selection, let stamp = SourceStamp(selection), let source = files[stamp.file] else {
      styles = nil
      textContent = nil
      return
    }
    let content = try? await service.perform { try $0.text(source: source, src: selection) }
    let summary = try? await service.perform { try $0.styles(source: source, src: selection) }
    guard self.selection == selection, files[stamp.file] == source else { return }
    styles = summary
    textContent = content
  }
}

extension EditorModel {
  // MARK: Gestures
  /// Starts a gesture on the selection. Returns false (with a refusal overlay and haptic) when the
  /// properties it would write are animated, bound or computed.
  @discardableResult
  public func beginGesture(_ gesture: CanvasGesture) -> Bool {
    if isThreeSelection {
      refuse("Drag on the canvas to orbit the camera or rotate the selected 3D object")
      return false
    }
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
  func textEditTarget(at point: CGPoint) async -> TextEditTarget? {
    guard status == .idle, !isGesturing, let hit = hitTest(point), let source = hit.source else { return nil }
    player.pause()
    select(at: point)
    let frame = player.currentFrame
    await refreshStyles()
    guard selection == source, selectedPath == hit.id, player.currentFrame == frame else { return nil }
    guard canEditText else {
      refuse(textContent?.reason ?? "This element does not contain editable text.")
      return nil
    }
    guard let stamp = SourceStamp(source), let expectedSource = files[stamp.file], let rect = selectedRect else { return nil }
    let node = player.displayedFrame?.tree.node(at: hit.id)
    let fontSize = node?.style["fontSize"]?.number ?? node.flatMap { SelectedFilmText.fontSize(in: $0) } ?? 28
    return TextEditTarget(source: source, expectedSource: expectedSource, text: selectedTextValue, rect: rect, fontSize: fontSize)
  }

  public var canEditText: Bool {
    guard let content = textContent, content.editable else { return false }
    if content.styleContent != true || content.value != nil { return true }
    guard let path = selectedPath, let node = player.displayedFrame?.tree.node(at: path) else { return false }
    return SelectedFilmText.content(in: node) != nil
  }

  /// SVG-backed film layers expose their visible text through the rendered image.
  public var selectedTextValue: String {
    if let value = textContent?.value, !value.isEmpty { return value }
    guard let path = selectedPath, let node = player.displayedFrame?.tree.node(at: path) else {
      return textContent?.value ?? ""
    }
    return SelectedFilmText.content(in: node) ?? textContent?.value ?? ""
  }

  /// Saves the sheet's original target, refusing changes made since the sheet opened.
  @discardableResult
  public func setText(_ text: String, source: String, expectedSource: String, requiresSelection: Bool = true) async -> Bool {
    guard !requiresSelection || selection == source, let stamp = SourceStamp(source), files[stamp.file] == expectedSource else {
      show(.conflict, "The selection or source changed. Close and reopen Edit Text.")
      return false
    }
    if selection == source, text == selectedTextValue { return true }
    return await apply([EditOperation(op: .setText, src: source, key: "children", value: .string(text))],
                       name: "Text", from: .user)
  }

  public func setStyle(_ key: String, _ value: JSONValue) async {
    guard let selection else { return }
    if styles?.isMap == true {
      _ = await setMapValues([key: value], of: selection, name: "Set \(key)")
      return
    }
    if selectedTrack?.keyframes[key] != nil {
      guard status == .idle else { return }
      guard value.number?.isFinite == true else { refuse("Keyframed attributes must have numeric values"); return }
      player.pause()
      if styles?.isPropDomain == true, let track = selectedTrack, let number = value.number {
        let local = player.currentFrame - track.start
        let point = track.keyframes[key]?.first { $0.frame == local }
        await setKeyframe(of: selection, key: key, frame: player.currentFrame, value: number,
                          easing: point?.easing ?? "linear", replacing: point?.frame)
        return
      }
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

  enum Origin { case user, undo, redo }

  private func updateUndoState() {
    canUndo = !undoStack.isEmpty
    canRedo = !redoStack.isEmpty
  }

  // MARK: Write-back
  /// Applies operations in order, writes the touched files, records the inverse and hot-reloads.
  @discardableResult
  func apply(_ operations: [EditOperation], name: String, from origin: Origin) async -> Bool {
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

  func refuse(_ reason: String) {
    refusalFeedback += 1
    show(.refusal, reason)
  }

  func show(_ kind: EditorNoticeKind, _ message: String) {
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
