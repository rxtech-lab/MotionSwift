import MapKit
import MotionCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: Controls

struct CoordinateFields: View {
  @Binding var longitude: Double
  @Binding var latitude: Double

  var body: some View {
    TextField("Latitude", value: $latitude, format: .number.precision(.fractionLength(0...6)))
      .accessibilityIdentifier("latitude")
    TextField("Longitude", value: $longitude, format: .number.precision(.fractionLength(0...6)))
      .accessibilityIdentifier("longitude")
  }
}

struct LabeledSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let format: (Double) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title)
        Spacer()
        Text(format(value)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
      }
      Slider(value: $value, in: range, step: step) { Text(title) }.labelsHidden()
    }
  }
}

struct HexColorPicker: View {
  let title: String
  @Binding var hex: String

  var body: some View {
    ColorPicker(title, selection: Binding(get: {
      let rgba = StylePropertyDefinition.rgba(hex) ?? [1, 1, 1, 1]
      return Color(.sRGB, red: rgba[0], green: rgba[1], blue: rgba[2], opacity: rgba[3])
    }, set: { hex = Self.hex($0) }), supportsOpacity: false)
  }

  static func hex(_ color: Color) -> String {
    #if os(macOS)
    let native = NSColor(color).usingColorSpace(.sRGB) ?? .white
    #else
    let native = UIColor(color)
    #endif
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
    native.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
  }
}

/// Searches places with MapKit and hands back the chosen coordinate (and name).
struct PlaceSearchField: View {
  let prompt: String
  let onSelect: (Double, Double, String) -> Void
  @State private var query = ""
  @State private var results: [MKMapItem] = []
  @State private var searching = false
  @State private var failure: String?

  init(prompt: String, onSelect: @escaping (Double, Double) -> Void) {
    self.prompt = prompt
    self.onSelect = { longitude, latitude, _ in onSelect(longitude, latitude) }
  }

  init(prompt: String, onSelect: @escaping (Double, Double, String) -> Void) {
    self.prompt = prompt
    self.onSelect = onSelect
  }

  var body: some View {
    HStack {
      TextField(prompt, text: $query)
        .autocorrectionDisabled()
        .onSubmit { search() }
        .accessibilityIdentifier("place-search")
      if searching { ProgressView().controlSize(.small) } else {
        Button("Search", systemImage: "magnifyingglass") { search() }
          .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
    ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { _, item in
      Button {
        let coordinate = item.placemark.coordinate
        let name = item.name ?? query
        onSelect(EditorModel.coordinate(coordinate.longitude), EditorModel.coordinate(coordinate.latitude), name)
        results = []
        query = item.name ?? query
      } label: {
        VStack(alignment: .leading) {
          Text(item.name ?? "Place")
          if let detail = item.placemark.title, detail != item.name {
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
        }
      }
      .buttonStyle(.plain)
    }
  }

  private func search() {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    searching = true
    failure = nil
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = text
    Task {
      defer { searching = false }
      do {
        results = try await MKLocalSearch(request: request).start().mapItems
        if results.isEmpty { failure = "No places found" }
      } catch {
        results = []
        failure = "Search is unavailable: \(error.localizedDescription)"
      }
    }
  }
}
