import Foundation
import MotionCore
import MotionPortable
import simd

/// One sample of the evaluated `<ThreeCanvas>` camera, for the camera path overview.
public struct CameraSample: Equatable, Sendable {
  public let frame: Int
  public let position: SIMD3<Double>
  /// Unit view direction (the camera looks down its local -Z).
  public let forward: SIMD3<Double>
}

/// The evaluated camera of the composition's first `<ThreeCanvas>` at the displayed frame.
public struct CameraState: Equatable, Sendable {
  public var position: SIMD3<Double>
  /// three.js Euler angles, order XYZ, radians.
  public var rotation: SIMD3<Double>
  public var fov: Double
  public var zoom: Double

  public var orientation: simd_quatd {
    let value = Scene3D.quaternion(euler: [rotation.x, rotation.y, rotation.z])
    return simd_quatd(ix: value[0], iy: value[1], iz: value[2], r: value[3])
  }

  public var forward: SIMD3<Double> { orientation.act(SIMD3(0, 0, -1)) }

  init?(_ properties: [String: JSONValue]) {
    func number(_ key: String, _ fallback: Double) -> Double { properties[key]?.number ?? fallback }
    guard properties["cameraPositionX"]?.number != nil else { return nil }
    position = SIMD3(number("cameraPositionX", 0), number("cameraPositionY", 0), number("cameraPositionZ", 5))
    rotation = SIMD3(number("cameraRotationX", 0), number("cameraRotationY", 0), number("cameraRotationZ", 0))
    fov = number("cameraFov", 75)
    zoom = number("cameraZoom", 1)
  }
}

/// Canvas drags on 3D selections: the camera orbits, pans or dollies; objects rotate or move.
public enum ThreeDragKind: String, CaseIterable, Sendable {
  case orbit, pan, dolly, rotate, move
  /// Keyboard fly controls: WASD/QE move, arrow keys orbit.
  case fly

  public var isCamera: Bool { [.orbit, .pan, .dolly, .fly].contains(self) }
}

struct ThreeDragState {
  let kind: ThreeDragKind
  let source: String
  let start: [String: Double]
  let keys: [String]
  let position: SIMD3<Double>
  let orientation: simd_quatd
  let pivot: SIMD3<Double>
  let distance: Double
  let fov: Double
}

struct ThreeEditing {
  var cameraPath: [CameraSample] = []
  var preview: [String: Double] = [:]
  var isAddingCamera = false
  var rigs: [CameraRig] = []
}

/// How a camera edit is saved, from the most to the least source-faithful.
public enum CameraEditMode: Equatable, Sendable {
  /// Timeline keyframes on `<ThreeCanvas>` drive the camera; drags add a keyframe at the playhead.
  case keyframes
  /// A code rig with literal keys (`<CameraRig keys={…}>`); drags rewrite or insert its key.
  case rig
  /// `camera={{position, rotation, …}}` is authored and nothing else moves it; drags rewrite it.
  case authored
  /// Other code aims the camera; the first drag adds it to the timeline (baked) and applies.
  case bake
}

struct ThreeWork {
  var drag: ThreeDragState?
  var cameraPathTask: Task<Void, Never>?
  /// Accumulated keyboard flight since the session began: world translation, yaw and pitch.
  var fly = (offset: SIMD3<Double>.zero, yaw: 0.0, pitch: 0.0)
  var flyCommit: Task<Void, Never>?
}

private let cameraKeys = ["cameraPositionX", "cameraPositionY", "cameraPositionZ",
                          "cameraRotationX", "cameraRotationY", "cameraRotationZ", "cameraFov"]

extension EditorModel {
  /// Camera position and aim sampled across the composition.
  public internal(set) var cameraPath: [CameraSample] {
    get { three.cameraPath }
    set { three.cameraPath = newValue }
  }
  /// Live values of an in-progress 3D drag, keyed like the inspector's 3D properties.
  public internal(set) var threePreview: [String: Double] {
    get { three.preview }
    set { three.preview = newValue }
  }
  public internal(set) var isAddingCamera: Bool {
    get { three.isAddingCamera }
    set { three.isAddingCamera = newValue }
  }
  var threeDrag: ThreeDragState? {
    get { threeWork.drag }
    set { threeWork.drag = newValue }
  }
  var cameraPathTask: Task<Void, Never>? {
    get { threeWork.cameraPathTask }
    set { threeWork.cameraPathTask = newValue }
  }

