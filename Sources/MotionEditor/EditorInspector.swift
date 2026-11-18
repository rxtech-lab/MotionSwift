import MotionCore
import MotionPortable
import SwiftUI

/// What a text sheet writes: the element's literal children, one traced literal, or fixed text.
private enum TextDraftTarget { case children, field(TextSummary.Field), replacement }

/// Properties of the selection, classified from source. Static values and map props open the Edit
/// Property sheet; other animated, bound and computed values are read-only with an explanation.
/// Public so hosts can show it in their own inspector panel next to an `EditorCanvas`, or with the
/// selection driven from `EditorModel.selectTrack(_:)`.
public struct EditorInspector: View {
  let model: EditorModel
  /// Opens the source at a line, for text that only code can change. Hidden when nil.
  let onEditCode: ((SourceStamp) -> Void)?
  @State private var editing: StyleSummary.Property?
  @State private var adding = false
  @State private var textDraft: TextDraft?
  @State private var confirmingReplace = false

  private struct TextDraft: Identifiable {
    let id = UUID()
    let selection: String
    let source: String
    let text: String
    let target: TextDraftTarget
  }
  @State private var removing: StyleSummary.Property?

  public init(model: EditorModel, onEditCode: ((SourceStamp) -> Void)? = nil) {
    self.model = model
    self.onEditCode = onEditCode
  }

