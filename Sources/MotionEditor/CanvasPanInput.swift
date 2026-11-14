import SwiftUI

#if os(macOS)
import AppKit

/// Observe trackpad scrolling only inside the preview. Passing hit tests through keeps
/// selection, resize handles and text editing on the SwiftUI canvas interactive.
struct CanvasPanInput: NSViewRepresentable {
  var onPan: (CGSize) -> Void

  func makeNSView(context: Context) -> PanView { PanView() }
  func updateNSView(_ view: PanView, context: Context) { view.onPan = onPan }
  static func dismantleNSView(_ view: PanView, coordinator: ()) { view.stop() }

  final class PanView: NSView {
    var onPan: ((CGSize) -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stop()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        let handled = MainActor.assumeIsolated {
          guard let self, let window = self.window, event.window === window,
                !self.isHiddenOrHasHiddenAncestor,
                self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return false }
          // Precise deltas are trackpad points; wheel ticks need a useful point increment.
          let multiplier = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
          self.onPan?(CGSize(width: event.scrollingDeltaX * multiplier, height: event.scrollingDeltaY * multiplier))
          return true
        }
        return handled ? nil : event
      }
    }

    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
#elseif os(iOS)
import UIKit

/// A window recognizer receives two-touch pans without covering the canvas's controls.
struct CanvasPanInput: UIViewRepresentable {
  var onPan: (CGSize) -> Void
  var onActive: (Bool) -> Void = { _ in }

  func makeUIView(context: Context) -> PanView { PanView() }
  func updateUIView(_ view: PanView, context: Context) {
    view.onPan = onPan
    view.onActive = onActive
  }
  static func dismantleUIView(_ view: PanView, coordinator: ()) { view.stop() }

  final class PanView: UIView, UIGestureRecognizerDelegate {
    var onPan: ((CGSize) -> Void)?
    var onActive: ((Bool) -> Void)?
    private var pan: UIPanGestureRecognizer?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      stop()
      guard let window else { return }
      let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
      pan.minimumNumberOfTouches = 2
      pan.maximumNumberOfTouches = 2
      pan.delegate = self
      window.addGestureRecognizer(pan)
      self.pan = pan
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard !isHidden, window != nil else { return false }
      return bounds.contains(gestureRecognizer.location(in: self))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      // SwiftUI uses private recognizer types on some OS versions. Permit simultaneous
      // recognition so pan can accompany pinch/rotate; EditorCanvas suspends element drags.
      true
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
      onActive?(recognizer.state == .began || recognizer.state == .changed)
      let delta = recognizer.translation(in: window)
      recognizer.setTranslation(.zero, in: window)
      if recognizer.state == .began || recognizer.state == .changed {
        onPan?(CGSize(width: delta.x, height: delta.y))
      }
    }

    func stop() {
      if let pan { pan.view?.removeGestureRecognizer(pan) }
      pan = nil
    }
  }
}
#endif