  /// The code camera rig in the camera's source file, if its keys are plain literals.
  public var cameraRig: CameraRig? {
    guard let file = cameraTrack.flatMap({ SourceStamp($0.src)?.file }) else { return nil }
    return three.rigs.first { SourceStamp($0.src)?.file == file }
  }

  public var cameraMode: CameraEditMode {
    if hasCameraKeyframes { return .keyframes }
    if cameraRig != nil { return .rig }
    guard isCameraSelected, let styles else { return .bake }
    for key in cameraKeys.prefix(6) {
      guard let property = styles.property(key), property.kind == .static, let authored = property.value?.number,
        let evaluated = currentStyleValue(key)?.number, abs(authored - evaluated) < 1e-4 else { return .bake }
    }
    return .authored
  }

  /// How many rendered instances share the selected source element (for example in a `map`).
  public var selectionInstances: Int {
    guard let selection else { return 0 }
    let three = player.displayedFrame?.tree.threeEditorElements.filter { $0.source == selection }.count ?? 0
    if three > 0 { return three }
    return player.displayedFrame?.layout.filter { $0.source == selection }.count ?? 0
  }

  // MARK: Camera
  /// The `<ThreeCanvas>` track of the open composition; it carries the camera's keyframes.
  public var cameraTrack: ObjectTrack? { timelineTracks.first { $0.label == "ThreeCanvas" } }

  public var isCameraSelected: Bool { selection != nil && selection == cameraTrack?.src }

  /// Camera keyframes on the timeline drive the shot, overriding code that aims the camera.
  public var hasCameraKeyframes: Bool {
    cameraTrack?.keyframes.keys.contains { $0.hasPrefix("camera") } == true
  }

  /// Whether the selection is a `<ThreeCanvas>` or an R3F element (before its styles load too).
  public var isThreeSelection: Bool {
    if styles?.isThree == true { return true }
    guard let selection else { return false }
    return player.displayedFrame?.tree.threeEditorElements.contains { $0.source == selection } == true
  }

  /// The camera at the displayed frame, including an in-progress camera drag.
  public var cameraState: CameraState? {
    guard let element = player.displayedFrame?.tree.threeEditorElements.first(where: { $0.type == "ThreeCanvas" })
    else { return nil }
    var properties = element.properties
    if element.source == selection {
      for (key, value) in threePreview where key.hasPrefix("camera") { properties[key] = .number(value) }
    }
    return CameraState(properties)
  }

  /// Top-level object positions at the displayed frame, for the camera overview.
  public var sceneObjectPositions: [SIMD3<Double>] {
    func scene(in node: RenderNode) -> Scene3D? { node.scene ?? node.children.lazy.compactMap(scene).first }
    guard let tree = player.displayedFrame?.tree, let scene = scene(in: tree) else { return [] }
    func visit(_ object: Scene3D.Object, _ offset: SIMD3<Double>) -> [SIMD3<Double>] {
      let position = offset + SIMD3(object.position[0], object.position[1], object.position[2])
      if object.kind == "group" { return object.children.flatMap { visit($0, position) } }
      return ["mesh", "model"].contains(object.kind) ? [position] : []
    }
    return scene.objects.flatMap { visit($0, .zero) }
  }

  /// Selects the camera (the `<ThreeCanvas>` track).
  public func selectCamera() {
    if let track = cameraTrack { selectTrack(track) }
  }

  /// Re-reads literal camera rigs from source, then resamples the camera path.
  func refreshCameraRigs() async {
    let files = files
    three.rigs = (try? await service.perform { compiler in
      try files.keys.sorted().filter { ["tsx", "jsx"].contains(URL(fileURLWithPath: $0).pathExtension) }
        .flatMap { try compiler.cameraRigs(source: files[$0]!, file: $0) }
    }) ?? []
    refreshCameraPath()
  }

