import MapKit
import MotionCore
import MotionPortable
import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: Canvas

/// Route endpoints and marker handles of the selected map element, drawn over the canvas.
/// Drags are handled by the canvas gesture (`beginMapDrag`), so this layer is not hit-testable.
struct MapHandlesOverlay: View {
  let model: EditorModel
  let scale: Double
  let zoom: Double

  var body: some View {
    let handles = model.mapHandles
    ZStack(alignment: .topLeading) {
      if handles.count == 2 {
        Path { path in
          path.move(to: scaled(handles[0].point))
          path.addLine(to: scaled(handles[1].point))
        }
        .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5 / zoom, dash: [5 / zoom, 4 / zoom]))
      }
      ForEach(Array(handles.enumerated()), id: \.offset) { _, handle in
        let label = handle.kind == .routeStart ? "A" : handle.kind == .routeEnd ? "B" : nil
        ZStack {
          Circle().fill(.white)
          Circle().stroke(Color.accentColor, lineWidth: 2.5 / zoom)
          if let label {
            Text(label).font(.system(size: 10 / zoom, weight: .bold)).foregroundStyle(Color.accentColor)
          }
        }
        .frame(width: 20 / zoom, height: 20 / zoom)
        .shadow(radius: 2 / zoom)
        .position(scaled(handle.point))
        .accessibilityLabel(handle.kind == .routeStart ? "Route start" : handle.kind == .routeEnd ? "Route end" : "Marker")
      }
    }
    .allowsHitTesting(false)
  }

  private func scaled(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * scale, y: point.y * scale) }
}

/// Floating map controls: zoom, rotation, framing and map settings for the active map.
struct MapToolbarOverlay: View {
  let model: EditorModel
  @State private var editingMap: Scene3D.EditorElement?

