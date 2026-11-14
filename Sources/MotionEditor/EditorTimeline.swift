import MotionCore
import MotionPortable
import MotionSwiftUI
import SwiftUI

/// A separate timeline surface using the same controller as `EditorCanvas`.
public struct EditorTimeline: View {
  @Bindable private var model: EditorModel
  @State private var zoomScale = 6.0
  @GestureState private var magnification = 1.0
  @State private var editingTiming: ObjectTrack?
  @State private var editingKeyframe: KeyframeTarget?
  @State private var movingKeyframe: String?
  @State private var movingFrame: Int?
  private let labelWidth = 170.0

  public init(model: EditorModel) { self.model = model }

  private var duration: Int { model.player.composition?.durationInFrames ?? 1 }
  private var pixelsPerFrame: Double { clampedZoom(zoomScale * magnification) }
  private var trackWidth: Double { Double(duration) * pixelsPerFrame }

  private func clampedZoom(_ scale: Double) -> Double { min(max(scale, 2), 16) }

  private var magnify: some Gesture {
    MagnifyGesture()
      .updating($magnification) { value, scale, _ in scale = value.magnification }
      .onEnded { value in zoomScale = clampedZoom(zoomScale * value.magnification) }
  }

  public var body: some View {
    VStack(spacing: 0) {
      controls
      Divider()
      if model.timelineTracks.isEmpty {
        ContentUnavailableView("Object Timeline", systemImage: "film.stack",
                               description: Text("Object tracks appear when the composition renders."))
      } else {
        ScrollView(.horizontal) {
          VStack(spacing: 0) {
            ruler
            ScrollView(.vertical) {
              VStack(spacing: 1) {
                ForEach(model.timelineTracks) { track in
                  trackRow(track)
                  if model.selection == track.src {
                    if track.label == "ThreeCanvas", model.cameraMode == .rig, let rig = model.cameraRig {
                      CameraRigLane(model: model, rig: rig, labelWidth: labelWidth, scale: pixelsPerFrame, width: trackWidth)
                    }
                    ForEach(track.keyframes.keys.sorted(), id: \.self) { key in
                      keyframeLane(track, key: key)
                    }
                  }
                }
              }
            }
          }
          .overlay(alignment: .topLeading) {
            TimelinePlayhead(player: model.player, labelWidth: labelWidth, scale: pixelsPerFrame)
          }
        }
        .simultaneousGesture(magnify)
        .sensoryFeedback(.selection, trigger: magnification != 1) { _, active in active }
      }
    }
    .background(.background)
    .accessibilityIdentifier("editor-timeline")
    .sheet(item: $editingTiming) { track in ObjectTimingSheet(model: model, track: track) }
    .sheet(item: $editingKeyframe) { target in KeyframeSheet(model: model, target: target) }
  }

  private var controls: some View {
    HStack {
      Label("Timeline", systemImage: "film.stack").font(.headline)
      Spacer()
      if model.cameraTrack != nil, !model.hasCameraKeyframes {
        Button(model.isAddingCamera ? "Adding Camera…" : model.cameraMode == .rig ? "Rig to Keyframes" : "Add Camera",
               systemImage: "video.badge.plus") {
          Task { await model.addCamera() }
        }
        .help("Keyframe the 3D camera on the timeline, baking any camera animation from code")
        .disabled(model.status != .idle || model.isAddingCamera || model.isGesturing)
        .accessibilityIdentifier("add-camera")
      }
      Button("Timing…", systemImage: "clock") { editingTiming = model.selectedTrack }
        .disabled(model.selectedTrack == nil || model.selectedTrack?.reason != nil || model.status != .idle)
        .accessibilityIdentifier("edit-object-timing")
      Button("Add Keyframe", systemImage: "diamond") {
        Task { await model.captureKeyframe() }
      }
      .help("Capture the object's current numeric style at the playhead")
      .disabled(model.selectedTrack == nil || model.selectedTrack?.reason != nil || model.status != .idle
                || model.isCapturingKeyframe || model.isGesturing)
      .accessibilityIdentifier("add-keyframe")
      Menu {
        ForEach([2.0, 4, 6, 10, 16], id: \.self) { scale in
          Button("\(Int(scale)) px/frame") { zoomScale = scale }
        }
      } label: { Image(systemName: "plus.magnifyingglass") }
      .help("Timeline zoom · Pinch the timeline to zoom in or out")
      .accessibilityLabel("Timeline zoom")
    }
    .buttonStyle(.borderless)
    .padding(.horizontal, 12).padding(.vertical, 8)
  }

