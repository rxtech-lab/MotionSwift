import SwiftUI
import simd

/// Floating camera panel over a `<ThreeCanvas>`: the evaluated camera at the playhead, a top-down
/// overview of its path through the scene, the canvas drag tool and Add Camera.
struct CameraOverlay: View {
  let model: EditorModel
  @Binding var cameraTool: ThreeDragKind
  @Binding var objectTool: ThreeDragKind
  @State private var expanded = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      if expanded, let camera = model.cameraState {
        values(camera)
        CameraMap(model: model, camera: camera)
          .frame(width: 210, height: 130)
          .accessibilityLabel("Camera path, top view")
        tools
      }
    }
    .padding(10)
    .frame(width: expanded ? 230 : nil, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    .shadow(radius: 8, y: 2)
    .animation(.snappy, value: expanded)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("camera-overlay")
  }

  private var header: some View {
    HStack(spacing: 6) {
      Button { model.selectCamera() } label: {
        Label("Camera", systemImage: "video.fill").font(.callout.weight(.semibold))
          .foregroundStyle(model.isCameraSelected ? Color.accentColor : .primary)
      }
      .buttonStyle(.plain)
      .help("Select the camera to edit it")
      if expanded {
        Text(modeBadge.title)
          .font(.caption2.weight(.semibold))
          .padding(.horizontal, 6).padding(.vertical, 2)
          .background(modeBadge.tint.opacity(0.25), in: Capsule())
          .help(modeHelp)
      }
      Spacer(minLength: 4)
      Button(expanded ? "Collapse" : "Expand", systemImage: expanded ? "chevron.up" : "chevron.down") { expanded.toggle() }
        .labelStyle(.iconOnly).buttonStyle(.borderless)
    }
  }

  private func values(_ camera: CameraState) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
      row("Position", [camera.position.x, camera.position.y, camera.position.z], digits: 2)
      row("Rotation°", [camera.rotation.x, camera.rotation.y, camera.rotation.z].map { $0 * 180 / .pi }, digits: 1)
      GridRow {
        Text("FOV").foregroundStyle(.secondary)
        Text(camera.fov.formatted(.number.precision(.fractionLength(1))) + "°").gridCellColumns(3)
      }
    }
    .font(.caption.monospacedDigit())
  }

  private func row(_ title: String, _ numbers: [Double], digits: Int) -> some View {
    GridRow {
      Text(title).foregroundStyle(.secondary)
      ForEach(numbers.indices, id: \.self) { index in
        Text(numbers[index].formatted(.number.precision(.fractionLength(digits))))
          .frame(minWidth: 40, alignment: .trailing)
      }
    }
  }

  @ViewBuilder private var tools: some View {
    if model.isCameraSelected {
      Picker("Camera tool", selection: $cameraTool) {
        Image(systemName: "rotate.3d").tag(ThreeDragKind.orbit).help("Orbit")
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").tag(ThreeDragKind.pan).help("Pan")
        Image(systemName: "arrow.up.forward.and.arrow.down.backward").tag(ThreeDragKind.dolly).help("Dolly")
      }
      .pickerStyle(.segmented).labelsHidden()
      hint("Drag the canvas to \(cameraTool.rawValue)" + modifiersHint(" · ⇧ pan · ⌥ dolly") + ". "
           + "WASD/QE fly, arrows orbit. " + saveHint)
    } else if model.isThreeSelection {
      Picker("Object tool", selection: $objectTool) {
        Image(systemName: "rotate.right").tag(ThreeDragKind.rotate).help("Rotate")
        Image(systemName: "move.3d").tag(ThreeDragKind.move).help("Move")
      }
      .pickerStyle(.segmented).labelsHidden()
      hint("Drag the canvas to \(objectTool.rawValue) the object" + modifiersHint(" · ⇧ move"))
    } else {
      hint("Click the scene to select the camera, or pick an object on the timeline")
    }
    if !model.hasCameraKeyframes {
      Button {
        Task { await model.addCamera() }
      } label: {
        Label(model.isAddingCamera ? "Adding Camera…"
              : model.cameraMode == .rig ? "Convert Rig to Keyframes" : "Add Camera to Timeline",
              systemImage: "video.badge.plus")
          .frame(maxWidth: .infinity)
      }
      .controlSize(.small)
      .disabled(model.status != .idle || model.isAddingCamera || model.cameraTrack == nil)
      .help("Keyframe the camera on the timeline, baking any camera animation from code")
      .accessibilityIdentifier("overlay-add-camera")
    }
  }

  private var modeBadge: (title: String, tint: Color) {
    switch model.cameraMode {
    case .keyframes: ("Keyframed", .yellow)
    case .rig: ("Code rig", .blue)
    case .authored: ("Code", .green)
    case .bake: ("Code", .secondary)
    }
  }

  private var modeHelp: String {
    switch model.cameraMode {
    case .keyframes: "Timeline keyframes drive the camera"
    case .rig: "\(model.cameraRig?.name ?? "A camera rig") aims the camera from literal keys; drags edit them in code"
    case .authored: "camera={{…}} on ThreeCanvas sets the camera; drags rewrite it"
    case .bake: "Code aims the camera; the first drag adds it to the timeline"
    }
  }

  private var saveHint: String {
    switch model.cameraMode {
    case .keyframes: "Saves a keyframe at the playhead."
    case .rig: "Edits the rig's key at this frame in code."
    case .authored: "Rewrites camera={{…}} in code."
    case .bake: "The first drag adds the camera to the timeline."
    }
  }

  private func hint(_ text: String) -> some View {
    Text(text).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
  }

  private func modifiersHint(_ text: String) -> String {
    #if os(macOS)
    text
    #else
    ""
    #endif
  }
}

