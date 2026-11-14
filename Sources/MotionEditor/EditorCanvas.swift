import MotionCore
import MotionRender
import MotionSwiftUI
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// The preview canvas: the rendered frame plus a SwiftUI overlay with the selection, resize
/// handles and snapping guides. Overlay shapes stay sharp at any zoom; the engine draws no UI.
///
/// Gestures: double-click edits text inline, tap selects, drag moves (or resizes from a corner handle),
/// two-finger pan pans the preview, pinch zooms the preview, and two-finger rotate rotates the selected
/// 2D element (or the preview viewport when no 2D element is selected). Every element gesture writes back once, when it ends.
public struct EditorCanvas: View {
  @Bindable var model: EditorModel
  private var externalViewport: Binding<CanvasViewport>?
  @Binding private var legacyZoom: Double
  @State private var fallbackPan: CGSize = .zero
  @State private var fallbackRotation: Angle = .zero
  @State private var previousMagnification: Double?
  @State private var isViewportPanning = false
  @State private var drag: DragState?
  @State private var rotationTarget: RotationTarget?
  @State private var previousGestureRotation = 0.0
  @State private var unsnappedViewportRotation: Double?
  @State private var rotationSnap: Int?
  @State private var hoveredCorner: ResizeHandle?
  @State private var cornerRotation: CornerRotationDrag?
  @State private var textTarget: EditorModel.TextEditTarget?
  @State private var textCommit = 0
  @State private var cameraTool: ThreeDragKind = .orbit
  @State private var objectTool: ThreeDragKind = .rotate
  @FocusState private var canvasFocused: Bool

  public init(model: EditorModel, viewport: Binding<CanvasViewport>) {
    self.model = model
    self.externalViewport = viewport
    _legacyZoom = .constant(1)
  }

  public init(model: EditorModel, zoom: Binding<Double>) {
    self.model = model
    self.externalViewport = nil
    _legacyZoom = zoom
  }

  private var viewport: CanvasViewport {
    get {
      externalViewport?.wrappedValue ?? CanvasViewport(zoom: legacyZoom, pan: fallbackPan, rotation: fallbackRotation)
    }
    nonmutating set {
      if let externalViewport {
        externalViewport.wrappedValue = newValue
      } else {
        legacyZoom = newValue.zoom
        fallbackPan = newValue.pan
        fallbackRotation = newValue.rotation
      }
    }
  }

  private var zoom: Double { viewport.zoom }

  private var isTwoFingerActive: Bool {
    isViewportPanning || previousMagnification != nil || rotationTarget != nil
  }

  private var rotatesSelectedElement: Bool {
    model.selection != nil && !model.isThreeSelection && !model.isMapSelection
  }

  private enum DragState: Equatable {
    case move, resize(ResizeHandle), three, map, refused
  }

  private enum RotationTarget: Equatable {
    case viewport, element, refused
  }

