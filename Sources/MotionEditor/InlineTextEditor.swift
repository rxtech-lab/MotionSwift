import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A canvas-local editing surface; the rendered source changes only when the draft is committed.
struct InlineTextEditor: View {
  let model: EditorModel
  let target: EditorModel.TextEditTarget
  let scale: Double
  let zoom: Double
  let commit: Int
  let onClose: () -> Void
  @State private var text: String
  @State private var saving = false
  @State private var finished = false
  @State private var pendingSave = false
  @State private var error: String?

  init(model: EditorModel, target: EditorModel.TextEditTarget, scale: Double, zoom: Double,
       commit: Int, onClose: @escaping () -> Void) {
    self.model = model
    self.target = target
    self.scale = scale
    self.zoom = zoom
    self.commit = commit
    self.onClose = onClose
    _text = State(initialValue: target.text)
  }

  var body: some View {
    CanvasTextInput(text: $text, fontSize: max(14 / zoom, target.fontSize * scale), onSave: save, onCancel: cancel)
      .disabled(saving)
      .accessibilityIdentifier("inline-text-content")
    .background { glassBackground }
    .clipShape(RoundedRectangle(cornerRadius: 8 / zoom))
    .overlay(RoundedRectangle(cornerRadius: 8 / zoom).stroke(Color.accentColor, lineWidth: 2 / zoom))
    .overlay {
      if saving { ProgressView("Saving text…").padding().background(.regularMaterial) }
    }
    .overlay(alignment: .top) {
      if let error {
        Text(error).font(.caption).padding(8).background(.regularMaterial)
      }
    }
    .onChange(of: commit) { _, _ in save() }
    .onChange(of: model.status) { _, status in
      if status == .idle, pendingSave { pendingSave = false; save() }
    }
    .sensoryFeedback(.success, trigger: model.commitFeedback)
    .sensoryFeedback(.error, trigger: error)
  }

  @ViewBuilder private var glassBackground: some View {
    let shape = RoundedRectangle(cornerRadius: 8 / zoom)
    if #available(macOS 26, iOS 26, *) {
      Color.clear.glassEffect(.regular, in: shape)
    } else {
      shape.fill(.ultraThinMaterial)
    }
  }

  private func cancel() {
    guard !saving, !finished else { return }
    finished = true
    onClose()
  }

  private func save() {
    guard !saving, !finished else { return }
    if text == target.text { finished = true; onClose(); return }
    guard model.status == .idle else { pendingSave = true; return }
    saving = true
    error = nil
    Task {
      let saved = await model.setText(text, source: target.source, expectedSource: target.expectedSource, requiresSelection: false)
      saving = false
      if saved { finished = true; onClose() } else { error = model.notice?.message ?? "Could not save text. Please try again." }
    }
  }
}

#if os(macOS)
private struct CanvasTextInput: NSViewRepresentable {
  @Binding var text: String
  let fontSize: Double
  let onSave: () -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.drawsBackground = false
    scroll.contentView.drawsBackground = false
    guard let view = scroll.documentView as? NSTextView else { return scroll }
    view.isRichText = false
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.font = .systemFont(ofSize: fontSize)
    view.textColor = .labelColor
    view.drawsBackground = false
    view.backgroundColor = .clear
    view.string = text
    view.delegate = context.coordinator
    context.coordinator.watchClicks(outside: view)
    view.setAccessibilityLabel("Edit text inline")
    view.setAccessibilityIdentifier("inline-text-content")
    DispatchQueue.main.async {
      view.window?.makeFirstResponder(view)
      view.selectAll(nil)
    }
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
  }

  static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) { coordinator.stop() }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: CanvasTextInput
    private var mouseMonitor: Any?
    private var active = true

    func watchClicks(outside view: NSTextView) {
      mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak view] event in
        let location = event.locationInWindow
        let windowNumber = event.windowNumber
        // AppKit delivers local event monitors synchronously on the main thread.
        MainActor.assumeIsolated {
          guard let self, self.active, let view, let window = view.window else { return }
          let area = view.enclosingScrollView ?? view
          let point = area.convert(location, from: nil)
          if windowNumber != window.windowNumber || !area.bounds.contains(point) {
            view.unmarkText()
            self.parent.text = view.string
            self.parent.onSave()
          }
        }
        return event
      }
    }

    func stop() {
      active = false
      if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
      mouseMonitor = nil
    }

    init(_ parent: CanvasTextInput) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      parent.text = view.string
    }

    func textDidEndEditing(_ notification: Notification) {
      guard active else { return }
      if let view = notification.object as? NSTextView { parent.text = view.string }
      parent.onSave()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        stop()
        parent.onCancel()
        return true
      }
      if commandSelector == #selector(NSResponder.insertNewline(_:)), NSEvent.modifierFlags.contains(.command) {
        // Commit marked IME text before saving a Chinese/Japanese composition.
        textView.unmarkText()
        parent.text = textView.string
        parent.onSave()
        return true
      }
      return false
    }
  }
}
#else
private struct CanvasTextInput: UIViewRepresentable {
  @Binding var text: String
  let fontSize: Double
  let onSave: () -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> UITextView {
    let view = CanvasNativeTextView()
    view.backgroundColor = .clear
    view.isOpaque = false
    view.onSave = { [weak view] in
      guard let view else { return }
      view.unmarkText()
      context.coordinator.parent.text = view.text
      context.coordinator.parent.onSave()
    }
    view.onCancel = {
      context.coordinator.cancelled = true
      context.coordinator.parent.onCancel()
    }
    view.font = .systemFont(ofSize: fontSize)
    view.text = text
    view.delegate = context.coordinator
    view.accessibilityLabel = "Edit text inline"
    view.accessibilityIdentifier = "inline-text-content"
    DispatchQueue.main.async {
      view.becomeFirstResponder()
      view.selectAll(nil)
    }
    return view
  }

  func updateUIView(_ view: UITextView, context: Context) { context.coordinator.parent = self }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: CanvasTextInput
    var cancelled = false
    init(_ parent: CanvasTextInput) { self.parent = parent }
    func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
    func textViewDidEndEditing(_ textView: UITextView) {
      guard !cancelled else { return }
      parent.text = textView.text
      parent.onSave()
    }
  }
}

private final class CanvasNativeTextView: UITextView {
  var onSave: (() -> Void)?
  var onCancel: (() -> Void)?

  override var keyCommands: [UIKeyCommand]? {
    (super.keyCommands ?? []) + [
      UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(saveDraft)),
      UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelDraft)),
    ]
  }

  @objc private func saveDraft() { onSave?() }
  @objc private func cancelDraft() { onCancel?() }
}
#endif

extension EditorModel {
  /// A canvas draft captures its source version so later edits cannot overwrite newer work.
  struct TextEditTarget: Identifiable {
    let id = UUID()
    let source: String
    let expectedSource: String
    let text: String
    let rect: CGRect
    let fontSize: Double
  }

}
