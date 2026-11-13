import SwiftUI

/// Dedicated text update view. Drafts do not touch the film until Save succeeds.
struct EditTextSheet: View {
  let model: EditorModel
  let source: String
  let expectedSource: String
  @Environment(\.dismiss) private var dismiss
  @State private var text: String
  @State private var saving = false
  @State private var error: String?

  init(model: EditorModel, source: String, expectedSource: String, text: String) {
    self.model = model
    self.source = source
    self.expectedSource = expectedSource
    _text = State(initialValue: text)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        Text("Text Content").font(.headline)
        TextEditor(text: $text)
          .font(.body)
          .accessibilityLabel("Text content")
          .accessibilityIdentifier("text-content")
          .border(.quaternary)
        if model.selectionInstances > 1 {
          Text("This source element is reused. Changes apply to every instance.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .navigationTitle("Edit Text")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(saving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            saving = true
            error = nil
            Task {
              let saved = await model.setText(text, source: source, expectedSource: expectedSource)
              saving = false
              if saved { dismiss() } else { error = model.notice?.message ?? "Could not save text. Please try again." }
            }
          }
          .disabled(saving || model.status != .idle)
          .accessibilityIdentifier("save-text")
        }
      }
      .overlay {
        if saving {
          ProgressView("Saving text…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
      }
      .overlay(alignment: .bottom) {
        if let error {
          Text(error).font(.callout).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
        }
      }
      .sensoryFeedback(.success, trigger: model.commitFeedback)
      .sensoryFeedback(.error, trigger: error)
    }
    .interactiveDismissDisabled(saving)
    #if os(macOS)
    .frame(minWidth: 480, idealWidth: 540, maxWidth: .infinity, minHeight: 400, idealHeight: 460, maxHeight: .infinity)
    #else
    .presentationDetents([.large])
    #endif
  }
}