  private var ruler: some View {
    let step = max(1, Int(60 / pixelsPerFrame))
    let total = duration
    let scale = pixelsPerFrame
    return HStack(spacing: 0) {
      Text("Objects · frames").font(.caption).foregroundStyle(.secondary)
        .frame(width: labelWidth, height: 30, alignment: .leading)
      Canvas { context, size in
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.secondary.opacity(0.08)))
        var frame = 0
        while frame < total {
          let x = Double(frame) * scale + 3
          if x <= size.width {
            context.draw(
              Text("\(frame)").font(.caption2.monospacedDigit()).foregroundStyle(.primary),
              at: CGPoint(x: x, y: 5),
              anchor: .topLeading)
          }
          frame += step
        }
      }
      .frame(width: trackWidth, height: 30)
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { value in
        model.scrub(to: Int((value.location.x / pixelsPerFrame).rounded()))
      })
      .accessibilityLabel("Timeline ruler")
      .accessibilityAdjustableAction { direction in model.player.step(by: direction == .increment ? 1 : -1) }
    }
  }

  private func trackRow(_ track: ObjectTrack) -> some View {
    HStack(spacing: 0) {
      Button { model.selectTrack(track) } label: {
        VStack(alignment: .leading, spacing: 2) {
          if track.label == "ThreeCanvas" {
            Label("Camera", systemImage: track.reason == nil ? "video" : "lock")
          } else {
            Label(track.label, systemImage: track.reason == nil ? "rectangle" : "lock")
          }
          Text(track.src).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .frame(width: labelWidth - 16, height: 46, alignment: .leading)
        .padding(.horizontal, 8).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(track.reason ?? track.src)
      TimelineClip(model: model, track: track, scale: pixelsPerFrame, width: trackWidth) {
        model.selectTrack(track)
        editingTiming = track
      }
    }
    .background(model.selection == track.src ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.04))
  }

  private func keyframeLane(_ track: ObjectTrack, key: String) -> some View {
    HStack(spacing: 0) {
      Text(key).font(.caption).padding(.leading, 24)
        .frame(width: labelWidth, height: 30, alignment: .leading)
      ZStack(alignment: .leading) {
        Rectangle().fill(.secondary.opacity(0.15)).frame(height: 1)
        ForEach(track.keyframes[key] ?? [], id: \.frame) { point in
          Button {
            editingKeyframe = .init(track: track, key: key, point: point)
          } label: {
            Image(systemName: "diamond.fill").font(.caption).foregroundStyle(.yellow)
              .frame(width: 24, height: 30).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .offset(x: Double(track.start + displayedKeyframe(track, key: key, point: point)) * pixelsPerFrame - 12)
          .simultaneousGesture(keyframeDrag(track, key: key, point: point))
          .disabled(track.reason != nil || model.status != .idle)
          .help("\(key): \(point.value) at frame \(track.start + point.frame)")
          .accessibilityLabel("\(key) keyframe at frame \(track.start + point.frame)")
        }
      }
      .frame(width: trackWidth, height: 30)
    }
  }

  private func keyframeID(_ track: ObjectTrack, key: String, point: EditorKeyframe) -> String {
    "\(track.src)#\(key)#\(point.frame)"
  }

  private func displayedKeyframe(_ track: ObjectTrack, key: String, point: EditorKeyframe) -> Int {
    movingKeyframe == keyframeID(track, key: key, point: point) ? movingFrame ?? point.frame : point.frame
  }

  private func keyframeDrag(_ track: ObjectTrack, key: String, point: EditorKeyframe) -> some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .global)
      .onChanged { value in
        model.player.pause()
        movingKeyframe = keyframeID(track, key: key, point: point)
        let last = track.end(in: duration) - track.start - 1
        movingFrame = min(max(point.frame + Int((value.translation.width / pixelsPerFrame).rounded()), 0), last)
      }
      .onEnded { _ in
        let frame = movingFrame ?? point.frame
        movingKeyframe = nil
        movingFrame = nil
        guard frame != point.frame else { return }
        Task {
          await model.setKeyframe(of: track.src, key: key, frame: track.start + frame, value: point.value,
                                  easing: point.easing, replacing: point.frame)
        }
      }
  }

}

/// Playhead indicator isolated into its own view so `EditorTimeline` does not re-evaluate on playback ticks.
private struct TimelinePlayhead: View {
  let player: MotionPlayer
  let labelWidth: Double
  let scale: Double