  public var body: some View {
    let composition = model.player.composition
    let ratio = composition.map { Double($0.width) / Double($0.height) } ?? 16 / 9
    GeometryReader { geometry in
      let fitted = fit(ratio: ratio, in: geometry.size)
      let scale = composition.map { fitted.width / Double($0.width) } ?? 1
      ZStack {
        panBridge(in: geometry.size, fitted: fitted)
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            if textTarget != nil { textCommit += 1; return }
            model.clearSelection()
          }
        content(scale: scale)
          .frame(width: fitted.width, height: fitted.height)
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Editor canvas")
          .accessibilityIdentifier("editor-canvas")
          .scaleEffect(viewport.zoom)
          .rotationEffect(viewport.rotation)
          .offset(viewport.pan)
          .frame(width: geometry.size.width, height: geometry.size.height)
      }
      .simultaneousGesture(
        magnify(in: geometry.size, fitted: fitted)
          .simultaneously(with: rotate(in: geometry.size, fitted: fitted))
      )
      .overlay(alignment: .topTrailing) {
        if model.cameraState != nil {
          CameraOverlay(model: model, cameraTool: $cameraTool, objectTool: $objectTool).padding(10)
        } else if model.hasMapView {
          MapToolbarOverlay(model: model).padding(10)
        }
      }
    }
    .clipped()
    .background(Color.black.opacity(0.92))
    // The canvas takes keyboard focus so camera keys never reach the sidebar list.
    .focusable()
    .focused($canvasFocused)
    .focusEffectDisabled()
    .onKeyPress(phases: [.down, .repeat]) { press in flyKey(press) }
    .simultaneousGesture(TapGesture().onEnded { if textTarget == nil { canvasFocused = true } })
    .onAppear { canvasFocused = true }
    .onChange(of: model.selection) { _, selection in
      if let target = textTarget, target.source != selection { textCommit += 1 }
    }
    .sensoryFeedback(.alignment, trigger: rotationSnap) { _, new in new != nil }
  }

  @ViewBuilder private func panBridge(in size: CGSize, fitted: CGSize) -> some View {
    #if os(macOS)
    CanvasPanGestureBridge(isEnabled: textTarget == nil) { delta in
      var next = viewport
      next.pan(by: delta, viewportSize: size, canvasSize: fitted)
      viewport = next
    }
    #elseif os(iOS)
    CanvasPanGestureBridge(
      isEnabled: textTarget == nil,
      onBegan: {
        isViewportPanning = true
        if cornerRotation == nil { cancelActiveDrag() }
      },
      onPan: { delta in
        var next = viewport
        next.pan(by: delta, viewportSize: size, canvasSize: fitted)
        viewport = next
      },
      onEnded: {
        isViewportPanning = false
      }
    )
    #endif
  }

  private func content(scale: Double) -> some View {
    ZStack(alignment: .topLeading) {
      CanvasFrameImage(player: model.player)
      SelectionOverlay(model: model, scale: scale, zoom: zoom)
      MapHandlesOverlay(model: model, scale: scale, zoom: zoom)
      if textTarget == nil { handles(scale: scale) }
      if let target = textTarget {
        Color.clear.contentShape(Rectangle()).onTapGesture { textCommit += 1 }
        InlineTextEditor(model: model, target: target, scale: scale, zoom: zoom, commit: textCommit) { textTarget = nil }
          .id(target.id)
          .frame(width: max(target.rect.width * scale, 180 / zoom),
                 height: max(target.rect.height * scale, 32 / zoom))
          .offset(x: target.rect.minX * scale, y: target.rect.minY * scale)
          .onChange(of: model.player.currentFrame) { _, _ in textCommit += 1 }
      }
    }
    .coordinateSpace(.named(Self.space))
    .gesture(taps(scale: scale), including: textTarget == nil ? .all : .subviews)
    .gesture(move(scale: scale), including: textTarget == nil ? .all : .subviews)
  }

  static let space = "motionswift.editor.canvas"

  // MARK: Gestures

  private func cancelActiveDrag() {
    guard let active = drag else { return }
    drag = nil
    switch active {
    case .move, .resize:
      model.cancelGesture()
    case .three:
      model.cancelThreeDrag()
    case .map:
      model.cancelMapDrag()
    case .refused:
      break
    }
  }

  private func tap(scale: Double) -> some Gesture {
    SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { value in
      let point = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
      if model.hitTest(point) == nil { model.clearSelection() } else { model.select(at: point) }
    }
  }

  private func move(scale: Double) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
      .onChanged { value in
        guard cornerRotation == nil, textTarget == nil, !isTwoFingerActive else { return }
        if drag == nil {
          let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
          // On a map, drags move route/marker handles or pan the camera.
          if !model.isThreeSelection, model.beginMapDrag(at: start, handleRadius: Self.handleHitSize / (scale * zoom)) {
            drag = .map
            return
          }
          // Inside a ThreeCanvas, drags orbit the camera or rotate the selected 3D object.
          if !model.isThreeSelection, let hit = model.hitTest(start),
            model.player.displayedFrame?.tree.node(at: hit.id)?.scene != nil {
            model.select(at: start)
          }
          if model.isThreeSelection {
            drag = model.beginThreeDrag(threeDragKind) ? .three : .refused
            return
          }
          // Dragging an unselected element selects it first, like a tap.
          if model.selectedRect?.contains(start) != true {
            guard model.hitTest(start) != nil else {
              drag = .refused
              return
            }
            model.select(at: start)
          }
          drag = model.beginGesture(.move(dx: 0, dy: 0)) ? .move : .refused
        }
        if drag == .three {
          model.updateThreeDrag(dx: value.translation.width / scale, dy: value.translation.height / scale)
          return
        }
        if drag == .map {
          model.updateMapDrag(dx: value.translation.width / scale, dy: value.translation.height / scale)
          return
        }
        guard drag == .move else { return }
        model.updateGesture(
          .move(dx: value.translation.width / scale, dy: value.translation.height / scale),
          snapThreshold: 6 / (scale * zoom))
      }
      .onEnded { _ in
        let state = drag
        drag = nil
        if state == .move { Task { await model.endGesture(named: "Move") } }
        if state == .three { Task { await model.endThreeDrag() } }
        if state == .map { Task { await model.endMapDrag() } }
      }
  }

  #if os(iOS)
  static let handleSize = 14.0
  static let handleHitSize = 44.0
  #else
  static let handleSize = 9.0
  static let handleHitSize = 18.0
  #endif

  static var shiftPressed: Bool {
    #if os(macOS)
    NSEvent.modifierFlags.contains(.shift)
    #else
    false
    #endif
  }
}

