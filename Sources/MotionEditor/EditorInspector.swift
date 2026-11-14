import MotionCore
import MotionPortable
import SwiftUI

/// Properties of the selection, classified from source. Static values and map props open the Edit
/// Property sheet; other animated, bound and computed values are read-only with an explanation.
struct EditorInspector: View {
  let model: EditorModel
  @State private var editing: StyleSummary.Property?
  @State private var adding = false
  @State private var textDraft: TextDraft?

  private struct TextDraft: Identifiable {
    let id = UUID()
    let selection: String
    let source: String
    let text: String
  }
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
        if let content = model.textContent, model.canEditText || content.reason != nil {
          Section("Text Content") {
            if model.canEditText {
              Text(model.selectedTextValue).lineLimit(4)
              Button("Edit Text…", systemImage: "text.cursor") {
                if let stamp = SourceStamp(selection), let source = model.files[stamp.file] {
                  textDraft = TextDraft(selection: selection, source: source, text: model.selectedTextValue)
                }
              }
                .disabled(model.status != .idle)
                .accessibilityIdentifier("edit-text")
            } else if let reason = content.reason {
              Text(reason).font(.callout).foregroundStyle(.secondary)
            }
          }
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
    .sheet(item: $textDraft) { draft in
      EditTextSheet(model: model, source: draft.selection, expectedSource: draft.source, text: draft.text)
    }
    .sheet(item: $editing) { property in
      EditPropertySheet(key: property.key, value: model.currentStyleValue(property.key) ?? property.value ?? .string(""),
                        isThree: model.styles?.isThree == true, definition: mapDefinition(property.key)) { value in
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
    let definition = mapDefinition(property.key) ?? (model.styles?.isThree == true
      ? StylePropertyDefinition.three(property.key) : StylePropertyDefinition.find(property.key))
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
