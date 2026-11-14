import CoreGraphics
import Foundation
import MotionCore
import MotionPortable
import MotionSwiftUI
import Testing
@testable import MotionEditor
@testable import motionswift_showcase

/// Offline with an empty cache: placeholder tiles, no network and no previously fetched routes.
private func isolateMaps(_ directory: URL) {
  MapServices.cacheDirectory = directory.appendingPathComponent("map-cache")
  MapServices.isOffline = true
}

private func restoreMaps() {
  MapServices.resetCacheDirectory()
  MapServices.isOffline = false
}

private struct OpenedMapStudio {
  let model: EditorModel
  let url: URL
  let original: String
}

@MainActor
private func openMapStudio(_ directory: URL) async throws -> OpenedMapStudio {
  let location = try ShowcaseExample.project(MotionStudy.mapStudioProject, entry: "index.tsx").prepare(root: directory)
  let model = EditorModel(project: location.project, entry: location.entry, configuration: .init(scale: 0.5, backend: .gpu))
  await model.open(compositionID: "HarbourJourney")
  #expect(model.status == .idle, "\(model.status)")
  for _ in 0..<500 where model.player.displayedFrame == nil { try await Task.sleep(for: .milliseconds(10)) }
  model.observeTimelineFrame()
  let url = location.project.appendingPathComponent("index.tsx")
  return OpenedMapStudio(model: model, url: url, original: try String(contentsOf: url, encoding: .utf8))
}

@MainActor
private func select(_ model: EditorModel, _ track: ObjectTrack) async throws {
  model.selectTrack(track)
  for _ in 0..<300 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  try #require(model.styles != nil)
}

@Suite(.serialized)
struct MapEditorTests {
  @Test @MainActor
  func mapStudioExposesEditableMapRoutesAndMarkers() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("map-studio-\(UUID())")
    isolateMaps(directory)
    defer { restoreMaps(); try? FileManager.default.removeItem(at: directory) }
    let studio = try await openMapStudio(directory)
    let (model, url, original) = (studio.model, studio.url, studio.original)