  var body: some View {
    Rectangle()
      .fill(.red)
      .frame(width: 1)
      .offset(x: labelWidth + Double(player.currentFrame) * scale)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

private struct TimelineClip: View {
  let model: EditorModel
  let track: ObjectTrack
  let scale: Double
  let width: Double
  let edit: () -> Void
  @State private var previewStart: Int?
  @State private var previewEnd: Int?

  private var end: Int { track.end(in: model.player.composition?.durationInFrames ?? 1) }
  private var start: Int { previewStart ?? track.start }
  private var finish: Int { previewEnd ?? end }

  var body: some View {
    ZStack(alignment: .leading) {
      Color.clear
      HStack(spacing: 0) {
        handle(leading: true)
        Text("\(start) – \(finish)").font(.caption2.monospacedDigit()).lineLimit(1)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle())
          .onTapGesture { model.selectTrack(track) }
          .onTapGesture(count: 2, perform: edit)
          .gesture(drag(edge: nil))
        handle(leading: false)
      }
      .frame(width: max(Double(finish - start) * scale, 16), height: 32)
      .background(model.selection == track.src ? Color.accentColor : Color.accentColor.opacity(0.5),
                  in: RoundedRectangle(cornerRadius: 5))
      .offset(x: Double(start) * scale)
      .contextMenu { Button("Edit Timing…", action: edit) }
      .disabled(track.reason != nil || model.status != .idle)
    }
    .frame(width: width, height: 46)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(track.label), frames \(start) to \(finish)")
  }

  private func handle(leading: Bool) -> some View {
    Capsule().fill(.white.opacity(0.7)).frame(width: 3, height: 16)
      .frame(width: 12, height: 32).contentShape(Rectangle())
      .gesture(drag(edge: leading))
      .accessibilityLabel(leading ? "Trim start" : "Trim end")
  }

  private func drag(edge: Bool?) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .global)
      .onChanged { value in
        let delta = Int((value.translation.width / scale).rounded())
        let limit = min(track.limit ?? Int.max, model.player.composition?.durationInFrames ?? end)
        if previewStart == nil { model.selectTrack(track) }
        if edge == true {
          previewStart = min(max(track.start + delta, track.offset), end - 1)
          previewEnd = end
        } else if edge == false {
          previewStart = track.start
          previewEnd = min(max(end + delta, track.start + 1), limit)
        } else {
          previewStart = min(max(track.start + delta, track.offset), limit - (end - track.start))
          previewEnd = (previewStart ?? track.start) + end - track.start
        }
      }
      .onEnded { _ in
        let newStart = start, newDuration = finish - start
        previewStart = nil
        previewEnd = nil
        guard newStart != track.start || newDuration != end - track.start else { return }
        Task { await model.setTiming(of: track.src, start: newStart, duration: newDuration) }
      }
  }
}

private struct ObjectTimingSheet: View {
  let model: EditorModel
  let track: ObjectTrack
  @Environment(\.dismiss) private var dismiss
  @State private var start: Int
  @State private var duration: Int

  init(model: EditorModel, track: ObjectTrack) {
    self.model = model
    self.track = track
    _start = State(initialValue: track.start)
    _duration = State(initialValue: max(1, track.end(in: model.player.composition?.durationInFrames ?? 1) - track.start))
  }

  private var limit: Int { min(track.limit ?? Int.max, model.player.composition?.durationInFrames ?? 1) }
  private var valid: Bool { start >= track.offset && duration > 0 && start <= limit - duration }

  var body: some View {
    NavigationStack {
      Form {
        Section("Object") { Text(track.src).font(.caption.monospaced()) }
        Section("Composition frames") {
          TextField("Start", value: $start, format: .number.grouping(.never))
          TextField("Duration", value: $duration, format: .number.grouping(.never))
          Text("The end frame is exclusive. Moving an object keeps its keyframes relative to its start.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Object Timing")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task { await model.setTiming(of: track.src, start: start, duration: duration) }
            dismiss()
          }.disabled(!valid || model.status != .idle)
        }
      }
    }
    .modifier(EditorSheetSize())
  }
}

private struct KeyframeTarget: Identifiable {
  let id = UUID()
  let track: ObjectTrack
  var key: String?
  var point: EditorKeyframe?
}

private struct KeyframeSheet: View {
  let model: EditorModel
  let target: KeyframeTarget
  @Environment(\.dismiss) private var dismiss
  @State private var key: String
  @State private var frame: Int
  @State private var value: Double
  @State private var easing: String
  @State private var confirmsDelete = false

  init(model: EditorModel, target: KeyframeTarget) {
    self.model = model
    self.target = target
    let available: [String] = if model.styles?.isMap == true {
      MapCatalog.keyframeKeys(model.styles?.type ?? "").sorted()
    } else {
      model.styles?.properties.filter { $0.kind == .static && $0.value?.number != nil }.map(\.key) ?? []
    }
    let initialKey = target.key ?? available.first ?? ""
    let fallback = model.currentStyleValue(initialKey)?.number ?? model.styles?.property(initialKey)?.value?.number ?? 0
    _key = State(initialValue: initialKey)
    _frame = State(initialValue: target.point.map { target.track.start + $0.frame } ?? model.player.currentFrame)
    _value = State(initialValue: target.point?.value ?? fallback)
    _easing = State(initialValue: target.point?.easing ?? "linear")
  }