  var body: some View {
    let map = model.activeMapView
    VStack(alignment: .trailing, spacing: 6) {
      HStack(spacing: 2) {
        Label("Map", systemImage: "map.fill").font(.callout.weight(.semibold)).padding(.trailing, 6)
        button("Zoom Out", "minus.magnifyingglass") { await model.nudgeMap(zoom: -0.5) }
        button("Zoom In", "plus.magnifyingglass") { await model.nudgeMap(zoom: 0.5) }
        button("Rotate Left", "rotate.left") { await model.nudgeMap(bearing: -15) }
        button("Rotate Right", "rotate.right") { await model.nudgeMap(bearing: 15) }
        button("Reset North", "location.north.line") { await model.resetMapBearing() }
          .disabled((map?.properties["bearing"]?.number ?? 0) == 0)
        if ["MapRoute", "MapMarker"].contains(model.selectedMapElement?.type) {
          button("Frame on Map", "viewfinder") { await model.frameSelectionOnMap() }
        }
        Button("Map Settings…", systemImage: "slider.horizontal.3") {
          if model.selection == nil, let map, let track = model.objectTracks.first(where: { $0.src == map.source }) {
            model.selectTrack(track)
          }
          editingMap = map
        }
          .labelStyle(.iconOnly).buttonStyle(.borderless).help("Map Settings…")
          .accessibilityIdentifier("map-settings")
      }
      if let map {
        Text(summary(map)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
      }
      Text(model.mapHandles.isEmpty ? "Drag the map to pan" : "Drag handles to move · drag the map to pan")
        .font(.caption2).foregroundStyle(.secondary)
    }
    .padding(10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    .shadow(radius: 8, y: 2)
    .disabled(model.status != .idle)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("map-overlay")
    .sheet(item: $editingMap) { map in MapSettingsSheet(model: model, map: map) }
  }

  private func button(_ title: String, _ symbol: String, action: @escaping () async -> Void) -> some View {
    Button(title, systemImage: symbol) { Task { await action() } }
      .labelStyle(.iconOnly).buttonStyle(.borderless).help(title)
  }

  private func summary(_ map: Scene3D.EditorElement) -> String {
    let props = map.properties
    let number = { (key: String, digits: Int) in
      (props[key]?.number ?? 0).formatted(.number.precision(.fractionLength(digits)))
    }
    let provider = MapCatalog.provider(props["effectiveProvider"]?.string).label
    return "\(number("centerLatitude", 4)), \(number("centerLongitude", 4)) · z\(number("zoom", 1)) · \(provider)"
  }
}

extension Scene3D.EditorElement: Identifiable {
  public var id: String { source }
}

// MARK: Inspector

/// Map actions for the selected `<MapView>`, `<MapRoute>` or `<MapMarker>`.
struct MapInspectorSection: View {
  let model: EditorModel
  @State private var sheet: MapSheet?
  @State private var deleting = false
  @State private var journeySeconds = 4.0

  enum MapSheet: Identifiable {
    case map(Scene3D.EditorElement), route(MapRouteDraft), marker(MapMarkerDraft)
    var id: String {
      switch self {
      case .map(let map): "map:\(map.source)"
      case .route(let draft): "route:\(draft.source ?? "new")"
      case .marker(let draft): "marker:\(draft.source ?? "new")"
      }
    }
  }

  var body: some View {
    if let element = model.selectedMapElement {
      Section {
        if let status = model.mapStatus {
          Label(status, systemImage: element.properties["routePending"] != nil ? "hourglass" : "exclamationmark.triangle")
            .font(.callout).foregroundStyle(element.properties["routePending"] != nil ? Color.secondary : Color.orange)
        }
        switch element.type {
        case "MapView":
          action("Map Settings…", "slider.horizontal.3", id: "edit-map") { sheet = .map(element) }
        case "MapRoute":
          action("Edit Route…", "point.topleft.down.to.point.bottomright.curvepath", id: "edit-route") {
            sheet = .route(MapRouteDraft(element))
          }
          action("Frame Route", "viewfinder", id: "frame-route") { Task { await model.frameSelectionOnMap() } }
          journey
          if let source = element.properties["routeSource"]?.string {
            Text(source).font(.caption).foregroundStyle(.secondary)
          }
        case "MapMarker":
          action("Edit Marker…", "mappin.and.ellipse", id: "edit-marker") { sheet = .marker(MapMarkerDraft(element)) }
          action("Frame Marker", "viewfinder", id: "frame-marker") { Task { await model.frameSelectionOnMap() } }
        default: EmptyView()
        }
        if element.type != "MapView", let map = model.mapView(containing: element.source) {
          action("Map Settings…", "map", id: "edit-parent-map") { sheet = .map(map) }
        }
        action("Add Route…", "plus.circle", id: "add-route") { sheet = .route(MapRouteDraft(adding: model)) }
        action("Add Marker…", "mappin.circle", id: "add-marker") { sheet = .marker(MapMarkerDraft(adding: model)) }
        if element.type != "MapView" {
          Button(element.type == "MapRoute" ? "Delete Route…" : "Delete Marker…", systemImage: "trash", role: .destructive) {
            deleting = true
          }
          .accessibilityIdentifier("delete-map-element")
        }
      } header: {
        Text(element.type == "MapView" ? "Map" : element.type == "MapRoute" ? "Route" : "Marker")
      }
      .disabled(model.status != .idle)
      .sheet(item: $sheet) { sheet in
        switch sheet {
        case .map(let map): MapSettingsSheet(model: model, map: map)
        case .route(let draft): MapRouteSheet(model: model, draft: draft)
        case .marker(let draft): MapMarkerSheet(model: model, draft: draft)
        }
      }
      .confirmationDialog(element.type == "MapRoute" ? "Delete this route?" : "Delete this marker?",
                          isPresented: $deleting, titleVisibility: .visible) {
        Button("Delete", role: .destructive) { Task { await model.removeSelectedMapChild() } }
      } message: {
        Text("Removes it from \(SourceStamp(element.source)?.file ?? "the source"). You can undo this.")
      }
    }
  }

  private var journey: some View {
    HStack {
      Button("Animate Journey", systemImage: "play.circle") {
        let fps = model.player.composition?.fps ?? 30
        Task { await model.animateRouteJourney(frames: Int((journeySeconds * fps).rounded())) }
      }
      .accessibilityIdentifier("animate-journey")
      .help("Keyframe progress from 0 at the playhead to 1")
      Spacer()
      Stepper("\(journeySeconds.formatted())s", value: $journeySeconds, in: 0.5...60, step: 0.5)
        .fixedSize()
    }
  }

  private func action(_ title: String, _ symbol: String, id: String, perform: @escaping () -> Void) -> some View {
    Button(title, systemImage: symbol, action: perform).accessibilityIdentifier(id)
  }
}

// MARK: Map settings

struct MapSettingsSheet: View {
  let model: EditorModel
  let map: Scene3D.EditorElement
  @Environment(\.dismiss) private var dismiss
  @State private var provider: String
  @State private var style: String
  @State private var longitude: Double
  @State private var latitude: Double
  @State private var zoom: Double
  @State private var bearing: Double
  @State private var saturation: Double
  @State private var brightness: Double
  @State private var attribution: String
  @State private var token: String
  private let original: [String: JSONValue]
  private let originalToken: String

  init(model: EditorModel, map: Scene3D.EditorElement) {
    self.model = model
    self.map = map
    let props = map.properties
    original = props
    _provider = State(initialValue: props["provider"]?.string ?? "openstreetmap")
    _style = State(initialValue: props["mapStyle"]?.string ?? "standard")
    _longitude = State(initialValue: props["centerLongitude"]?.number ?? 0)
    _latitude = State(initialValue: props["centerLatitude"]?.number ?? 0)
    _zoom = State(initialValue: props["zoom"]?.number ?? 2)
    _bearing = State(initialValue: props["bearing"]?.number ?? 0)
    _saturation = State(initialValue: props["saturation"]?.number ?? 1)
    _brightness = State(initialValue: props["brightness"]?.number ?? 1)
    _attribution = State(initialValue: props["attribution"]?.string ?? "bottom-right")
    let token = UserDefaults.standard.string(forKey: MapServices.mapboxTokenDefaultsKey) ?? ""
    _token = State(initialValue: token)
    originalToken = token
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Provider", selection: $provider) {
            ForEach(MapCatalog.providers) { provider in
              Label(provider.label, systemImage: provider.symbol).tag(provider.id)
            }
          }
          .accessibilityIdentifier("map-provider")
          Picker("Style", selection: $style) {
            ForEach(MapCatalog.provider(provider).styles, id: \.id) { Text($0.label).tag($0.id) }
          }
          .accessibilityIdentifier("map-style")
          if provider == "mapbox" {
            SecureField("Mapbox access token", text: $token)
              .autocorrectionDisabled()
              .accessibilityIdentifier("mapbox-token")
          }
        } header: {
          Text("Provider")
        } footer: {
          Text(providerFooter).font(.caption)
        }
        Section("Camera") {
          PlaceSearchField(prompt: "Center on a place") { longitude = $0; latitude = $1 }
          CoordinateFields(longitude: $longitude, latitude: $latitude)
          LabeledSlider(title: "Zoom", value: $zoom, range: 0...20, step: 0.1,
                        format: { "z" + $0.formatted(.number.precision(.fractionLength(1))) })
          LabeledSlider(title: "Bearing", value: $bearing, range: -180...180, step: 1, format: { "\(Int($0.rounded()))°" })
        }
        Section {
          LabeledSlider(title: "Saturation", value: $saturation, range: 0...2, step: 0.05, format: percent)
          LabeledSlider(title: "Brightness", value: $brightness, range: 0...2, step: 0.05, format: percent)
          Picker("Attribution", selection: $attribution) {
            ForEach(MapCatalog.attributionCorners, id: \.self) {
              Text($0.replacingOccurrences(of: "-", with: " ").capitalized).tag($0)
            }
          }
        } header: {
          Text("Appearance")
        } footer: {
          Text(keyframeFooter).font(.caption)
        }
      }
      .formStyle(.grouped)
      .onChange(of: provider) { _, provider in
        if !MapCatalog.provider(provider).styles.contains(where: { $0.id == style }) {
          style = MapCatalog.provider(provider).styles[0].id
        }
      }
      .navigationTitle("Map Settings")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }.accessibilityIdentifier("save-map")
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    #if os(macOS)
    .frame(minWidth: 460, idealWidth: 520, minHeight: 620, idealHeight: 700)
    #else
    .presentationDetents([.large])
    #endif
  }

  private var providerFooter: String {
    switch provider {
    case "apple":
      MapServices.isAppleMapsAvailable ? "Apple Maps tiles are drawn with MapKit. Elsewhere the map falls back to OpenStreetMap."
        : "MapKit is unavailable here; the map falls back to OpenStreetMap."
    case "mapbox":
      "The token is saved on this device (or set MAPBOX_ACCESS_TOKEN). Without one the map falls back to OpenStreetMap."
    default: "OpenStreetMap tiles. Light and Dark are filtered Standard tiles. Attribution is always drawn."
    }
  }

  private var keyframeFooter: String {
    let keyframed = model.objectTracks.first { $0.src == map.source }?.keyframes.keys.filter {
      ["centerLongitude", "centerLatitude", "zoom", "bearing", "saturation", "brightness"].contains($0)
    } ?? []
    guard !keyframed.isEmpty else { return "Tiles are cached on disk, so exports and offline previews match." }
    let names = keyframed.sorted().map(MapCatalog.label).joined(separator: ", ")
    return "Keyframed (\(names)): saved as a keyframe at frame \(model.player.currentFrame)."
  }

  private func percent(_ value: Double) -> String { (value * 100).formatted(.number.precision(.fractionLength(0))) + "%" }

  private func save() {
    var values: [String: JSONValue] = [:]
    func set(_ key: String, _ value: JSONValue) {
      if original[key] != value { values[key] = value }
    }
    set("provider", .string(provider))
    set("mapStyle", .string(style))
    set("centerLongitude", .number(EditorModel.coordinate(longitude)))
    set("centerLatitude", .number(EditorModel.coordinate(min(max(latitude, -85.05), 85.05))))
    set("zoom", .number(EditorModel.rounded(zoom)))
    set("bearing", .number(EditorModel.rounded(bearing)))
    set("saturation", .number(EditorModel.rounded(saturation)))
    set("brightness", .number(EditorModel.rounded(brightness)))
    set("attribution", .string(attribution))
    let tokenChanged = token != originalToken
    if tokenChanged {
      let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { UserDefaults.standard.removeObject(forKey: MapServices.mapboxTokenDefaultsKey) } else {
        UserDefaults.standard.set(trimmed, forKey: MapServices.mapboxTokenDefaultsKey)
      }
    }
    dismiss()
    Task {
      if !values.isEmpty { await model.setMapValues(values, of: map.source, name: "Map Settings") }
      if tokenChanged { model.player.refreshMapData() }
    }
  }
}

