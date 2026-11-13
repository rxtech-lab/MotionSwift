import MotionCore
import MotionRender
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// The preview canvas: the rendered frame plus a SwiftUI overlay with the selection, resize
/// handles and snapping guides. Overlay shapes stay sharp at any zoom; the engine draws no UI.
///
/// Gestures: tap selects, drag moves (or resizes from a corner handle), two-finger rotate rotates
/// the selection, pinch zooms the canvas. Every gesture writes back once, when it ends.
public struct EditorCanvas: View {
  @Bindable var model: EditorModel
  @Binding var zoom: Double
  @State private var zoomAtGestureStart: Double?
  @State private var drag: DragState?
  @State private var rotationActive = false
  @State private var rotationSnap: Int?
  @State private var hoveredCorner: ResizeHandle?
  @State private var cornerRotation: CornerRotationDrag?

  public init(model: EditorModel, zoom: Binding<Double>) {
    self.model = model
    _zoom = zoom
  }

  private enum DragState: Equatable {
    case move, resize(ResizeHandle), refused
  }

  public var body: some View {
    let composition = model.player.composition
    let ratio = composition.map { Double($0.width) / Double($0.height) } ?? 16 / 9
    GeometryReader { geometry in
      let fitted = fit(ratio: ratio, in: geometry.size)
      let scale = composition.map { fitted.width / Double($0.width) } ?? 1
      ZStack {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture { model.clearSelection() }
        content(scale: scale)
          .frame(width: fitted.width, height: fitted.height)
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Editor canvas")
          .accessibilityIdentifier("editor-canvas")
          .scaleEffect(zoom)
          .frame(width: geometry.size.width, height: geometry.size.height)
      }
      .simultaneousGesture(magnify)
    }
    .clipped()
    .background(Color.black.opacity(0.92))
    .sensoryFeedback(.alignment, trigger: rotationSnap) { _, new in new != nil }
  }

  private func fit(ratio: Double, in size: CGSize) -> CGSize {
    let width = min(size.width, size.height * ratio)
    return CGSize(width: max(width, 1), height: max(width / ratio, 1))
  }

  private func content(scale: Double) -> some View {
    ZStack(alignment: .topLeading) {
      if let frame = model.player.displayedFrame {
        Image(decorative: frame.image, scale: 1)
          .resizable()
          .interpolation(.high)
      } else {
        Color.black
      }
      SelectionOverlay(model: model, scale: scale, zoom: zoom)
      handles(scale: scale)
    }
    .coordinateSpace(.named(Self.space))
    .gesture(tap(scale: scale))
    .gesture(move(scale: scale))
    .simultaneousGesture(rotate)
  }

  static let space = "motionswift.editor.canvas"

  // MARK: Gestures

  private func tap(scale: Double) -> some Gesture {
    SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { value in
      let point = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
      if model.hitTest(point) == nil { model.clearSelection() } else { model.select(at: point) }
    }
  }

  private func move(scale: Double) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
      .onChanged { value in
        guard cornerRotation == nil else { return }
        if drag == nil {
          let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
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
        guard drag == .move else { return }
        model.updateGesture(
          .move(dx: value.translation.width / scale, dy: value.translation.height / scale),
          snapThreshold: 6 / (scale * zoom))
      }
      .onEnded { _ in
        let state = drag
        drag = nil
        if state == .move { Task { await model.endGesture(named: "Move") } }
      }
  }

  private var rotate: some Gesture {
    RotateGesture(minimumAngleDelta: .degrees(2))
      .onChanged { value in
        guard model.selection != nil, cornerRotation == nil else { return }
        if !rotationActive {
          rotationActive = true
          if !model.beginGesture(.rotate(degrees: 0)) {
            drag = .refused
            return
          }
        }
        guard drag != .refused else { return }
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
      }
      .onEnded { _ in
        let refused = drag == .refused
        rotationActive = false
        rotationSnap = nil
        if refused { drag = nil } else { Task { await model.endGesture(named: "Rotate") } }
      }
  }

  private var magnify: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let start = zoomAtGestureStart ?? zoom
        zoomAtGestureStart = start
        zoom = min(max(start * value.magnification, 0.25), 6)
      }
      .onEnded { _ in zoomAtGestureStart = nil }
  }

  @ViewBuilder private func handles(scale: Double) -> some View {
    if let rect = model.selectedRect, drag != .move, !rotationActive {
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

  private func resize(_ handle: ResizeHandle, scale: Double) -> some Gesture {
    DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
      .onChanged { value in
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
