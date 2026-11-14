import CoreGraphics
import Foundation
import MotionCore
import MotionPortable

/// What a canvas drag on a map changes.
public enum MapDragKind: String, Sendable {
  /// Pans the `<MapView>` camera (its center).
  case pan
  /// Moves a `<MapRoute>` start or end point.
  case routeStart, routeEnd
  /// Moves a `<MapMarker>`.
  case marker
}

struct MapDragState {
  let kind: MapDragKind
  /// The element whose props the drag writes.
  let source: String
  let camera: MapCamera
  /// Composition point that the dragged coordinate started at.
  let anchor: CGPoint
  let start: [String: Double]
}

struct MapEditing {
  var preview: [String: Double] = [:]
  var drag: MapDragState?
}

extension EditorModel {
  // MARK: Selection

  /// Evaluated props of a `<MapView>`, `<MapRoute>` or `<MapMarker>` at the displayed frame.
  public func mapElement(_ source: String?) -> Scene3D.EditorElement? {
    guard let source else { return nil }
    return player.displayedFrame?.tree.editorElements.first { $0.source == source }
  }

  public var selectedMapElement: Scene3D.EditorElement? { mapElement(selection) }

  /// Whether the selection is a map component (before its source summary loads too).
  public var isMapSelection: Bool { styles?.isMap == true || selectedMapElement != nil }

  /// The `<MapView>` that contains `source` (or is `source`).
  public func mapView(containing source: String) -> Scene3D.EditorElement? {
    guard !source.isEmpty, let tree = player.displayedFrame?.tree else { return nil }
    func visit(_ node: RenderNode, _ map: Scene3D.EditorElement?) -> Scene3D.EditorElement? {
      let map = node.editor?.type == "MapView" ? node.editor : map
      if node.source == source { return map }
      for child in node.children { if let found = visit(child, map) { return found } }
      return nil
    }
    return visit(tree, nil)
  }

  /// The `<MapView>` for the current selection, or the primary visible `<MapView>` in the composition.
  public var activeMapView: Scene3D.EditorElement? {
    if let selection, let map = mapView(containing: selection) { return map }
    return player.displayedFrame?.tree.editorElements.first { $0.type == "MapView" }
  }

  /// Whether the current composition renders a `<MapView>`.
  public var hasMapView: Bool {
    timelineTracks.contains { $0.label == "MapView" }
      || player.displayedFrame?.tree.editorElements.contains { $0.type == "MapView" } == true
  }

  private func mapView(at point: CGPoint) -> Scene3D.EditorElement? {
    guard let frame = player.displayedFrame else { return nil }
    for element in frame.tree.editorElements.reversed() where element.type == "MapView" {
      if let box = frame.layout.first(where: { $0.source == element.source }), visualRect(box).contains(point) {
        return element
      }
    }
    return nil
  }

  /// The camera of the map containing `source`, in composition pixels.
  public func mapCamera(for source: String) -> MapCamera? {
    guard let map = mapView(containing: source) else { return nil }
    let box = player.displayedFrame?.layout.first { $0.source == map.source }
    return MapCamera(map.properties, origin: CGPoint(x: box?.x ?? 0, y: box?.y ?? 0))
  }

  /// Composition-space handles of the selected route (start, end) or marker.
  public var mapHandles: [(kind: MapDragKind, point: CGPoint)] {
    guard let element = selectedMapElement, let camera = mapCamera(for: element.source) else { return [] }
    let value = { (key: String) in self.mapPreview[key] ?? element.properties[key]?.number }
    switch element.type {
    case "MapRoute":
      guard let fx = value("fromLongitude"), let fy = value("fromLatitude"),
        let tx = value("toLongitude"), let ty = value("toLatitude") else { return [] }
      return [(.routeStart, camera.project(fx, fy)), (.routeEnd, camera.project(tx, ty))]
    case "MapMarker":
      guard let x = value("longitude"), let y = value("latitude") else { return [] }
      return [(.marker, camera.project(x, y))]
    default: return []
    }
  }

  /// Live values of an in-progress map drag.
  public internal(set) var mapPreview: [String: Double] {
    get { mapState.preview }
    set { mapState.preview = newValue }
  }

  /// A note about the selected map element: provider fallback or route problems.
  public var mapStatus: String? {
    guard let properties = selectedMapElement?.properties else { return nil }
    return properties["routeStatus"]?.string ?? properties["providerNote"]?.string
      ?? mapView(containing: selection ?? "")?.properties["providerNote"]?.string
  }