/// Top view (X right, Z down) of scene objects, the sampled camera path and the current camera.
private struct CameraMap: View {
  let model: EditorModel
  let camera: CameraState

  var body: some View {
    let path = model.cameraPath
    let objects = model.sceneObjectPositions
    let frame = model.player.currentFrame
    Canvas { context, size in
      let points = path.map(\.position) + objects + [camera.position]
      let xs = points.map(\.x), zs = points.map(\.z)
      let minX = xs.min() ?? -1, maxX = xs.max() ?? 1, minZ = zs.min() ?? -1, maxZ = zs.max() ?? 1
      let span = max(maxX - minX, maxZ - minZ, 1) * 1.15
      let center = SIMD2((minX + maxX) / 2, (minZ + maxZ) / 2)
      let unit = min(size.width, size.height) / span
      func project(_ point: SIMD3<Double>) -> CGPoint {
        CGPoint(x: size.width / 2 + (point.x - center.x) * unit, y: size.height / 2 + (point.z - center.y) * unit)
      }
      context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8), with: .color(.black.opacity(0.35)))
      for object in objects {
        let dot = project(object)
        context.fill(Path(ellipseIn: CGRect(x: dot.x - 1.5, y: dot.y - 1.5, width: 3, height: 3)), with: .color(.white.opacity(0.35)))
      }
      if path.count > 1 {
        var line = Path()
        line.addLines(path.map { project($0.position) })
        context.stroke(line, with: .color(.accentColor.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        let keyFrames = Set(model.cameraKeyFrames)
        for sample in path where keyFrames.contains(sample.frame) {
          let key = project(sample.position)
          context.fill(Path(CGRect(x: key.x - 2.5, y: key.y - 2.5, width: 5, height: 5)), with: .color(.yellow))
        }
      }
      // Current camera: a small frustum wedge pointing along its view direction.
      let origin = project(camera.position)
      let forward = SIMD2(camera.forward.x, camera.forward.z)
      let length = simd_length(forward) > 1e-6 ? simd_normalize(forward) : SIMD2(0, -1)
      let half = camera.fov * .pi / 360
      var wedge = Path()
      wedge.move(to: origin)
      for angle in [-half, half] {
        let rotated = SIMD2(length.x * cos(angle) - length.y * sin(angle), length.x * sin(angle) + length.y * cos(angle))
        wedge.addLine(to: CGPoint(x: origin.x + rotated.x * 22, y: origin.y + rotated.y * 22))
      }
      wedge.closeSubpath()
      context.fill(wedge, with: .color(.accentColor.opacity(0.3)))
      context.stroke(wedge, with: .color(.accentColor), lineWidth: 1)
      context.fill(Path(ellipseIn: CGRect(x: origin.x - 3.5, y: origin.y - 3.5, width: 7, height: 7)), with: .color(.white))
      context.draw(Text("frame \(frame)").font(.caption2).foregroundStyle(.secondary),
                   at: CGPoint(x: 6, y: size.height - 4), anchor: .bottomLeading)
    }
  }
}
