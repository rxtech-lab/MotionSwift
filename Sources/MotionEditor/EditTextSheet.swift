import SwiftUI

/// Dedicated text update view. Drafts do not touch the film until Save succeeds.
struct EditTextSheet: View {
  let title: LocalizedStringKey
  let note: String?
  let save: (String) async -> Bool
  let model: EditorModel
  @Environment(\.dismiss) private var dismiss
  @State private var text: String
  @State private var saving = false
  @State private var error: String?

  /// Edits the element's own literal children.
  init(model: EditorModel, source: String, expectedSource: String, text: String) {
    self.init(model: model, title: "Edit Text", text: text,
              note: model.selectionInstances > 1 ? "This source element is reused. Changes apply to every instance." : nil) {
      await model.setText($0, source: source, expectedSource: expectedSource)
    }
  }

  init(model: EditorModel, title: LocalizedStringKey, text: String, note: String?, save: @escaping (String) async -> Bool) {
    self.model = model
    self.title = title
    self.note = note
    self.save = save
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
        if let note {
          Text(note).font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .navigationTitle(title)
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
              let saved = await save(text)
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