extension EditorCanvas {
  @ViewBuilder private func handles(scale: Double) -> some View {
    if let rect = model.selectedRect, drag != .move, rotationTarget != .element {
      ForEach(ResizeHandle.allCases, id: \.self) { handle in
        let point = CGPoint(
          x: (handle.movesLeadingEdge ? rect.minX : rect.maxX) * scale,
          y: (handle.movesTopEdge ? rect.minY : rect.maxY) * scale)
        Circle()
          .fill(.white)
          .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
          .frame(width: Self.handleSize / zoom, height: Self.handleSize / zoom)
          .frame(width: Self.handleHitSize / zoom, height: Self.handleHitSize / zoom)
          .contentShape(Rectangle())
          .onHover { hovering in hoveredCorner = hovering ? handle : nil }
          .highPriorityGesture(resize(handle, scale: scale))
          .position(point)
          .allowsHitTesting(cornerRotation == nil)
          .accessibilityLabel("Resize \(handle.rawValue)")
          .accessibilityIdentifier("resize-\(handle.rawValue)")
        #if os(macOS)
        rotationHandle(handle, point: point, scale: scale)
        #endif
      }
    }
  }

  #if os(macOS)
  private func rotationHandle(_ handle: ResizeHandle, point: CGPoint, scale: Double) -> some View {
    let distance = 20.0 / zoom
    let position = CGPoint(x: point.x + (handle.movesLeadingEdge ? -distance : distance),
                           y: point.y + (handle.movesTopEdge ? -distance : distance))
    return Image(systemName: "arrow.counterclockwise")
      .font(.system(size: 13 / zoom, weight: .semibold))
      .foregroundStyle(.white)
      .padding(4 / zoom)
      .background(Color.accentColor, in: Circle())
      .opacity(hoveredCorner == handle || cornerRotation != nil ? 1 : 0.01)
      .frame(width: 28 / zoom, height: 28 / zoom)
      .contentShape(Rectangle())
      .onHover { hovering in hoveredCorner = hovering ? handle : nil }
      .highPriorityGesture(cornerRotate(scale: scale))
      .position(position)
      .help("Drag to rotate. Hold Shift to snap to 15°.")
      .accessibilityLabel("Rotate from \(handle.rawValue)")
      .accessibilityIdentifier("rotate-\(handle.rawValue)")
  }

  private func cornerRotate(scale: Double) -> some Gesture {
    DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
      .onChanged { value in
        guard drag != .refused else { return }
        if cornerRotation == nil {
          guard let rect = model.selectedRect else { return }
          guard model.beginGesture(.rotate(degrees: 0)) else { drag = .refused; return }
          cornerRotation = CornerRotationDrag(
            center: CGPoint(x: rect.midX * scale, y: rect.midY * scale), start: value.startLocation)
        }
        guard drag != .refused, var rotation = cornerRotation else { return }
        let degrees = rotation.update(to: value.location)
        cornerRotation = rotation
        let snapped = (degrees / 15).rounded() * 15
        let snaps = abs(snapped - degrees) < 2 || Self.shiftPressed
        rotationSnap = snaps ? Int(snapped) : nil
        model.updateGesture(.rotate(degrees: snaps ? snapped : degrees))
      }
      .onEnded { _ in
        let committed = cornerRotation != nil
        cornerRotation = nil
        rotationSnap = nil
        drag = nil
        if committed { Task { await model.endGesture(named: "Rotate") } }
      }
  }
  #endif
}