  public var body: some View {
    Form {
      if let selection = model.selection {
        Section("Element") {
          LabeledContent("Source", value: selection)
          if model.selectionInstances > 1 {
            LabeledContent("Instances", value: "\(model.selectionInstances) (edits apply to all)")
          }
          if let box = model.selectedBox {
            LabeledContent("Box", value: "\(format(box.x)), \(format(box.y)) · \(format(box.width))×\(format(box.height))")
          } else if model.styles?.isMap == true {
            Text("Map props use degrees (longitude, latitude) and Web Mercator zoom.")
              .font(.caption).foregroundStyle(.secondary)
          } else if model.styles?.isThree == true {
            Text("Select 3D objects and materials in the timeline. Position uses scene units; rotation uses radians. "
                 + "Repeated instances share source edits.")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Text("Object is outside the playhead's visible range").font(.caption).foregroundStyle(.secondary)
          }
        }
        if let content = model.textContent,
           model.canEditText || content.reason != nil || !content.fields.isEmpty || content.canReplace {
          textSection(content, selection: selection)
        }
        MapInspectorSection(model: model)
        Section {
          if let styles = model.styles {
            if !styles.editable {
              Text("The style prop is an expression. Edit it in code.").foregroundStyle(.secondary)
            }
          } else {
            ProgressView()
          }
        } header: {
          HStack {
            Text(model.styles?.isMap == true ? "Map Properties" : model.styles?.isThree == true ? "3D Properties" : "Style")
            Spacer()
            Button("Add Property", systemImage: "plus") { adding = true }
              .labelStyle(.iconOnly)
              .disabled(model.styles?.editable != true || model.styles?.isPropDomain == true)
              .accessibilityIdentifier("add-property")
          }
        }
        if let styles = model.styles {
          ForEach(Array(Set(model.detectedStyleProperties.map { styles.group(for: $0.key) })).sorted(), id: \.self) { group in
            Section(group) {
              ForEach(model.detectedStyleProperties.filter { styles.group(for: $0.key) == group }) { property in row(property) }
            }
          }
        }
      } else {
        ContentUnavailableView(
          "No Selection", systemImage: "cursorarrow.click",
          description: Text("Select an object on the timeline or tap a canvas element to inspect and edit it."))
      }
    }
    .formStyle(.grouped)
    .sheet(item: $textDraft) { draft in textSheet(draft) }
    .confirmationDialog("Replace generated text?", isPresented: $confirmingReplace, titleVisibility: .visible) {
      Button("Replace with Fixed Text…") { draft(.replacement, text: model.selectedRenderedText) }
    } message: {
      Text("The text will no longer follow its code. Undo restores the code.")
    }
    .sheet(item: $editing) { property in
      let current = model.currentStyleValue(property.key) ?? property.value
      EditPropertySheet(key: property.key, value: current ?? .string(""),
                        isThree: model.styles?.isThree == true, definition: propertyDefinition(property)) { value in
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
    let definition = propertyDefinition(property)
    let editable = (property.kind == .static || model.styles?.isMap == true) && definition != nil
    Button {
      if editable { editing = property }
    } label: {
      HStack {
        Text(model.styles?.isMap == true ? MapCatalog.label(for: property.key) : model.styles?.label(for: property.key) ?? property.key)
        Spacer()
        Text(valueText(property))
          .font(.callout.monospaced()).lineLimit(1).foregroundStyle(.secondary)
        if !editable || animated || property.kind != .static {
          Text(animated ? "keyframes" : property.kind == .static ? "code" : property.kind.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!editable)
    .help(help(property, definition: definition))
    .contextMenu {
      if editable {
        Button("Edit…", systemImage: "pencil") { editing = property }
        if !animated && model.styles?.isPropDomain != true {
          Button("Remove…", systemImage: "trash", role: .destructive) { removing = property }
        }
      }
    }
    .swipeActions {
      if editable && !animated && model.styles?.isPropDomain != true {
        Button("Remove", systemImage: "trash", role: .destructive) { removing = property }
      }
    }
  }

  private func propertyDefinition(_ property: StyleSummary.Property) -> StylePropertyDefinition? {
    if let map = mapDefinition(property.key) { return map }
    if model.styles?.isThree == true { return StylePropertyDefinition.three(property.key) }
    if model.styles?.group(for: property.key) == "Component Props" {
      return StylePropertyDefinition.component(property.key, value: model.currentStyleValue(property.key) ?? property.value)
    }
    return StylePropertyDefinition.find(property.key)
  }

  private func mapDefinition(_ key: String) -> StylePropertyDefinition? {
    guard model.styles?.isMap == true else { return nil }
    let provider = model.mapView(containing: model.selection ?? "")?.properties["provider"]?.string
    return StylePropertyDefinition.map(key, provider: provider)
  }

  private func help(_ property: StyleSummary.Property, definition: StylePropertyDefinition?) -> String {
    if definition == nil {
      return "This property has no visual control yet; edit its value in code"
    }
    if model.styles?.isMap == true, property.kind != .static {
      return "Controlled by code — click to override on the map (Undo restores the expression)"
    }
    switch property.kind {
    case .static: return "Edit the literal in source"
    case .animated: return "Animated: edit keyframes on the timeline"
    case .bound: return "Bound to a variable: edit its definition in code"
    case .computed: return "Computed: edit it in code"
    }
  }

  private func valueText(_ property: StyleSummary.Property) -> String {
    let value = model.currentStyleValue(property.key) ?? property.value
    return value?.number?.formatted() ?? value?.string ?? property.raw ?? ""
  }

  private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}

extension EditorInspector {
  // MARK: Text

  @ViewBuilder private func textSection(_ content: TextSummary, selection: String) -> some View {
    Section {
      if model.canEditText {
        Text(model.selectedTextValue).lineLimit(4)
        Button("Edit Text…", systemImage: "text.cursor") { draft(.children, text: model.selectedTextValue) }
          .disabled(model.status != .idle)
          .accessibilityIdentifier("edit-text")
      } else if !content.fields.isEmpty {
        ForEach(content.fields) { field in
          Button { draft(.field(field), text: field.value) } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(field.value.isEmpty ? "Empty" : field.value).lineLimit(3)
                Text(detail(field)).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "pencil").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(model.status != .idle)
          .help(field.shared ? "Written at line \(field.line); every element that uses it changes" : "Written at line \(field.line)")
          .accessibilityIdentifier("edit-text-field")
        }
      } else if let reason = content.reason {
        Text(reason).font(.callout).foregroundStyle(.secondary)
      }
      if !model.canEditText, content.canReplace {
        Button("Replace with Fixed Text…", systemImage: "character.cursor.ibeam") { confirmingReplace = true }
          .disabled(model.status != .idle)
          .accessibilityIdentifier("replace-text")
      }
      if let onEditCode, !model.canEditText, let stamp = codeStamp(content, selection: selection) {
        Button("Edit in Code…", systemImage: "chevron.left.forwardslash.chevron.right") { onEditCode(stamp) }
          .accessibilityIdentifier("edit-text-code")
      }
    } header: {
      Text("Text Content")
    } footer: {
      if !model.canEditText, !content.fields.isEmpty {
        Text("Code builds this text. Each part is edited where it is written.")
      }
    }
  }

  /// Where to open the code: the one literal behind the text, otherwise the element.
  private func codeStamp(_ content: TextSummary, selection: String) -> SourceStamp? {
    guard let stamp = SourceStamp(selection) else { return nil }
    guard content.fields.count == 1, let field = content.fields.first else { return stamp }
    return SourceStamp("\(stamp.file):\(field.line):1")
  }

  private func detail(_ field: TextSummary.Field) -> String {
    var parts = [field.label == "Text" ? "Text" : field.label, "line \(field.line)"]
    if field.shared { parts.append("shared") }
    if field.transformed { parts.append("changed by code") }
    return parts.joined(separator: " · ")
  }

  private func draft(_ target: TextDraftTarget, text: String) {
    guard let selection = model.selection, let stamp = SourceStamp(selection), let source = model.files[stamp.file] else { return }
    textDraft = TextDraft(selection: selection, source: source, text: text, target: target)
  }

  @ViewBuilder private func textSheet(_ draft: TextDraft) -> some View {
    switch draft.target {
    case .children:
      EditTextSheet(model: model, source: draft.selection, expectedSource: draft.source, text: draft.text)
    case .field(let field):
      EditTextSheet(model: model, title: "Edit \(field.label)", text: draft.text, note: note(for: field)) {
        await model.setTextField(field, to: $0, source: draft.selection, expectedSource: draft.source)
      }
    case .replacement:
      EditTextSheet(model: model, title: "Replace Text", text: draft.text,
                    note: "Replaces the code that generates this text. Undo restores it.") {
        await model.replaceText(with: $0, source: draft.selection, expectedSource: draft.source)
      }
    }
  }

  private func note(for field: TextSummary.Field) -> String? {
    var notes: [String] = []
    if field.shared { notes.append("Written at line \(field.line). Every element that uses it changes.") }
    if field.transformed { notes.append("Code changes this text before showing it, for example its case or spacing.") }
    return notes.isEmpty ? nil : notes.joined(separator: " ")
  }
}