  /// Samples the evaluated camera across the composition so its animation is visible as a path.
  func refreshCameraPath() {
    cameraPathTask?.cancel()
    guard let composition = player.composition else { cameraPath = []; return }
    let compositionID = composition.id
    let duration = composition.durationInFrames
    cameraPathTask = Task { [weak self] in
      guard let self, !Task.isCancelled else { return }
      let step = max(1, duration / 45)
      var samples: [CameraSample] = []
      let marked = self.cameraKeyFrames.filter { (0..<duration).contains($0) }
      for frame in Set(Array(stride(from: 0, to: duration, by: step)) + [duration - 1] + marked).sorted() {
        guard !Task.isCancelled, self.player.composition?.id == compositionID,
          let rendered = try? await self.player.render(frame: frame)
        else { return }
        guard let element = rendered.tree.threeEditorElements.first(where: { $0.type == "ThreeCanvas" }),
          let camera = CameraState(element.properties)
        else {
          if samples.isEmpty { self.cameraPath = [] }
          return
        }
        if samples.last?.frame != frame {
          samples.append(CameraSample(frame: frame, position: camera.position, forward: camera.forward))
        }
      }
      guard !Task.isCancelled else { return }
      self.cameraPath = samples
    }
  }

  // MARK: 3D drags
  /// Starts a canvas drag on the selected camera or 3D object. Returns false with a refusal
  /// notice when the transform it writes is controlled by code.
  @discardableResult
  public func beginThreeDrag(_ kind: ThreeDragKind) -> Bool {
    guard status == .idle, !isGesturing, !isAddingCamera, let selection, isThreeSelection else { return false }
    let camera = isCameraSelected
    if kind.isCamera != camera {
      refuse(camera ? "Drag to orbit, pan or dolly the camera" : "Drag to rotate or move the selected 3D object")
      return false
    }
    let keys: [String] = switch kind {
    case .orbit, .fly: Array(cameraKeys.prefix(6))
    case .pan, .dolly: Array(cameraKeys.prefix(3))
    case .rotate: ["rotationX", "rotationY"]
    case .move: ["positionX", "positionY"]
    }
    if camera, let reason = cameraTrack?.reason { refuse(reason); return false }
    if !camera, let styles, let reason = threeRefusal(keys, styles: styles) { refuse(reason); return false }
    var start: [String: Double] = [:]
    for key in keys {
      guard let value = currentStyleValue(key)?.number else {
        refuse(camera ? "The camera is not visible at this frame" : "Select a mesh, group, model or light to transform it")
        return false
      }
      start[key] = value
    }
    guard let state = cameraState else { return false }
    let forward = state.forward
    // Orbit around the point the camera looks at: the rig's target, else the scene origin's depth.
    var depth = max(simd_dot(-state.position, forward), 1)
    if camera, cameraMode == .rig, let rig = cameraRig {
      let target = Self.rigTarget(rig, frame: player.currentFrame)
      depth = max(simd_length(target - state.position), 0.1)
    }
    let objectDistance = camera ? depth : max(simd_length(state.position - SIMD3(
      currentStyleValue("positionX")?.number ?? 0, currentStyleValue("positionY")?.number ?? 0,
      currentStyleValue("positionZ")?.number ?? 0)), 1)
    player.pause()
    discardKeyframeDraft()
    threeDrag = ThreeDragState(
      kind: kind, source: selection, start: start, keys: keys, position: state.position,
      orientation: state.orientation, pivot: state.position + forward * depth, distance: objectDistance, fov: state.fov)
    isGesturing = true
    return true
  }

  private func threeRefusal(_ keys: [String], styles: StyleSummary) -> String? {
    for key in keys {
      guard let property = styles.property(key) else { return "This element has no 3D transform to edit" }
      guard property.kind != .static else { continue }
      return "\(key) is \(property.kind.rawValue) in code; edit it there"
    }
    return nil
  }