  // MARK: Canvas drags

  /// Starts a map drag at a composition point: route/marker handles of the selection, else panning
  /// the map under the point. Returns false when the point is not on a map.
  @discardableResult
  public func beginMapDrag(at point: CGPoint, handleRadius: Double = 14) -> Bool {
    guard status == .idle, !isGesturing else { return false }
    var kind: MapDragKind?
    var anchor = point
    if let handle = mapHandles.min(by: { distance($0.point, point) < distance($1.point, point) }),
      distance(handle.point, point) <= handleRadius {
      kind = handle.kind
      anchor = handle.point
    }
    let element = kind == nil ? nil : selectedMapElement
    let target: Scene3D.EditorElement
    if let element {
      target = element
    } else {
      // Pan the map under the point (selecting it when needed).
      let hit = hitTest(point).flatMap { mapView(containing: $0.source ?? "") }
      let fallback = (isMapSelection ? mapView(containing: selection ?? "") : nil) ?? mapView(at: point)
      guard let map = hit ?? fallback else { return false }
      if selection != map.source, let track = objectTracks.first(where: { $0.src == map.source }) {
        selectTrack(track)
      }
      target = map
      kind = .pan
    }
    guard let kind, let camera = mapCamera(for: target.source) else { return false }
    let keys = Self.mapKeys(kind)
    if let track = objectTracks.first(where: { $0.src == target.source }), let reason = track.reason {
      refuse(reason)
      return false
    }
    var start: [String: Double] = [:]
    for key in keys {
      guard let value = target.properties[key]?.number else { return false }
      start[key] = value
    }
    if kind == .pan { anchor = CGPoint(x: camera.origin.x + camera.size.width / 2, y: camera.origin.y + camera.size.height / 2) }
    player.pause()
    discardKeyframeDraft()
    mapState.drag = MapDragState(kind: kind, source: target.source, camera: camera, anchor: anchor, start: start)
    isGesturing = true
    return true
  }

  static func mapKeys(_ kind: MapDragKind) -> [String] {
    switch kind {
    case .pan: ["centerLongitude", "centerLatitude"]
    case .routeStart: ["fromLongitude", "fromLatitude"]
    case .routeEnd: ["toLongitude", "toLatitude"]
    case .marker: ["longitude", "latitude"]
    }
  }

  /// Updates the live preview from a drag translation in composition pixels.
  public func updateMapDrag(dx: Double, dy: Double) {
    guard isGesturing, let drag = mapState.drag else { return }
    let keys = Self.mapKeys(drag.kind)
    // Panning moves the map with the pointer, so the center moves the opposite way.
    let point = drag.kind == .pan ? CGPoint(x: drag.anchor.x - dx, y: drag.anchor.y - dy)
      : CGPoint(x: drag.anchor.x + dx, y: drag.anchor.y + dy)
    let coordinate = drag.camera.unproject(point)
    let values = [keys[0]: Self.coordinate(coordinate.longitude), keys[1]: Self.coordinate(coordinate.latitude)]
    mapPreview = values
    player.setPreviewOverrides([drag.source: values.mapValues { JSONValue.number($0) }])
  }

  public func cancelMapDrag() {
    isGesturing = false
    mapState.drag = nil
    mapPreview = [:]
    player.setPreviewOverrides([:])
  }

  /// Saves the drag as one undo step (a keyframe at the playhead for keyframed coordinates).
  public func endMapDrag() async {
    guard isGesturing, let drag = mapState.drag else { return }
    let values = mapPreview
    isGesturing = false
    mapState.drag = nil
    let changed = values.filter { abs($0.value - (drag.start[$0.key] ?? .nan)) > 1e-9 }
    guard !changed.isEmpty else { mapPreview = [:]; player.setPreviewOverrides([:]); return }
    let name = switch drag.kind {
    case .pan: "Pan Map"
    case .routeStart: "Move Route Start"
    case .routeEnd: "Move Route End"
    case .marker: "Move Marker"
    }
    let saved = await setMapValues(values.mapValues { .number($0) }, of: drag.source, name: name)
    mapPreview = [:]
    if !saved { player.setPreviewOverrides([:]) }
  }

  // MARK: Writes

