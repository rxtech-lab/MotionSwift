import MotionCore
import MotionPortable
import SwiftUI

/// Properties of the selection, classified from source. Static values open the Edit Property
/// sheet; animated, bound and computed values are read-only with an explanation.
struct EditorInspector: View {
  let model: EditorModel
  @State private var editing: StyleSummary.Property?
  @State private var adding = false
  @State private var removing: StyleSummary.Property?

  var body: some View {
    Form {
      if let selection = model.selection {
        Section("Element") {
          LabeledContent("Source", value: selection)
          if model.selectionInstances > 1 {
            LabeledContent("Instances", value: "\(model.selectionInstances) (edits apply to all)")
          }
          if let box = model.selectedBox {
            LabeledContent("Box", value: "\(format(box.x)), \(format(box.y)) · \(format(box.width))×\(format(box.height))")
          } else {
            Text("Object is outside the playhead's visible range").font(.caption).foregroundStyle(.secondary)
          }
        }
        Section {
          if let styles = model.styles {
            if !styles.editable {
              Text("The style prop is an expression. Edit it in code.").foregroundStyle(.secondary)
            }
            ForEach(styles.properties) { property in row(property) }
          } else {
            ProgressView()
          }
        } header: {
          HStack {
            Text("Style")
            Spacer()
            Button("Add Property", systemImage: "plus") { adding = true }
              .labelStyle(.iconOnly)
              .disabled(model.styles?.editable != true)
              .accessibilityIdentifier("add-property")
          }
        }
      } else {
        ContentUnavailableView(
          "No Selection", systemImage: "cursorarrow.click",
          description: Text("Tap an element on the canvas to inspect and edit it."))
      }
    }
    .formStyle(.grouped)
    .sheet(item: $editing) { property in
      EditPropertySheet(key: property.key, value: model.currentStyleValue(property.key) ?? property.value ?? .string("")) { value in
        Task { await model.setStyle(property.key, value) }
      }
    }
    .sheet(isPresented: $adding) {
      EditPropertySheet(key: nil, value: .number(0)) { _ in }
        onSaveKey: { key, value in Task { await model.setStyle(key, value) } }
    }
    .confirmationDialog(
      "Remove \(removing?.key ?? "property")?", isPresented: Binding(
        get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible, presenting: removing
    ) { property in
      Button("Remove \(property.key)", role: .destructive) { Task { await model.removeStyle(property.key) } }
    } message: { property in
      Text("Deletes \(property.key) from the element's style in \(SourceStamp(model.selection ?? "")?.file ?? "the source").")
    }
  }

  @ViewBuilder private func row(_ property: StyleSummary.Property) -> some View {
    let animated = model.selectedTrack?.keyframes[property.key] != nil
    let editable = property.kind == .static
    Button {
      if editable { editing = property }
    } label: {
      HStack {
        Text(property.key)
        Spacer()
        Text(animated ? (model.currentStyleValue(property.key)?.number?.formatted() ?? property.raw ?? "") : property.raw ?? "")
          .font(.callout.monospaced()).lineLimit(1).foregroundStyle(.secondary)
        if !editable || animated {
          Text(animated ? "keyframes" : property.kind.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help(property))
    .contextMenu {
      if editable {
        Button("Edit…", systemImage: "pencil") { editing = property }
        if !animated { Button("Remove…", systemImage: "trash", role: .destructive) { removing = property } }
      }
    }
    .swipeActions {
      if editable && !animated { Button("Remove", systemImage: "trash", role: .destructive) { removing = property } }
    }
  }

  private func help(_ property: StyleSummary.Property) -> String {
    switch property.kind {
    case .static: return "Edit the literal in source"
    case .animated: return "Animated: edit keyframes on the timeline"
    case .bound: return "Bound to a variable: edit its definition in code"
    case .computed: return "Computed: edit it in code"
    }
  }

  private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}

/// The dedicated sheet for creating or updating one style property.
struct EditPropertySheet: View {
  let key: String?
  let onSave: (JSONValue) -> Void
  var onSaveKey: ((String, JSONValue) -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var text: String
  @State private var isNumber: Bool

  init(key: String?, value: JSONValue, onSave: @escaping (JSONValue) -> Void,
       onSaveKey: ((String, JSONValue) -> Void)? = nil) {
    self.key = key
    self.onSave = onSave
    self.onSaveKey = onSaveKey
    _isNumber = State(initialValue: value.number != nil)
    _text = State(initialValue: value.number.map { $0.formatted(.number.grouping(.never)) } ?? value.string ?? "")
  }

  private var value: JSONValue? {
    if isNumber { return Double(text.trimmingCharacters(in: .whitespaces)).map(JSONValue.number) }
    return .string(text)
  }

  private var validName: Bool {
    key != nil || name.range(of: "^[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) != nil
  }

  var body: some View {
    NavigationStack {
      Form {
        if key == nil {
          TextField("Property (camelCase, e.g. borderRadius)", text: $name)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        }
        Picker("Type", selection: $isNumber) {
          Text("Number (px)").tag(true)
          Text("Text").tag(false)
        }
        .pickerStyle(.segmented)
        TextField(isNumber ? "Value" : "Value, e.g. #fca311 or 50%", text: $text)
          .autocorrectionDisabled()
          #if os(iOS)
          .keyboardType(isNumber ? .decimalPad : .default)
          .textInputAutocapitalization(.never)
          #endif
          .accessibilityIdentifier("property-value")
        if isNumber, !text.isEmpty, value == nil { Text("Enter a number").foregroundStyle(.red) }
      }
      .formStyle(.grouped)
      .navigationTitle(key.map { "Edit \($0)" } ?? "Add Property")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard let value else { return }
            if key != nil { onSave(value) } else { onSaveKey?(name, value) }
            dismiss()
          }
          .disabled(value == nil || !validName)
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 420, idealWidth: 460, maxWidth: .infinity, minHeight: 300, idealHeight: 340, maxHeight: .infinity)
    #else
    .presentationDetents([.medium, .large])
    #endif
  }
}