  /// Updates the live preview from a drag translation in composition pixels.
  public func updateThreeDrag(dx: Double, dy: Double) {
    guard isGesturing, let drag = threeDrag, drag.kind != .fly, let composition = player.composition else { return }
    var values = drag.start
    let right = drag.orientation.act(SIMD3(1, 0, 0))
    let up = drag.orientation.act(SIMD3(0, 1, 0))
    let forward = drag.orientation.act(SIMD3(0, 0, -1))
    // World units per composition pixel at the drag's depth.
    let unit = 2 * drag.distance * tan(drag.fov * .pi / 360) / Double(max(composition.height, 1))
    func setPosition(_ position: SIMD3<Double>) {
      values["cameraPositionX"] = position.x
      values["cameraPositionY"] = position.y
      values["cameraPositionZ"] = position.z
    }
    switch drag.kind {
    case .orbit:
      let yaw = simd_quatd(angle: -dx * 0.01, axis: SIMD3(0, 1, 0))
      let pitch = simd_quatd(angle: -dy * 0.01, axis: simd_normalize(right))
      let rotation = yaw * pitch
      setPosition(drag.pivot + rotation.act(drag.position - drag.pivot))
      let turned = (rotation * drag.orientation).normalized
      let euler = Scene3D.euler(quaternion: [turned.imag.x, turned.imag.y, turned.imag.z, turned.real])
      for (index, key) in ["cameraRotationX", "cameraRotationY", "cameraRotationZ"].enumerated() {
        values[key] = Self.unwrap(euler[index], near: drag.start[key] ?? 0)
      }
    case .pan:
      setPosition(drag.position - right * dx * unit + up * dy * unit)
    case .dolly:
      let travel = min(-dy * drag.distance * 0.005, drag.distance - 0.1)
      setPosition(drag.position + forward * travel)
    case .rotate:
      values["rotationY"] = (drag.start["rotationY"] ?? 0) + dx * 0.01
      values["rotationX"] = (drag.start["rotationX"] ?? 0) + dy * 0.01
    case .fly: return
    case .move:
      values["positionX"] = (drag.start["positionX"] ?? 0) + dx * unit
      values["positionY"] = (drag.start["positionY"] ?? 0) - dy * unit
    }
    threePreview = values
    player.setPreviewOverrides([drag.source: values.mapValues { JSONValue.number($0) }])
  }

