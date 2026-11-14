import Foundation
import ImageIO
import Testing
@testable import MotionCore

@Test
func mapTileSourcesAreValidated() throws {
  let tile = try MapServices.Tile("motionmap://tile/openstreetmap/standard/13/6693/3577")
  #expect(tile == (try MapServices.Tile("motionmap://tile/openstreetmap/standard/13/6693/3577")))
  #expect(tile.zoom == 13 && tile.x == 6693 && tile.y == 3577)
  for bad in ["motionmap://tile/openstreetmap/standard/3/8/0", "motionmap://tile/osm/../../etc/1/0/0",
              "https://tile.openstreetmap.org/1/0/0.png", "motionmap://tile/openstreetmap/standard/23/0/0"] {
    #expect(throws: MotionError.self) { try MapServices.Tile(bad) }
  }
  #expect(throws: MotionError.self) { try MapServices.Tile("motionmap://tile/bing/aerial/1/0/0").remoteURL() }
}

@Test
func previewSnapshotsDoNotBlockAndHaveBoundedConcurrency() throws {
  let loader = MapTilePreviewLoader()
  let release = DispatchSemaphore(value: 0)
  let started = DispatchSemaphore(value: 0)
  let finished = DispatchGroup()
  let calls = LockedValue(0)
  defer { for _ in 0..<8 { release.signal() } }
  let begin = ProcessInfo.processInfo.systemUptime
  for index in 0..<8 {
    finished.enter()
    #expect(try loader.request(key: "tile-\(index)") {
      calls.withLock { $0 += 1 }
      started.signal()
      _ = release.wait(timeout: .now() + 5)
      finished.leave()
      return Data([1])
    } == nil)
  }
  // Even slow snapshots return immediately to the frame renderer.
  #expect(ProcessInfo.processInfo.systemUptime - begin < 0.5)
  #expect(started.wait(timeout: .now() + 2) == .success)
  #expect(started.wait(timeout: .now() + 2) == .success)
  #expect(calls.withLock { $0 } == 2)
  // Another frame/worker asking for the same tile must not enqueue a second snapshot.
  #expect(try loader.request(key: "tile-0") {
    Issue.record("Duplicate snapshot request")
    return Data()
  } == nil)
  for _ in 0..<8 { release.signal() }
  #expect(finished.wait(timeout: .now() + 2) == .success)
  #expect(calls.withLock { $0 } == 8)
}

@Test
func offlineMapsDrawPlaceholderTilesAndRefuseRouting() throws {
  let cache = FileManager.default.temporaryDirectory.appendingPathComponent("map-cache-\(UUID())")
  MapServices.cacheDirectory = cache
  MapServices.isOffline = true
  defer {
    MapServices.isOffline = false
    MapServices.resetCacheDirectory()
    try? FileManager.default.removeItem(at: cache)
  }
  let data = try MapServices.tileData("motionmap://tile/apple/satellite/2/1/1")
  let image = try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
  #expect(image.width == 256 && image.height == 256)
  // Placeholders are never cached, so a later online render fetches the real tile.
  #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("tiles").path))
  let route = MapServices.route(#"{"mode":"driving","points":[[2.29,48.85],[2.35,48.85]]}"#)
  #expect(route.contains("offline"))
  #expect(MapServices.route(#"{"mode":"teleport","points":[[0,0],[1,1]]}"#).contains("Unsupported"))
  #expect(MapServices.route(#"{"mode":"driving","points":[[0,0]]}"#).contains("2–25"))
  let capabilities = try JSONSerialization.jsonObject(with: Data(MapServices.capabilitiesJSON().utf8)) as? [String: Bool]
  #expect(capabilities?["apple"] == MapServices.isAppleMapsAvailable)
}

@Test
func railRoutesFollowConnectedTrackBetweenSnappedStations() throws {
  // Two parallel lines; only the lower one connects the start to the end. The closest node
  // to the end sits on a disconnected siding and must not be chosen.
  let coordinates: [[Double]] = [
    [0, 0], [0.01, 0], [0.02, 0], [0.03, 0],          // main line 0…3
    [0.03, 0.002], [0.032, 0.002],                     // siding 4–5, near the end, disconnected
    [0, 0.005], [0.015, 0.005],                        // spur 6–7 near the start, disconnected
  ]
  let graph = RailGraph(coordinates: coordinates, ways: [[0, 1, 2, 3], [4, 5], [6, 7]])
  let path = try graph.path(from: [0, 0.0004], to: [0.0305, 0.0018], mode: "railway")
  #expect(path.first == [0, 0])
  #expect(path.last == [0.03, 0])
  #expect(path.count == 4)
  #expect(throws: MotionError.self) { try graph.path(from: [1, 1], to: [0.03, 0], mode: "railway") }
}