// MARK: Routes

struct MapRouteDraft {
  var source: String?
  var fromLongitude = 0.0, fromLatitude = 0.0, toLongitude = 0.0, toLatitude = 0.0
  var mode = "straight"
  var color = "#ff5a36", outlineColor = "#ffffff"
  var width = 5.0, markerSize = 14.0, progress = 1.0
  var original: [String: JSONValue] = [:]

  init(_ element: Scene3D.EditorElement) {
    let props = element.properties
    source = element.source
    original = props
    fromLongitude = props["fromLongitude"]?.number ?? 0
    fromLatitude = props["fromLatitude"]?.number ?? 0
    toLongitude = props["toLongitude"]?.number ?? 0
    toLatitude = props["toLatitude"]?.number ?? 0
    mode = props["mode"]?.string ?? mode
    color = props["color"]?.string ?? color
    outlineColor = props["outlineColor"]?.string ?? outlineColor
    width = props["width"]?.number ?? width
    markerSize = props["markerSize"]?.number ?? markerSize
    progress = props["progress"]?.number ?? progress
  }

  @MainActor init(adding model: EditorModel) {
    let from = model.mapCoordinate(atFraction: 0.3, 0.6) ?? (0, 0)
    let to = model.mapCoordinate(atFraction: 0.7, 0.4) ?? (1, 1)
    (fromLongitude, fromLatitude, toLongitude, toLatitude) = (from.longitude, from.latitude, to.longitude, to.latitude)
  }

