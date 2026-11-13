import MotionCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// A dedicated create/update sheet with a constrained property picker and typed value controls.
struct EditPropertySheet: View {
  let key: String?
  let initialValue: JSONValue
  let isThree: Bool
  let onSave: (JSONValue) -> Void
  var onSaveKey: ((String, JSONValue) -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  init(key: String?, value: JSONValue, isThree: Bool = false, onSave: @escaping (JSONValue) -> Void,
       onSaveKey: ((String, JSONValue) -> Void)? = nil) {
    self.key = key
    self.isThree = isThree
    initialValue = value
    self.onSave = onSave
    self.onSaveKey = onSaveKey
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if key == nil {
          #if os(macOS)
          PropertyNamePicker(selection: $name)
            .frame(maxWidth: .infinity)
            .padding(20)
          #else
          Form { PropertyNamePicker(selection: $name) }
            .formStyle(.grouped)
            .frame(height: 100)
          #endif
        }
        if let definition = isThree ? StylePropertyDefinition.three(key ?? name) : StylePropertyDefinition.find(key ?? name) {
          PropertyValueForm(definition: definition, initialValue: key == nil ? definition.defaultValue : initialValue) { value in
            if key != nil { onSave(value) } else { onSaveKey?(definition.id, value) }
            dismiss()
          }
          .id(definition.id)
        } else {
          ContentUnavailableView("Choose a Property", systemImage: "slider.horizontal.3",
                                 description: Text("Type to search, then select a property from the list."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .navigationTitle(key.map { "Edit \($0)" } ?? "Add Property")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
    }
    #if os(macOS)
    .frame(minWidth: 440, idealWidth: 480, maxWidth: .infinity, minHeight: 380, idealHeight: 420, maxHeight: .infinity)
    #else
    .presentationDetents([.large])
    #endif
  }
}

private struct PropertyValueForm: View {
  let definition: StylePropertyDefinition
  let onSave: (JSONValue) -> Void
  @State private var text: String
  @State private var unit: String
  @State private var color: Color

  init(definition: StylePropertyDefinition, initialValue: JSONValue, onSave: @escaping (JSONValue) -> Void) {
    self.definition = definition
    self.onSave = onSave
    var text = initialValue.number.map(String.init(describing:)) ?? initialValue.string ?? ""
    if case .options(let choices) = definition.control, let number = initialValue.number,
       let choice = choices.first(where: { Double($0) == number }) {
      text = choice
    }
    var unit = "px"
    if case .length = definition.control {
      if text.hasSuffix("%") { text.removeLast(); unit = "%" }
      if text.hasSuffix("px") { text.removeLast(2) }
    }
    _text = State(initialValue: text)
    _unit = State(initialValue: unit)
    let rgba = StylePropertyDefinition.rgba(text) ?? [1, 1, 1, 1]
    _color = State(initialValue: Color(.sRGB, red: rgba[0], green: rgba[1], blue: rgba[2], opacity: rgba[3]))
  }

  private var value: JSONValue? { definition.value(text: text, unit: unit) }

  var body: some View {
    Form {
      switch definition.control {
      case .options(let choices):
        Picker("Value", selection: $text) {
          ForEach(choices, id: \.self) { Text($0).tag($0) }
        }
        .accessibilityIdentifier("property-options")
      case .color:
        ColorPicker("Color", selection: $color, supportsOpacity: true)
          .onChange(of: color) { _, color in text = hex(color) }
          .accessibilityIdentifier("property-color")
        valueField("Hex color")
      case .opacity:
        Slider(value: Binding(get: { Double(text) ?? 1 }, set: { text = String($0) }), in: 0...1) { Text("Opacity") }
          .accessibilityIdentifier("property-opacity")
        valueField("Opacity (0–1)")
      case .length:
        valueField("Value")
        Picker("Unit", selection: $unit) {
          Text("Pixels (px)").tag("px")
          Text("Percent (%)").tag("%")
        }
      case .number:
        valueField(definition.id == "fontSize" ? "Size (px)" : "Value")
      case .text:
        valueField(definition.id == "transform" ? "Transform, e.g. rotate(45deg)" : "Font family")
      }
      if value == nil { Text("Enter a valid value for \(definition.id).").font(.caption).foregroundStyle(.red) }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { if let value { onSave(value) } }
          .disabled(value == nil)
          .accessibilityIdentifier("save-property")
      }
    }
  }

  private func valueField(_ label: String) -> some View {
    TextField(label, text: $text)
      .autocorrectionDisabled()
      #if os(iOS)
      .textInputAutocapitalization(.never)
      #endif
      .accessibilityIdentifier("property-value")
  }

  private func hex(_ color: Color) -> String {
    #if os(macOS)
    let native = NSColor(color).usingColorSpace(.sRGB) ?? .white
    #else
    let native = UIColor(color)
    #endif
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
    native.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return String(format: "#%02x%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()),
                  Int((blue * 255).rounded()), Int((alpha * 255).rounded()))
  }
}

#if os(macOS)
/// Native editable combo box: typing filters the list; only a catalog choice becomes a selection.
private struct PropertyNamePicker: NSViewRepresentable {
  @Binding var selection: String

  func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

  func makeNSView(context: Context) -> NSComboBox {
    let combo = NSComboBox()
    combo.placeholderString = "Search properties…"
    combo.usesDataSource = true
    combo.dataSource = context.coordinator
    combo.delegate = context.coordinator
    combo.numberOfVisibleItems = 10
    combo.setAccessibilityLabel("Property")
    combo.setAccessibilityIdentifier("property-name")
    return combo
  }

  func updateNSView(_ combo: NSComboBox, context: Context) {
    context.coordinator.selection = $selection
  }

  final class Coordinator: NSObject, NSComboBoxDataSource, NSComboBoxDelegate {
    var selection: Binding<String>
    var matches = StylePropertyDefinition.all

    init(selection: Binding<String>) { self.selection = selection }

    func numberOfItems(in comboBox: NSComboBox) -> Int { matches.count }

    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? { matches[index].id }

    func controlTextDidChange(_ notification: Notification) {
      guard let combo = notification.object as? NSComboBox else { return }
      selection.wrappedValue = ""
      matches = StylePropertyDefinition.matching(combo.stringValue)
      combo.reloadData()
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
      guard let combo = notification.object as? NSComboBox,
            matches.indices.contains(combo.indexOfSelectedItem) else { return }
      selection.wrappedValue = matches[combo.indexOfSelectedItem].id
    }
  }
}
#else
private struct PropertyNamePicker: View {
  @Binding var selection: String
  @State private var query = ""

  var body: some View {
    NavigationLink {
      List(StylePropertyDefinition.matching(query)) { property in
        PropertyChoice(property: property.id, selection: $selection)
      }
      .searchable(text: $query, prompt: "Search properties")
      .navigationTitle("Property")
    } label: {
      LabeledContent("Property", value: selection.isEmpty ? "Choose…" : selection)
    }
    .accessibilityIdentifier("property-name")
  }
}

private struct PropertyChoice: View {
  let property: String
  @Binding var selection: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Button(property) { selection = property; dismiss() }
      .sensoryFeedback(.selection, trigger: selection)
  }
}
#endif