/// Leaf image view so swapping `displayedFrame` at 30–60 fps does not invalidate `EditorCanvas.body`.
private struct CanvasFrameImage: View {
  let player: MotionPlayer

  var body: some View {
    if let frame = player.displayedFrame {
      Image(decorative: frame.image, scale: 1)
        .resizable()
        .interpolation(.high)
    } else {
      Color.black
    }
  }
}

/// Selection outline and snapping guides, positioned from layout boxes.
private struct SelectionOverlay: View {
  let model: EditorModel
  let scale: Double
  let zoom: Double

  var body: some View {
    Canvas { context, size in
      let line = 1.5 / zoom
      if let rect = model.selectedRect {
        let scaled = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        context.stroke(Path(scaled), with: .color(.accentColor), lineWidth: line)
        // Other instances of the same source element (for example from a map) get a lighter outline.
        for box in model.player.displayedFrame?.layout ?? [] where box.source == model.selection && box.id != model.selectedPath {
          let other = CGRect(x: box.x * scale, y: box.y * scale, width: box.width * scale, height: box.height * scale)
          context.stroke(Path(other), with: .color(.accentColor.opacity(0.5)), style: StrokeStyle(lineWidth: line, dash: [4, 3]))
        }
      }
      for guide in model.guides {
        var path = Path()
        switch guide.axis {
        case .vertical:
          path.move(to: CGPoint(x: guide.position * scale, y: 0))
          path.addLine(to: CGPoint(x: guide.position * scale, y: size.height))
        case .horizontal:
          path.move(to: CGPoint(x: 0, y: guide.position * scale))
          path.addLine(to: CGPoint(x: size.width, y: guide.position * scale))
        }
        context.stroke(path, with: .color(.pink), lineWidth: line)
      }
    }
    .allowsHitTesting(false)
  }
}

/// Incremental angles avoid a 360° jump when a pointer crosses the atan2 seam.
struct CornerRotationDrag {
  let center: CGPoint
  private var previousAngle: Double
  private(set) var degrees = 0.0

  init(center: CGPoint, start: CGPoint) {
    self.center = center
    previousAngle = atan2(start.y - center.y, start.x - center.x) * 180 / .pi
  }

  mutating func update(to point: CGPoint) -> Double {
    let angle = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
    var delta = angle - previousAngle
    if delta > 180 { delta -= 360 }
    if delta < -180 { delta += 360 }
    degrees += delta
    previousAngle = angle
    return degrees
  }
}

extension EditorCanvas {
  private func taps(scale: Double) -> some Gesture {
    let doubleTap = SpatialTapGesture(count: 2, coordinateSpace: .named(Self.space)).onEnded { value in
      let point = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
      Task { textTarget = await model.textEditTarget(at: point) }
    }
    return doubleTap.exclusively(before: tap(scale: scale))
  }
}

extension EditorCanvas {
  /// ⇧ pans the camera or moves an object, ⌥ dollies the camera; otherwise the overlay's tool.
  private var threeDragKind: ThreeDragKind {
    let camera = model.isCameraSelected
    #if os(macOS)
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift) { return camera ? .pan : .move }
    if flags.contains(.option), camera { return .dolly }
    #endif
    return camera ? cameraTool : objectTool
  }
}

extension EditorCanvas {
  private func resize(_ handle: ResizeHandle, scale: Double) -> some Gesture {
    DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
      .onChanged { value in
        guard !isTwoFingerActive else { return }
        if drag == nil { drag = model.beginGesture(.resize(handle: handle, dx: 0, dy: 0, keepsAspectRatio: false))
          ? .resize(handle) : .refused }
        guard drag == .resize(handle) else { return }
        model.updateGesture(.resize(
          handle: handle, dx: value.translation.width / scale, dy: value.translation.height / scale,
          keepsAspectRatio: Self.shiftPressed))
      }
      .onEnded { _ in
        let state = drag
        drag = nil
        if state == .resize(handle) { Task { await model.endGesture(named: "Resize") } }
      }
  }
}

extension EditorCanvas {
  private func clampedAnchor(_ location: CGPoint, in size: CGSize) -> CGPoint {
    guard size.width > 0, size.height > 0 else { return .zero }
    return CGPoint(
      x: min(max(location.x, 0), size.width),
      y: min(max(location.y, 0), size.height))
  }

