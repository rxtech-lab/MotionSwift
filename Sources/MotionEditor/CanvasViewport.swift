import CoreGraphics
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Viewport transform for the editor's video preview canvas: zoom, two-finger pan and rotation.
public struct CanvasViewport: Equatable, Sendable {
  public static let minZoom = 0.25
  public static let maxZoom = 6.0

  public var zoom: Double
  public var pan: CGSize
  public var rotation: Angle

  public init(zoom: Double = 1, pan: CGSize = .zero, rotation: Angle = .zero) {
    self.zoom = min(max(zoom, Self.minZoom), Self.maxZoom)
    self.pan = pan
    self.rotation = rotation
  }

  /// Whether the viewport is at its default fitted state (1× zoom, centered, upright).
  public var isIdentity: Bool {
    abs(zoom - 1) < 1e-6
      && abs(pan.width) < 0.5
      && abs(pan.height) < 0.5
      && abs(rotation.degrees.remainder(dividingBy: 360)) < 1e-4
  }

  /// Translates the viewport in screen points, keeping the canvas reachable inside `viewportSize`.
  public mutating func pan(by delta: CGSize, viewportSize: CGSize = .zero, canvasSize: CGSize = .zero) {
    guard delta.width.isFinite, delta.height.isFinite else { return }
    let next = CGSize(width: pan.width + delta.width, height: pan.height + delta.height)
    pan = Self.clampedPan(next, zoom: zoom, viewportSize: viewportSize, canvasSize: canvasSize)
  }

  /// Scales the viewport by `factor` around `anchor` (in viewport coordinates).
  public mutating func zoom(
    by factor: Double, anchor: CGPoint, viewportSize: CGSize, canvasSize: CGSize = .zero
  ) {
    guard factor.isFinite, factor > 0 else { return }
    let nextZoom = min(max(zoom * factor, Self.minZoom), Self.maxZoom)
    let applied = nextZoom / zoom
    let anchorOffset = CGPoint(x: anchor.x - viewportSize.width / 2, y: anchor.y - viewportSize.height / 2)
    let nextPan = CGSize(
      width: anchorOffset.x - applied * (anchorOffset.x - pan.width),
      height: anchorOffset.y - applied * (anchorOffset.y - pan.height))
    zoom = nextZoom
    pan = Self.clampedPan(nextPan, zoom: nextZoom, viewportSize: viewportSize, canvasSize: canvasSize)
  }

  /// Sets the viewport rotation to `degrees`, pivoting around `anchor` (in viewport coordinates).
  public mutating func rotate(
    to degrees: Double, anchor: CGPoint, viewportSize: CGSize, canvasSize: CGSize = .zero
  ) {
    guard degrees.isFinite else { return }
    let deltaRadians = (degrees - rotation.degrees) * .pi / 180
    let cosine = cos(deltaRadians)
    let sine = sin(deltaRadians)
    let anchorOffset = CGPoint(x: anchor.x - viewportSize.width / 2, y: anchor.y - viewportSize.height / 2)
    let dx = anchorOffset.x - pan.width
    let dy = anchorOffset.y - pan.height
    let nextPan = CGSize(
      width: anchorOffset.x - (dx * cosine - dy * sine),
      height: anchorOffset.y - (dx * sine + dy * cosine))
    rotation = .degrees(degrees)
    pan = Self.clampedPan(nextPan, zoom: zoom, viewportSize: viewportSize, canvasSize: canvasSize)
  }

  /// Wraps rotation into `[-180°, 180°]` so animated resets take the shortest angular path.
  public mutating func normalizeRotation() {
    var wrapped = rotation.degrees.remainder(dividingBy: 360)
    if abs(wrapped) < 1e-6 { wrapped = 0 }
    rotation = .degrees(wrapped)
  }

  /// Snaps viewport rotation near 90° cardinal angles (or 15° steps when `shiftPressed` is true).
  public static func snappedRotation(_ degrees: Double, shiftPressed: Bool = false) -> (degrees: Double, snapped: Int?) {
    if shiftPressed {
      let nearest = (degrees / 15).rounded() * 15
      return (nearest, Int(nearest.rounded()))
    }
    let nearest = (degrees / 90).rounded() * 90
    if abs(nearest - degrees) < 2 {
      return (nearest, Int(nearest.rounded()))
    }
    return (degrees, nil)
  }

  /// Maps a point in fitted canvas coordinates (`0...canvasSize`) into viewport screen coordinates.
  public func canvasToViewport(_ point: CGPoint, viewportSize: CGSize, canvasSize: CGSize) -> CGPoint {
    let centered = CGPoint(x: point.x - canvasSize.width / 2, y: point.y - canvasSize.height / 2)
    let scaled = CGPoint(x: centered.x * zoom, y: centered.y * zoom)
    let radians = rotation.radians
    let cosine = cos(radians)
    let sine = sin(radians)
    let rotated = CGPoint(x: scaled.x * cosine - scaled.y * sine, y: scaled.x * sine + scaled.y * cosine)
    return CGPoint(
      x: viewportSize.width / 2 + pan.width + rotated.x,
      y: viewportSize.height / 2 + pan.height + rotated.y)
  }