  var values: [String: JSONValue] {
    [
      "fromLongitude": .number(EditorModel.coordinate(fromLongitude)), "fromLatitude": .number(EditorModel.coordinate(fromLatitude)),
      "toLongitude": .number(EditorModel.coordinate(toLongitude)), "toLatitude": .number(EditorModel.coordinate(toLatitude)),
      "mode": .string(mode), "color": .string(color), "outlineColor": .string(outlineColor),
      "width": .number(EditorModel.rounded(width)), "markerSize": .number(EditorModel.rounded(markerSize)),
      "progress": .number(EditorModel.rounded(progress)),
    ]
  }
}

struct MapRouteSheet: View {
  let model: EditorModel
  @State var draft: MapRouteDraft
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Start") {
          PlaceSearchField(prompt: "Search for the start") { draft.fromLongitude = $0; draft.fromLatitude = $1 }
          CoordinateFields(longitude: $draft.fromLongitude, latitude: $draft.fromLatitude)
        }
        Section("End") {
          PlaceSearchField(prompt: "Search for the end") { draft.toLongitude = $0; draft.toLatitude = $1 }
          CoordinateFields(longitude: $draft.toLongitude, latitude: $draft.toLatitude)
        }
        Section {
          Picker("Follow", selection: $draft.mode) {
            ForEach(MapCatalog.modes) { mode in Label(mode.label, systemImage: mode.symbol).tag(mode.id) }
          }
          .accessibilityIdentifier("route-mode")
        } header: {
          Text("Path")
        } footer: {
          Text((MapCatalog.modes.first { $0.id == draft.mode }?.detail ?? "")
               + ". Routes are cached on disk once fetched.").font(.caption)
        }
        Section("Style") {
          HexColorPicker(title: "Line color", hex: $draft.color)
          HexColorPicker(title: "Outline color", hex: $draft.outlineColor)
          LabeledSlider(title: "Line width", value: $draft.width, range: 1...24, step: 0.5, format: { $0.formatted() + " px" })
          LabeledSlider(title: "Head marker", value: $draft.markerSize, range: 0...48, step: 1,
                        format: { $0 == 0 ? "Hidden" : $0.formatted() + " px" })
          if !isKeyframed("progress") {
            LabeledSlider(title: "Progress", value: $draft.progress, range: 0...1, step: 0.01,
                          format: { ($0 * 100).formatted(.number.precision(.fractionLength(0))) + "%" })
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(draft.source == nil ? "Add Route" : "Edit Route")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(draft.source == nil ? "Add" : "Save") { save() }.accessibilityIdentifier("save-route")
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    #if os(macOS)
    .frame(minWidth: 460, idealWidth: 520, minHeight: 640, idealHeight: 720)
    #else
    .presentationDetents([.large])
    #endif
  }

  private func isKeyframed(_ key: String) -> Bool {
    draft.source.flatMap { source in model.objectTracks.first { $0.src == source }?.keyframes[key] } != nil
  }

  private func save() {
    let draft = draft
    dismiss()
    Task {
      if let source = draft.source {
        let changed = draft.values.filter { key, value in
          draft.original[key] != value && !(key == "progress" && isKeyframed(key))
        }
        await model.setMapValues(changed, of: source, name: "Edit Route")
      } else {
        let values = draft.values
        await model.addMapChild("MapRoute", props: [
          "from": .array([values["fromLongitude"]!, values["fromLatitude"]!]),
          "to": .array([values["toLongitude"]!, values["toLatitude"]!]),
          "mode": values["mode"]!, "color": values["color"]!, "outlineColor": values["outlineColor"]!, "width": values["width"]!,
          "markerSize": values["markerSize"]!, "progress": values["progress"]!,
        ])
      }
    }
  }
}