  /// Keyboard flight: `move` is in camera space (x right, y up, z forward) in steps scaled to the
  /// scene; `yaw`/`pitch` orbit around the look-at point in radians. Key bursts preview live and
  /// save as one undo step once the keys go quiet.
  public func flyCamera(move: SIMD3<Double> = .zero, yaw: Double = 0, pitch: Double = 0) {
    if threeDrag?.kind != .fly {
      guard !isGesturing else { return }
      if !isCameraSelected { selectCamera() }
      guard beginThreeDrag(.fly) else { return }
      threeWork.fly = (.zero, 0, 0)
    }
    guard let drag = threeDrag else { return }
    threeWork.fly.yaw += yaw
    threeWork.fly.pitch += pitch
    let right = simd_normalize(drag.orientation.act(SIMD3(1, 0, 0)))
    let rotation = simd_quatd(angle: threeWork.fly.yaw, axis: SIMD3(0, 1, 0))
      * simd_quatd(angle: threeWork.fly.pitch, axis: right)
    let turned = (rotation * drag.orientation).normalized
    let local = SIMD3(move.x, move.y, -move.z) * max(drag.distance, 1) * 0.04
    threeWork.fly.offset += turned.act(local)
    let position = drag.pivot + rotation.act(drag.position - drag.pivot) + threeWork.fly.offset
    let euler = Scene3D.euler(quaternion: [turned.imag.x, turned.imag.y, turned.imag.z, turned.real])
    var values = drag.start
    values["cameraPositionX"] = position.x
    values["cameraPositionY"] = position.y
    values["cameraPositionZ"] = position.z
    for (index, key) in ["cameraRotationX", "cameraRotationY", "cameraRotationZ"].enumerated() {
      values[key] = Self.unwrap(euler[index], near: drag.start[key] ?? 0)
    }
    threePreview = values
    player.setPreviewOverrides([drag.source: values.mapValues { JSONValue.number($0) }])
    threeWork.flyCommit?.cancel()
    threeWork.flyCommit = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(450))
      guard !Task.isCancelled, let self, self.threeDrag?.kind == .fly else { return }
      await self.endThreeDrag()
    }
  }

  public func cancelThreeDrag() {
    isGesturing = false
    threeDrag = nil
    threePreview = [:]
    player.setPreviewOverrides([:])
  }

  /// Saves the drag as one undo step: keyframed properties get a keyframe at the playhead,
  /// static ones are rewritten in place.
  public func endThreeDrag() async {
    guard isGesturing, let drag = threeDrag else { return }
    let values = threePreview
    isGesturing = false
    threeDrag = nil
    let changed = values.filter { abs($0.value - (drag.start[$0.key] ?? .nan)) > 1e-9 }
    guard !changed.isEmpty else { threePreview = [:]; player.setPreviewOverrides([:]); return }
    if styles == nil { await refreshStyles() }
    if !drag.kind.isCamera, let styles, let reason = threeRefusal(drag.keys, styles: styles) {
      threePreview = [:]
      player.setPreviewOverrides([:])
      refuse(reason)
      return
    }
    let name: String = switch drag.kind {
    case .orbit: "Orbit Camera"
    case .fly: "Move Camera"
    case .pan: "Pan Camera"
    case .dolly: "Dolly Camera"
    case .rotate: "Rotate Object"
    case .move: "Move Object"
    }
    let saved: Bool
    if drag.kind.isCamera {
      switch cameraMode {
      case .keyframes, .authored: saved = await setThreeValues(values, of: drag.source, name: name)
      case .rig: saved = await setRigKey(values, drag: drag, name: name)
      case .bake: saved = await addCamera(applying: values, name: name)
      }
    } else {
      saved = await setThreeValues(values, of: drag.source, name: name)
    }
    threePreview = [:]
    if !saved { player.setPreviewOverrides([:]) }
  }

  /// Writes several 3D properties as one source edit.
  @discardableResult
  public func setThreeValues(_ values: [String: Double], of source: String, name: String) async -> Bool {
    guard let track = objectTracks.first(where: { $0.src == source }), let composition = player.composition else {
      return await apply(values.keys.sorted().map { .setStyle(source, $0, .number(Self.rounded(values[$0]!))) },
                         name: name, from: .user)
    }
    if let reason = track.reason { refuse(reason); return false }
    var timing = track.timing
    var operations: [EditOperation] = []
    let local = player.currentFrame - track.start
    var keyframed = false
    for key in values.keys.sorted() {
      let value = Self.rounded(values[key]!)
      if var points = timing.keyframes[key] {
        guard local >= 0, player.currentFrame < track.end(in: composition.durationInFrames) else {
          refuse("Move the playhead inside the object to keyframe it"); return false
        }
        let easing = points.first { $0.frame == local }?.easing ?? "linear"
        points.removeAll { $0.frame == local }
        points.append(.init(frame: local, value: value, easing: easing))
        timing.keyframes[key] = points.sorted { $0.frame < $1.frame }
        keyframed = true
      } else {
        operations.append(.setStyle(source, key, .number(value)))
      }
    }
    do {
      if keyframed { operations.append(try .setTimeline(source, timing)) }
    } catch { show(.failure, String(describing: error)); return false }
    return await apply(operations, name: name, from: .user)
  }

  // MARK: Add Camera
  /// Adds an editable camera to the timeline: writes `camera={{…}}` on `<ThreeCanvas>` and bakes
  /// the evaluated camera (including code-driven camera rigs) into keyframes, one undo step.
  @discardableResult
  public func addCamera(applying drag: [String: Double] = [:], name: String = "Add Camera") async -> Bool {
    guard status == .idle, !isGesturing, !isAddingCamera, let track = cameraTrack,
      let composition = player.composition else { return false }
    if let reason = track.reason { refuse(reason); return false }
    let playhead = player.currentFrame
    player.pause()
    isAddingCamera = true
    defer { isAddingCamera = false }
    let end = track.end(in: composition.durationInFrames)
    var frames = Array(stride(from: track.start, to: end, by: 10))
    if frames.last != end - 1 { frames.append(end - 1) }
    if !drag.isEmpty, (track.start..<end).contains(playhead), !frames.contains(playhead) {
      frames = (frames + [playhead]).sorted()
    }
    let sampled: CameraBake
    do {
      guard let result = try await sampleCamera(track: track, frames: frames, compositionID: composition.id) else { return false }
      sampled = result
    } catch { show(.failure, "Could not read the camera: \(error)"); return false }
    var samples = sampled.samples
    let clip = sampled.clip
    guard var first = samples.first else { refuse("The camera is not visible inside this object's range"); return false }
    let moves = samples.contains { sample in
      cameraKeys.contains { abs(sample.values[$0]! - first.values[$0]!) > 1e-4 }
    }
    if !moves { samples = [first] }
    // A drag on a code camera lands at the playhead; a still camera simply takes the new values.
    if !drag.isEmpty {
      if moves, let index = samples.firstIndex(where: { $0.frame == playhead }) {
        samples[index].values.merge(drag) { _, new in new }
      } else if !moves {
        first.values.merge(drag) { _, new in new }
        samples = [first]
      }
    }
    func list(_ prefix: String) -> String {
      "[" + ["X", "Y", "Z"].map { Self.literal(first.values[prefix + $0]!) }.joined(separator: ", ") + "]"
    }
    var literal = "camera={{position: \(list("cameraPosition")), rotation: \(list("cameraRotation")), "
      + "fov: \(Self.literal(first.values["cameraFov"]!))"
    if let clip { literal += ", near: \(Self.literal(clip.near)), far: \(Self.literal(clip.far))" }
    literal += "}}"
    var timing = track.timing
    for key in cameraKeys {
      timing.keyframes[key] = samples.map { .init(frame: $0.frame - track.start, value: Self.rounded($0.values[key]!)) }
    }
    do {
      let operations = [EditOperation(op: .setThreeProperty, src: track.src, key: "cameraFov", raw: literal),
                        try .setTimeline(track.src, timing)]
      guard await apply(operations, name: name, from: .user) else { return false }
      selectCamera()
      if drag.isEmpty {
        show(.info, moves ? "Camera added with \(samples.count) keyframes from its animation"
          : "Camera added. Move the playhead and drag the canvas to animate it.")
      } else {
        show(.info, "Camera moved to the timeline with \(samples.count) keyframe\(samples.count == 1 ? "" : "s")")
      }
      return true
    } catch { show(.failure, String(describing: error)); return false }
  }

  // MARK: Camera rigs
  /// Frames with camera keys (rig keys or timeline keyframes), in composition frames.
  public var cameraKeyFrames: [Int] {
    if hasCameraKeyframes, let track = cameraTrack {
      return (track.keyframes["cameraPositionX"] ?? []).map { $0.frame + track.start }
    }
    return cameraRig?.keys.map(\.frame) ?? []
  }

  /// Rewrites (or inserts) the rig key at the playhead from a camera drag.
  private func setRigKey(_ values: [String: Double], drag: ThreeDragState, name: String) async -> Bool {
    guard let rig = cameraRig else { return false }
    let frame = player.currentFrame
    let position = SIMD3(values["cameraPositionX"] ?? drag.position.x, values["cameraPositionY"] ?? drag.position.y,
                         values["cameraPositionZ"] ?? drag.position.z)
    // Orbit and dolly keep looking at the pivot; a pan carries the target along.
    let target = switch drag.kind {
    case .pan: drag.pivot + (position - drag.position)
    case .fly: drag.pivot + threeWork.fly.offset
    default: drag.pivot
    }
    let existing = rig.keys.first { $0.frame == frame }
    let rolls = rig.keys.contains { $0.roll != nil }
    var key: [String: JSONValue] = [
      "frame": .number(Double(frame)),
      "position": .array([position.x, position.y, position.z].map { .number(Self.rounded($0)) }),
      "target": .array([target.x, target.y, target.z].map { .number(Self.rounded($0)) }),
      "fov": .number(Self.rounded(existing?.fov ?? Self.rigValue(rig, frame: frame) { $0.fov })),
    ]
    if rolls || existing?.roll != nil {
      key["roll"] = .number(Self.rounded(existing?.roll ?? Self.rigValue(rig, frame: frame) { $0.roll ?? 0 }))
    }
    let saved = await apply([EditOperation(op: .setCameraRigKey, src: rig.src, key: "cameraRig", value: .object(key))],
                            name: name, from: .user)
    if saved, existing == nil { show(.info, "Added a \(rig.name ?? "camera rig") key at frame \(frame)") }
    return saved
  }

  /// Deletes the rig key at `frame` (a rig keeps at least two keys).
  public func deleteCameraRigKey(at frame: Int) async {
    guard let rig = cameraRig else { return }
    let value = JSONValue.object(["frame": .number(Double(frame)), "delete": .bool(true)])
    await apply([EditOperation(op: .setCameraRigKey, src: rig.src, key: "cameraRig", value: value)],
                name: "Delete Camera Key", from: .user)
  }

  /// Eases between rig keys like `camera.tsx` (`Easing.inOut(Easing.cubic)`, clamped).
  static func rigValue(_ rig: CameraRig, frame: Int, _ pick: (CameraRig.Key) -> Double) -> Double {
    let keys = rig.keys
    guard let first = keys.first, let last = keys.last else { return 0 }
    if frame <= first.frame { return pick(first) }
    if frame >= last.frame { return pick(last) }
    let next = keys.firstIndex { $0.frame > frame } ?? keys.count - 1
    let (from, to) = (keys[next - 1], keys[next])
    let progress = Double(frame - from.frame) / Double(to.frame - from.frame)
    let eased = progress < 0.5 ? 4 * pow(progress, 3) : 1 - pow(-2 * progress + 2, 3) / 2
    return pick(from) + (pick(to) - pick(from)) * eased
  }

  static func rigTarget(_ rig: CameraRig, frame: Int) -> SIMD3<Double> {
    SIMD3((0..<3).map { axis in rigValue(rig, frame: frame) { $0.target[axis] } })
  }

  private struct CameraBake {
    var samples: [(frame: Int, values: [String: Double])] = []
    var clip: (near: Double, far: Double)?
  }

  /// The evaluated camera at `frames`, with rotations unwrapped between samples. Nil when the
  /// source or composition changed while sampling.
  private func sampleCamera(track: ObjectTrack, frames: [Int], compositionID: String) async throws -> CameraBake? {
    var bake = CameraBake()
    let files = self.files
    for frame in frames {
      let rendered = try await player.render(frame: frame)
      guard self.files == files, player.composition?.id == compositionID else { return nil }
      guard let element = rendered.tree.threeEditorElements.first(where: { $0.source == track.src }) else { continue }
      var values: [String: Double] = [:]
      for key in cameraKeys { values[key] = element.properties[key]?.number }
      guard values.count == cameraKeys.count else { continue }
      if let previous = bake.samples.last?.values {
        for key in cameraKeys where key.contains("Rotation") { values[key] = Self.unwrap(values[key]!, near: previous[key]!) }
      }
      bake.samples.append((frame, values))
      if bake.clip == nil, let scene = Self.scene(in: rendered.tree, source: track.src) {
        bake.clip = (scene.camera.near, scene.camera.far)
      }
    }
    return bake
  }

  private static func scene(in node: RenderNode, source: String) -> Scene3D? {
    if let scene = node.scene, node.source == source { return scene }
    return node.children.lazy.compactMap { scene(in: $0, source: source) }.first
  }

  /// Keeps an angle within π of `reference` so keyframes interpolate the short way.
  static func unwrap(_ angle: Double, near reference: Double) -> Double {
    angle + (2 * .pi) * ((reference - angle) / (2 * .pi)).rounded()
  }

  nonisolated static func rounded(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }

  static func literal(_ value: Double) -> String {
    let rounded = rounded(value)
    return rounded == rounded.rounded() && abs(rounded) < 1e15 ? String(Int(rounded)) : String(rounded)
  }
}