  static func clampedPan(_ pan: CGSize, zoom: Double, viewportSize: CGSize, canvasSize: CGSize) -> CGSize {
    guard viewportSize.width > 0, viewportSize.height > 0 else { return pan }
    let radius = 0.5 * hypot(canvasSize.width, canvasSize.height) * zoom
    let limitX = max(viewportSize.width * 0.5, radius)
    let limitY = max(viewportSize.height * 0.5, radius)
    return CGSize(
      width: min(max(pan.width, -limitX), limitX),
      height: min(max(pan.height, -limitY), limitY))
  }
}

#if os(macOS)
/// Captures two-finger trackpad scroll gestures over the preview canvas on macOS without intercepting clicks.
struct CanvasPanGestureBridge: NSViewRepresentable {
  let isEnabled: Bool
  let onPan: (CGSize) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> ScrollOverlayView {
    let view = ScrollOverlayView()
    context.coordinator.attach(to: view)
    return view
  }

  func updateNSView(_ nsView: ScrollOverlayView, context: Context) {
    context.coordinator.parent = self
  }

  static func dismantleNSView(_ nsView: ScrollOverlayView, coordinator: Coordinator) {
    coordinator.stop()
  }

  final class ScrollOverlayView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  @MainActor final class Coordinator: NSObject {
    var parent: CanvasPanGestureBridge
    private weak var view: ScrollOverlayView?
    private var monitor: Any?

    init(_ parent: CanvasPanGestureBridge) {
      self.parent = parent
    }

    func attach(to view: ScrollOverlayView) {
      self.view = view
      stop()
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        let location = event.locationInWindow
        let windowNumber = event.windowNumber
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let precise = event.hasPreciseScrollingDeltas
        var consumed = false
        MainActor.assumeIsolated {
          guard let self, self.parent.isEnabled, let view = self.view, let window = view.window,
            window.windowNumber == windowNumber, !view.isHiddenOrHasHiddenAncestor
          else { return }
          let local = view.convert(location, from: nil)
          guard view.visibleRect.contains(local) else { return }
          if let hit = window.contentView?.hitTest(location), hit.enclosingScrollView != nil {
            return
          }
          let scale = precise ? 1.0 : 8.0
          let dx = deltaX * scale
          let dy = deltaY * scale
          if dx != 0 || dy != 0 {
            self.parent.onPan(CGSize(width: dx, height: dy))
          }
          consumed = true
        }
        return consumed ? nil : event
      }
    }

    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
#elseif os(iOS)
/// Recognizes two-finger pan (and trackpad two-finger scroll on iPadOS) simultaneously with pinch and rotate.
struct CanvasPanGestureBridge: UIViewRepresentable {
  let isEnabled: Bool
  let onBegan: () -> Void
  let onPan: (CGSize) -> Void
  let onEnded: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> PanAttachmentView {
    let view = PanAttachmentView()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = false
    view.coordinator = context.coordinator
    context.coordinator.bridgeView = view
    return view
  }

  func updateUIView(_ uiView: PanAttachmentView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.attachIfNeeded()
  }

  static func dismantleUIView(_ uiView: PanAttachmentView, coordinator: Coordinator) {
    coordinator.detach()
  }

  final class PanAttachmentView: UIView {
    weak var coordinator: Coordinator?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      if window == nil {
        coordinator?.detach()
      } else {
        coordinator?.attachIfNeeded()
      }
    }
  }

  @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var parent: CanvasPanGestureBridge
    weak var bridgeView: PanAttachmentView?
    private weak var hostView: UIView?
    private lazy var recognizer: UIPanGestureRecognizer = {
      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
      pan.minimumNumberOfTouches = 2
      pan.maximumNumberOfTouches = 2
      pan.allowedScrollTypesMask = .all
      pan.cancelsTouchesInView = false
      pan.delegate = self
      return pan
    }()

    init(_ parent: CanvasPanGestureBridge) {
      self.parent = parent
    }

    func attachIfNeeded() {
      guard let target = resolveHostView() else { return }
      if hostView !== target {
        detach()
        target.addGestureRecognizer(recognizer)
        hostView = target
      }
    }

    func detach() {
      hostView?.removeGestureRecognizer(recognizer)
      hostView = nil
    }

    private func resolveHostView() -> UIView? {
      guard let bridgeView, bridgeView.window != nil else { return nil }
      var candidate = bridgeView.superview
      var fallback: UIView?
      while let current = candidate, !(current is UIWindow) {
        if String(describing: type(of: current)).contains("Hosting") {
          return current
        }
        fallback = current
        candidate = current.superview
      }
      return fallback
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
      guard let hostView else { return }
      switch pan.state {
      case .began:
        parent.onBegan()
        let delta = pan.translation(in: hostView)
        pan.setTranslation(.zero, in: hostView)
        if delta != .zero {
          parent.onPan(CGSize(width: delta.x, height: delta.y))
        }
      case .changed:
        let delta = pan.translation(in: hostView)
        pan.setTranslation(.zero, in: hostView)
        if delta != .zero {
          parent.onPan(CGSize(width: delta.x, height: delta.y))
        }
      case .ended, .cancelled, .failed:
        parent.onEnded()
      default:
        break
      }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let bridge = bridgeView, parent.isEnabled, !bridge.isHidden, bridge.window != nil else { return false }
      return bridge.bounds.contains(gestureRecognizer.location(in: bridge))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      guard let bridge = bridgeView, parent.isEnabled, !bridge.isHidden, bridge.window != nil else { return false }
      if touch.view is UIControl || touch.view is UITextView { return false }
      return bridge.bounds.contains(touch.location(in: bridge))
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}
#endif