  /// Writes several map props as one undo step. Keyframed numbers get a keyframe at the playhead;
  /// everything else rewrites its attribute (including overriding code-controlled map props).
  @discardableResult
  public func setMapValues(_ values: [String: JSONValue], of source: String, name: String) async -> Bool {
    guard !values.isEmpty else { return true }
    var values = values
    let timingSource = objectTracks.first { $0.src == source }
    let coordinatePairs = [
      ("centerLongitude", "centerLatitude"),
      ("fromLongitude", "fromLatitude"),
      ("toLongitude", "toLatitude"),
      ("longitude", "latitude"),
    ]
    let hasHalfPair = coordinatePairs.contains { (lon, lat) in
      (values[lon] != nil && values[lat] == nil && timingSource?.timing.keyframes[lat] == nil)
        || (values[lat] != nil && values[lon] == nil && timingSource?.timing.keyframes[lon] == nil)
    }
    if hasHalfPair {
      let summary: StyleSummary? = if selection == source, let styles {
        styles
      } else if let stamp = SourceStamp(source), let code = files[stamp.file] {
        try? await service.perform { try $0.styles(source: code, src: source) }
      } else {
        nil
      }
      var liveProps: [String: JSONValue]?
      func siblingValue(_ key: String) async -> Double? {
        if liveProps == nil {
          let rendered = try? await player.render(frame: player.currentFrame)
          liveProps = rendered?.tree.editorElements.first { $0.source == source }?.properties
            ?? mapElement(source)?.properties
        }
        return liveProps?[key]?.number
      }
      for (lon, lat) in coordinatePairs {
        if values[lon] != nil, values[lat] == nil, timingSource?.timing.keyframes[lat] == nil,
          let prop = summary?.property(lat), prop.kind != .static, let live = await siblingValue(lat) {
          values[lat] = .number(Self.coordinate(live))
        } else if values[lat] != nil, values[lon] == nil, timingSource?.timing.keyframes[lon] == nil,
          let prop = summary?.property(lon), prop.kind != .static, let live = await siblingValue(lon) {
          values[lon] = .number(Self.coordinate(live))
        }
      }
    }
    guard let track = timingSource, let composition = player.composition else {
      return await apply(values.keys.sorted().map { .setStyle(source, $0, values[$0]!) }, name: name, from: .user)
    }
    if let reason = track.reason { refuse(reason); return false }
    var timing = track.timing
    var operations: [EditOperation] = []
    var keyframed = false
    let local = player.currentFrame - track.start
    for key in values.keys.sorted() {
      let value = values[key]!
      if var points = timing.keyframes[key] {
        guard let number = value.number else { refuse("\(key) is keyframed; it needs a number"); return false }
        guard local >= 0, player.currentFrame < track.end(in: composition.durationInFrames) else {
          refuse("Move the playhead inside the object to keyframe it"); return false
        }
        let easing = points.first { $0.frame == local }?.easing ?? "linear"
        points.removeAll { $0.frame == local }
        points.append(.init(frame: local, value: number, easing: easing))
        timing.keyframes[key] = points.sorted { $0.frame < $1.frame }
        keyframed = true
      } else {
        operations.append(.setStyle(source, key, value))
      }
    }
    do {
      if keyframed { operations.append(try .setTimeline(source, timing)) }
    } catch { show(.failure, String(describing: error)); return false }
    return await apply(operations, name: name, from: .user)
  }

  /// Zooms or rotates the active map by a step.
  public func nudgeMap(zoom: Double = 0, bearing: Double = 0) async {
    guard let map = activeMapView else { return }
    if selection == nil, let track = objectTracks.first(where: { $0.src == map.source }) { selectTrack(track) }
    var values: [String: JSONValue] = [:]
    if zoom != 0, let current = map.properties["zoom"]?.number {
      values["zoom"] = .number(Self.rounded(min(max(current + zoom, 0), 22)))
    }
    if bearing != 0, let current = map.properties["bearing"]?.number {
      var next = current + bearing
      if next > 180 { next -= 360 } else if next < -180 { next += 360 }
      values["bearing"] = .number(Self.rounded(next))
    }
    await setMapValues(values, of: map.source, name: zoom != 0 ? "Zoom Map" : "Rotate Map")
  }

  /// Points the active map north.
  public func resetMapBearing() async {
    guard let map = activeMapView, map.properties["bearing"]?.number != 0 else { return }
    if selection == nil, let track = objectTracks.first(where: { $0.src == map.source }) { selectTrack(track) }
    await setMapValues(["bearing": .number(0)], of: map.source, name: "Reset North")
  }