    let frame = try await model.player.render(frame: 0)
    let elements = frame.tree.editorElements
    #expect(elements.filter { $0.type == "MapView" }.count == 1)
    #expect(elements.filter { $0.type == "MapRoute" }.count == 2)
    #expect(elements.filter { $0.type == "MapMarker" }.count == 3)
    // Offline, the railway route is drawn as a placeholder line and says why (unless this process
    // already resolved it, in which case the memory cache serves it).
    let railway = try #require(elements.first { $0.properties["mode"] == .string("railway") })
    #expect(railway.properties["routeStatus"]?.string?.contains("offline") == true || railway.properties["routeSource"] != nil,
            "\(railway.properties)")
    #expect(model.timelineTracks.map(\.label).filter { $0.hasPrefix("Map") }.count == 6)

    let map = try #require(model.timelineTracks.first { $0.label == "MapView" })
    try await select(model, map)
    #expect(model.styles?.isMap == true)
    #expect(model.styles?.type == "MapView")
    #expect(model.isMapSelection)
    #expect(model.selectedRect == nil, "maps draw map handles, not resize handles")
    #expect(model.currentStyleValue("zoom")?.number == 13.2)

    // Provider and style: one undo step, with MapKit on Apple platforms.
    await model.setMapValues(["provider": .string("apple"), "mapStyle": .string("satellite")], of: map.src, name: "Map Settings")
    #expect(try String(contentsOf: url, encoding: .utf8).contains(#"provider="apple" mapStyle="satellite""#))
    let apple = try await model.player.render(frame: 0)
    let view = try #require(apple.tree.editorElements.first { $0.type == "MapView" })
    #expect(view.properties["effectiveProvider"] == .string(MapServices.isAppleMapsAvailable ? "apple" : "openstreetmap"))
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)

    // Zoom is keyframed in the study, so a camera edit lands as a keyframe at the playhead.
    model.scrub(to: 120)
    await model.setMapValues(["zoom": .number(15)], of: map.src, name: "Zoom Map")
    let keyed = try #require(model.timelineTracks.first { $0.src == map.src })
    #expect(keyed.keyframes["zoom"]?.contains { $0.frame == 120 && $0.value == 15 } == true)
    let zoomed = try await model.player.render(frame: 120)
    #expect(zoomed.tree.editorElements.first { $0.type == "MapView" }?.properties["zoom"] == .number(15))
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)
  }

  @Test @MainActor
  func mapCanvasDragsPanTheCameraAndMoveRouteEndpoints() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("map-drags-\(UUID())")
    isolateMaps(directory)
    defer { restoreMaps(); try? FileManager.default.removeItem(at: directory) }
    let studio = try await openMapStudio(directory)
    let (model, url, original) = (studio.model, studio.url, studio.original)
    let map = try #require(model.timelineTracks.first { $0.label == "MapView" })
    try await select(model, map)
    model.scrub(to: 0)
    for _ in 0..<300 where model.player.displayedFrame?.frame != 0 { try await Task.sleep(for: .milliseconds(10)) }

    // Panning re-evaluates the map with preview props, then saves the keyframed center.
    let camera = try #require(model.mapCamera(for: map.src))
    let before = camera.longitude
    #expect(model.beginMapDrag(at: CGPoint(x: 640, y: 360)))
    model.updateMapDrag(dx: 200, dy: 0)
    let preview = try await model.player.render(frame: 0)
    let previewed = try #require(preview.tree.editorElements.first { $0.type == "MapView" }?.properties["centerLongitude"]?.number)
    #expect(previewed < before, "dragging right moves the camera west")
    await model.endMapDrag()
    #expect(model.player.previewOverrides.isEmpty)
    let panned = try #require(model.timelineTracks.first { $0.src == map.src }?.keyframes["centerLongitude"]?.first { $0.frame == 0 })
    #expect(abs(panned.value - previewed) < 1e-5)
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)

    // The arc route has literal endpoints: dragging its end handle rewrites `to`.
    let arc = try #require(model.timelineTracks.filter { $0.label == "MapRoute" }.last)
    try await select(model, arc)
    let handles = model.mapHandles
    #expect(handles.map(\.kind) == [.routeStart, .routeEnd])
    let end = handles[1].point
    let projected = try #require(model.mapCamera(for: arc.src)).unproject(end)
    #expect(abs(projected.longitude + 122.3790) < 1e-4 && abs(projected.latitude - 37.6213) < 1e-4)
    #expect(model.beginMapDrag(at: CGPoint(x: end.x + 3, y: end.y - 2)))
    model.updateMapDrag(dx: 0, dy: 60)
    await model.endMapDrag()
    let edited = try String(contentsOf: url, encoding: .utf8)
    let moved = try #require(edited.firstMatch(of: /to=\{\[-122\.379, (37\.\d+)\]\}/), "only the latitude moves: \(edited)")
    let latitude = try #require(Double(String(moved.1)))
    #expect(latitude < 37.6213 && latitude > 37.60, "dragging down moves the end south")
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)

    // Journeys: keyframe progress from the playhead.
    await model.animateRouteJourney(frames: 30)
    let journey = try #require(model.timelineTracks.first { $0.src == arc.src }?.keyframes["progress"])
    #expect(journey.map(\.frame) == [0, 30] && journey.map(\.value) == [0, 1])
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)
  }

  @Test @MainActor
  func mapRoutesAndMarkersAreAddedAndDeletedWithUndo() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("map-children-\(UUID())")
    isolateMaps(directory)
    defer { restoreMaps(); try? FileManager.default.removeItem(at: directory) }
    let studio = try await openMapStudio(directory)
    let (model, url, original) = (studio.model, studio.url, studio.original)
    let map = try #require(model.timelineTracks.first { $0.label == "MapView" })
    try await select(model, map)
    let center = try #require(model.mapCoordinate(atFraction: 0.5, 0.5))
    #expect(await model.addMapChild("MapMarker", props: [
      "coordinate": .array([.number(center.longitude), .number(center.latitude)]), "label": .string("Central"),
    ]))
    #expect(model.timelineTracks.filter { $0.label == "MapMarker" }.count == 4)
    #expect(model.selectedTrack?.label == "MapMarker")
    #expect(try String(contentsOf: url, encoding: .utf8).contains(#"label="Central""#))
    for _ in 0..<300 where model.selectedMapElement == nil { try await Task.sleep(for: .milliseconds(10)) }
    await model.removeSelectedMapChild()
    #expect(model.timelineTracks.filter { $0.label == "MapMarker" }.count == 3)
    await model.undo()
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)
    await model.redo()
    #expect(try String(contentsOf: url, encoding: .utf8).contains("Central"))
  }

  @Test @MainActor
  func codeControlledYamanoteMapCanBePannedOverriddenAndKeyframed() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("railway-edit-\(UUID())")
    isolateMaps(directory)
    defer { restoreMaps(); try? FileManager.default.removeItem(at: directory) }
    let location = try ShowcaseExample.project(MotionStudy.railwayProject, entry: "index.tsx").prepare(root: directory)
    let model = EditorModel(project: location.project, entry: location.entry, configuration: .init(scale: 0.5, backend: .gpu))
    await model.open(compositionID: "IslandRailway")
    #expect(model.status == .idle, "\(model.status)")
    for _ in 0..<500 where model.player.displayedFrame == nil { try await Task.sleep(for: .milliseconds(10)) }
    model.observeTimelineFrame()
    let url = location.project.appendingPathComponent("index.tsx")
    let original = try String(contentsOf: url, encoding: .utf8)

    // Toolbar and canvas controls work immediately even before selecting `<MapView>`,
    // and hit-testing ignores the full-screen `pointerEvents: 'none'` railway SVG overlay.
    #expect(model.hasMapView)
    #expect(model.activeMapView?.type == "MapView")
    let map = try #require(model.timelineTracks.first { $0.label == "MapView" })
    #expect(model.hitTest(CGPoint(x: 960, y: 540))?.source == map.src)

    // Zooming from the toolbar overrides `zoom={camera.zoom}` and restores it byte-for-byte on undo.
    await model.nudgeMap(zoom: 0.5)
    #expect(model.notice?.kind != .refusal, "\(String(describing: model.notice))")
    #expect(try String(contentsOf: url, encoding: .utf8).contains("zoom={13.5}"))
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)

    // Dragging directly on the canvas pans the code-controlled `center={camera.center}` camera.
    model.clearSelection()
    #expect(model.beginMapDrag(at: CGPoint(x: 960, y: 540)))
    model.updateMapDrag(dx: 140, dy: -80)
    await model.endMapDrag()
    #expect(model.notice?.kind != .refusal, "\(String(describing: model.notice))")
    let panned = try String(contentsOf: url, encoding: .utf8)
    #expect(!panned.contains("center={camera.center}"))
    #expect(panned.contains("center={["))
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)

    // Editing a single coordinate in the Inspector expands `center={camera.center}` while preserving latitude.
    try await select(model, map)
    await model.setStyle("centerLongitude", .number(139.8))
    let singleAxis = try String(contentsOf: url, encoding: .utf8)
    #expect(singleAxis.contains("center={[139.8, 35.681]}") || singleAxis.contains("center={[139.8,35.681]}"), "\(singleAxis)")
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)

    // Capturing a keyframe on the code-controlled map animates camera fields without refusal.
    await model.captureKeyframe()
    let keyed = try #require(model.timelineTracks.first { $0.src == map.src })
    #expect(keyed.keyframes["zoom"]?.contains { $0.frame == 0 && $0.value == 13 } == true)
    #expect(keyed.keyframes["centerLongitude"]?.contains { $0.frame == 0 } == true)
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)
  }

  @Test
  func mapCameraProjectionRoundTripsAndFramesRoutes() {
    let camera = MapCamera(longitude: 114.17, latitude: 22.28, zoom: 13, bearing: 30, size: CGSize(width: 1280, height: 720),
                           origin: CGPoint(x: 10, y: 20))
    let center = camera.project(114.17, 22.28)
    #expect(abs(center.x - 650) < 1e-6 && abs(center.y - 380) < 1e-6)
    let point = camera.project(114.2, 22.3)
    let back = camera.unproject(point)
    #expect(abs(back.longitude - 114.2) < 1e-9 && abs(back.latitude - 22.3) < 1e-9)
    let framed = camera.framing((114.15, 22.28), (114.19, 22.29), padding: 100)
    for (longitude, latitude) in [(114.15, 22.28), (114.19, 22.29)] {
      let projected = framed.project(longitude, latitude)
      #expect((90...1190).contains(projected.x) && (90...630).contains(projected.y))
    }
    #expect(framed.bearing == 0)
  }
}