// MARK: Markers

struct MapMarkerDraft {
  var source: String?
  var longitude = 0.0, latitude = 0.0
  var label = "", color = "#ff5a36"
  var size = 18.0
  var original: [String: JSONValue] = [:]

  init(_ element: Scene3D.EditorElement) {
    let props = element.properties
    source = element.source
    original = props
    longitude = props["longitude"]?.number ?? 0
    latitude = props["latitude"]?.number ?? 0
    label = props["label"]?.string ?? ""
    color = props["color"]?.string ?? color
    size = props["size"]?.number ?? size
  }

  @MainActor init(adding model: EditorModel) {
    let center = model.mapCoordinate(atFraction: 0.5, 0.5) ?? (0, 0)
    (longitude, latitude) = (center.longitude, center.latitude)
  }

  var values: [String: JSONValue] {
    ["longitude": .number(EditorModel.coordinate(longitude)), "latitude": .number(EditorModel.coordinate(latitude)),
     "label": .string(label), "color": .string(color), "size": .number(EditorModel.rounded(size))]
  }
}

struct MapMarkerSheet: View {
  let model: EditorModel
  @State var draft: MapMarkerDraft
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Location") {
          PlaceSearchField(prompt: "Search for a place") { longitude, latitude, name in
            draft.longitude = longitude
            draft.latitude = latitude
            if draft.label.isEmpty { draft.label = name }
          }
          CoordinateFields(longitude: $draft.longitude, latitude: $draft.latitude)
        }
        Section("Appearance") {
          TextField("Label", text: $draft.label).accessibilityIdentifier("marker-label")
          HexColorPicker(title: "Color", hex: $draft.color)
          LabeledSlider(title: "Size", value: $draft.size, range: 4...64, step: 1, format: { $0.formatted() + " px" })
        }
      }
      .formStyle(.grouped)
      .navigationTitle(draft.source == nil ? "Add Marker" : "Edit Marker")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(draft.source == nil ? "Add" : "Save") { save() }.accessibilityIdentifier("save-marker")
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    #if os(macOS)
    .frame(minWidth: 440, idealWidth: 500, minHeight: 480, idealHeight: 540)
    #else
    .presentationDetents([.large])
    #endif
  }

  private func save() {
    let draft = draft
    dismiss()
    Task {
      if let source = draft.source {
        await model.setMapValues(draft.values.filter { draft.original[$0.key] != $0.value }, of: source, name: "Edit Marker")
      } else {
        let values = draft.values
        var props: [String: JSONValue] = ["coordinate": .array([values["longitude"]!, values["latitude"]!]), "color": values["color"]!,
                                          "size": values["size"]!]
        if !draft.label.isEmpty { props["label"] = values["label"]! }
        await model.addMapChild("MapMarker", props: props)
      }
    }
  }
}