  /// Moves the camera so the selected route (or marker) fills the map.
  public func frameSelectionOnMap() async {
    guard let element = selectedMapElement, let map = mapView(containing: element.source),
      let camera = mapCamera(for: element.source) else { return }
    let props = element.properties
    let target: MapCamera
    if element.type == "MapRoute", let fx = props["fromLongitude"]?.number, let fy = props["fromLatitude"]?.number,
      let tx = props["toLongitude"]?.number, let ty = props["toLatitude"]?.number {
      target = camera.framing((fx, fy), (tx, ty), padding: min(camera.size.width, camera.size.height) * 0.15)
    } else if element.type == "MapMarker", let x = props["longitude"]?.number, let y = props["latitude"]?.number {
      target = MapCamera(longitude: x, latitude: y, zoom: max(camera.zoom, 14), size: camera.size)
    } else { return }
    await setMapValues([
      "centerLongitude": .number(Self.coordinate(target.longitude)),
      "centerLatitude": .number(Self.coordinate(target.latitude)),
      "zoom": .number(Self.rounded(target.zoom)), "bearing": .number(0),
    ], of: map.source, name: "Frame on Map")
  }

  /// Keyframes the selected route's progress from 0 at the playhead to 1 after `frames`.
  public func animateRouteJourney(frames: Int) async {
    guard let element = selectedMapElement, element.type == "MapRoute",
      let track = objectTracks.first(where: { $0.src == element.source }), let composition = player.composition else { return }
    if let reason = track.reason { refuse(reason); return }
    let end = track.end(in: composition.durationInFrames)
    let start = min(max(player.currentFrame, track.start), end - 2) - track.start
    let finish = min(start + max(frames, 1), end - 1 - track.start)
    guard finish > start else { refuse("The route needs at least two frames to animate"); return }
    var timing = track.timing
    timing.keyframes["progress"] = [.init(frame: start, value: 0), .init(frame: finish, value: 1)]
    do {
      await apply([try .setTimeline(element.source, timing)], name: "Animate Journey", from: .user)
    } catch { show(.failure, String(describing: error)) }
  }

  /// Adds a route or marker to the active map.
  @discardableResult
  public func addMapChild(_ type: String, props: [String: JSONValue]) async -> Bool {
    guard let map = activeMapView else {
      refuse("Select a map first"); return false
    }
    let owner = objectTracks.first { $0.src == map.source }?.owner
    let saved = await apply([EditOperation(op: .setMapChildren, src: map.source, key: "insert",
      value: .object(["type": .string(type), "props": .object(props)]))],
      name: type == "MapRoute" ? "Add Route" : "Add Marker", from: .user)
    if saved {
      // Select the new element inside the map's component/composition rather than a later sibling composition.
      let file = SourceStamp(map.source)?.file
      let matching = timelineTracks.last {
        $0.label == type && SourceStamp($0.src)?.file == file && (owner == nil || $0.owner == owner)
      } ?? objectTracks.last {
        $0.label == type && SourceStamp($0.src)?.file == file && (owner == nil || $0.owner == owner)
      }
      if let track = matching { selectTrack(track) }
    }
    return saved
  }

  /// Removes the selected route or marker.
  public func removeSelectedMapChild() async {
    guard let element = selectedMapElement, ["MapRoute", "MapMarker"].contains(element.type) else { return }
    let name = element.type == "MapRoute" ? "Delete Route" : "Delete Marker"
    if await apply([EditOperation(op: .setMapChildren, src: element.source, key: "remove")], name: name, from: .user) {
      clearSelection()
    }
  }

  /// A coordinate a fraction of the way across the active map (for placing new elements).
  public func mapCoordinate(atFraction x: Double, _ y: Double) -> (longitude: Double, latitude: Double)? {
    guard let map = activeMapView, let camera = mapCamera(for: map.source) else { return nil }
    let point = CGPoint(x: camera.origin.x + camera.size.width * x, y: camera.origin.y + camera.size.height * y)
    let coordinate = camera.unproject(point)
    return (Self.coordinate(coordinate.longitude), Self.coordinate(coordinate.latitude))
  }

  nonisolated static func coordinate(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }

  private func distance(_ first: CGPoint, _ second: CGPoint) -> Double { hypot(first.x - second.x, first.y - second.y) }
}