  private var properties: [String] {
    if model.styles?.isMap == true {
      return MapCatalog.keyframeKeys(model.styles?.type ?? "").sorted()
    }
    return model.styles?.properties.filter { $0.kind == .static && $0.value?.number != nil }.map(\.key) ?? []
  }
  private var valid: Bool {
    !key.isEmpty && value.isFinite && frame >= target.track.start
      && frame < target.track.end(in: model.player.composition?.durationInFrames ?? 1)
  }

  var body: some View {
    NavigationStack {
      Form {
        if properties.isEmpty && target.key == nil {
          Text("Add a static numeric style property in the inspector first. Code-authored expressions remain protected.")
        } else {
          Picker("Property", selection: $key) {
            ForEach(properties, id: \.self) { Text($0).tag($0) }
          }.disabled(target.key != nil)
          TextField("Composition frame", value: $frame, format: .number.grouping(.never))
          TextField("Value", value: $value, format: .number.grouping(.never))
          Picker("Interpolation to next keyframe", selection: $easing) {
            Text("Linear").tag("linear")
            Text("Hold").tag("hold")
          }
          Text("Values hold before the first and after the last keyframe. Deleting the final keyframe restores the original static style.")
            .font(.caption).foregroundStyle(.secondary)
          if target.point != nil {
            Button("Delete Keyframe…", role: .destructive) { confirmsDelete = true }
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(target.point == nil ? "Add Keyframe" : "Edit Keyframe")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              await model.setKeyframe(of: target.track.src, key: key, frame: frame, value: value,
                                      easing: easing, replacing: target.point?.frame)
            }
            dismiss()
          }.disabled(!valid || model.status != .idle)
        }
      }
      .confirmationDialog("Delete this keyframe?", isPresented: $confirmsDelete, titleVisibility: .visible) {
        Button("Delete Keyframe", role: .destructive) {
          if let point = target.point {
            Task { await model.removeKeyframe(of: target.track.src, key: key, frame: point.frame) }
          }
          dismiss()
        }
      }
      .onChange(of: key) { _, newKey in
        if target.point == nil {
          value = model.currentStyleValue(newKey)?.number ?? model.styles?.property(newKey)?.value?.number ?? 0
        }
      }
    }
    .modifier(EditorSheetSize())
  }
}

private struct EditorSheetSize: ViewModifier {
  func body(content: Content) -> some View {
    #if os(macOS)
    content.frame(minWidth: 440, idealWidth: 480, maxWidth: .infinity,
                  minHeight: 380, idealHeight: 420, maxHeight: .infinity)
    #else
    content.presentationDetents([.large])
    #endif
  }
}

/// Keys of a code camera rig on the Camera track: click to jump, context menu to delete.
private struct CameraRigLane: View {
  let model: EditorModel
  let rig: CameraRig
  let labelWidth: Double
  let scale: Double
  let width: Double
  @State private var deleting: Int?

  var body: some View {
    HStack(spacing: 0) {
      Label(rig.name ?? "Camera rig", systemImage: "chevron.left.forwardslash.chevron.right")
        .font(.caption).padding(.leading, 24)
        .frame(width: labelWidth, height: 30, alignment: .leading)
        .help("Keys written in code; drag the canvas at a frame to edit or add one")
      ZStack(alignment: .leading) {
        Rectangle().fill(.secondary.opacity(0.15)).frame(height: 1)
        ForEach(rig.keys, id: \.frame) { key in
          Button { model.scrub(to: key.frame) } label: {
            Image(systemName: "diamond.fill").font(.caption).foregroundStyle(.cyan)
              .frame(width: 24, height: 30).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .offset(x: Double(key.frame) * scale - 12)
          .contextMenu {
            Button("Go to Frame \(key.frame)") { model.scrub(to: key.frame) }
            Button("Delete Key…", role: .destructive) { deleting = key.frame }
              .disabled(rig.keys.count <= 2)
          }
          .disabled(model.status != .idle)
          .help("Camera key at frame \(key.frame), fov \(key.fov.formatted())")
          .accessibilityLabel("Camera rig key at frame \(key.frame)")
        }
      }
      .frame(width: width, height: 30)
    }
    .confirmationDialog("Delete the camera key at frame \(deleting ?? 0)?", isPresented: Binding(
      get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
      Button("Delete Key", role: .destructive) {
        if let frame = deleting { Task { await model.deleteCameraRigKey(at: frame) } }
      }
    } message: {
      Text("Removes the key from the rig's keys in code. Undo restores it.")
    }
  }
}