  private func magnify(in size: CGSize, fitted: CGSize) -> some Gesture {
    MagnifyGesture()
      .onChanged { value in
        guard textTarget == nil else { return }
        let previous = previousMagnification ?? 1.0
        if previousMagnification == nil, cornerRotation == nil { cancelActiveDrag() }
        previousMagnification = value.magnification
        guard previous > 0 else { return }
        let anchor = clampedAnchor(value.startLocation, in: size)
        var next = viewport
        next.zoom(by: value.magnification / previous, anchor: anchor, viewportSize: size, canvasSize: fitted)
        viewport = next
      }
      .onEnded { _ in
        previousMagnification = nil
      }
  }
}

extension EditorCanvas {
  /// W/S forward and back, A/D strafe, Q/E down and up, arrow keys orbit; ⇧ moves faster.
  private func flyKey(_ press: KeyPress) -> KeyPress.Result {
    guard model.cameraState != nil, textTarget == nil, !press.modifiers.contains(.command),
      !press.modifiers.contains(.control) else { return .ignored }
    let speed = press.modifiers.contains(.shift) ? 3.0 : 1.0
    let turn = 0.04 * speed
    switch press.key {
    case .upArrow: model.flyCamera(pitch: turn)
    case .downArrow: model.flyCamera(pitch: -turn)
    case .leftArrow: model.flyCamera(yaw: turn)
    case .rightArrow: model.flyCamera(yaw: -turn)
    default:
      let move: SIMD3<Double>? = switch press.characters.lowercased() {
      case "w": SIMD3(0, 0, 1)
      case "s": SIMD3(0, 0, -1)
      case "a": SIMD3(-1, 0, 0)
      case "d": SIMD3(1, 0, 0)
      case "q": SIMD3(0, -1, 0)
      case "e": SIMD3(0, 1, 0)
      default: nil
      }
      guard let move else { return .ignored }
      model.flyCamera(move: move * speed)
    }
    return .handled
  }
}

extension EditorCanvas {
  private func fit(ratio: Double, in size: CGSize) -> CGSize {
    let width = min(size.width, size.height * ratio)
    return CGSize(width: max(width, 1), height: max(width / ratio, 1))
  }
}

extension EditorCanvas {
  private func rotate(in size: CGSize, fitted: CGSize) -> some Gesture {
    RotateGesture(minimumAngleDelta: .degrees(2))
      .onChanged { value in
        guard cornerRotation == nil, textTarget == nil else { return }
        if rotationTarget == nil {
          cancelActiveDrag()
          previousGestureRotation = 0
          if rotatesSelectedElement {
            rotationTarget = model.beginGesture(.rotate(degrees: 0)) ? .element : .refused
          } else {
            unsnappedViewportRotation = viewport.rotation.degrees
            rotationTarget = .viewport
          }
        }
        switch rotationTarget {
        case .element:
          var degrees = value.rotation.degrees
          let nearest = (degrees / 15).rounded() * 15
          // Snap to 15° steps near them (⇧ on macOS always snaps).
          if abs(nearest - degrees) < 2 || Self.shiftPressed {
            degrees = nearest
            rotationSnap = Int(nearest)
          } else {
            rotationSnap = nil
          }
          model.updateGesture(.rotate(degrees: degrees))
        case .viewport:
          let delta = value.rotation.degrees - previousGestureRotation
          previousGestureRotation = value.rotation.degrees
          let raw = (unsnappedViewportRotation ?? viewport.rotation.degrees) + delta
          unsnappedViewportRotation = raw
          let snapped = CanvasViewport.snappedRotation(raw, shiftPressed: Self.shiftPressed)
          rotationSnap = snapped.snapped
          let anchor = clampedAnchor(value.startLocation, in: size)
          var next = viewport
          next.rotate(to: snapped.degrees, anchor: anchor, viewportSize: size, canvasSize: fitted)
          viewport = next
        case .refused, nil:
          break
        }
      }
      .onEnded { _ in
        let target = rotationTarget
        rotationTarget = nil
        previousGestureRotation = 0
        unsnappedViewportRotation = nil
        rotationSnap = nil
        switch target {
        case .element:
          Task { await model.endGesture(named: "Rotate") }
        case .viewport:
          var next = viewport
          next.normalizeRotation()
          viewport = next
        case .refused, nil:
          break
        }
      }
  }
}
