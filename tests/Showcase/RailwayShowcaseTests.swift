import Foundation
import ImageIO
import MotionCore
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func fullYamanoteLoopRendersAndStagesForEditing() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("railway-\(UUID())")
  let previousOffline = MapServices.isOffline
  let previousCache = MapServices.cacheDirectory
  if ProcessInfo.processInfo.environment["MOTIONSWIFT_REVIEW_MAP_NETWORK"] != "1" {
    MapServices.isOffline = true
    MapServices.cacheDirectory = directory.appendingPathComponent("map-cache")
  }
  defer {
    MapServices.isOffline = previousOffline
    MapServices.cacheDirectory = previousCache
    try? FileManager.default.removeItem(at: directory)
  }
  let location = try ShowcaseExample.project(MapsShowcaseView.railwayProject, entry: "index.tsx").prepare(root: directory)
  #expect(FileManager.default.fileExists(atPath: location.project.appendingPathComponent("public/map.png").path))
  let player = MotionPlayer(configuration: .init(scale: 1, backend: .gpu))
  await player.load(.portable(project: location.project, entry: location.entry, stamp: true), compositionID: "IslandRailway")
  #expect(player.composition?.width == 1920)
  #expect(player.composition?.height == 1080)
  #expect(player.composition?.durationInFrames == 1500)
  let first = try await player.render(frame: 0)
  let middle = try await player.render(frame: 750)
  let last = try await player.render(frame: 1499)
  let overview = try #require(first.tree.editorElements.first { $0.type == "MapView" })
  let following = try #require(middle.tree.editorElements.first { $0.type == "MapView" })
  let finished = try #require(last.tree.editorElements.first { $0.type == "MapView" })
  #expect(overview.properties["zoom"]?.number == 13)
  #expect(following.properties["zoom"]?.number == 15)
  #expect(finished.properties["zoom"]?.number == 13)
  #expect(overview.properties["centerLongitude"] != following.properties["centerLongitude"])
  #expect(middle.tree.editorElements.filter { $0.type == "MapMarker" }.count == 31)
  #expect(middle.image.width == 1920)
  #expect(middle.image.height == 1080)
  #expect(first.image.dataProvider?.data != middle.image.dataProvider?.data)
  #expect(middle.image.dataProvider?.data != last.image.dataProvider?.data)
  let repeated = try await player.render(frame: 750)
  #expect(repeated.image.dataProvider?.data == middle.image.dataProvider?.data)
  // Gallery previews load multiple projects together. A different project's public folder
  // must not redirect this player's railway image, including after replacing its worker.
  let other = MotionPlayer(configuration: .init(scale: 1, backend: .gpu))
  await other.load(.portable(project: MotionStudy.project, entry: "index.tsx"), compositionID: "Ribbon")
  #expect(other.status == .ready)
  #expect(MediaSource.publicDirectory == MotionStudy.project.appendingPathComponent("public"))
  player.update(configuration: .init(scale: 1, backend: .cpu))
  let isolated = try await player.render(frame: 750)
  #expect(isolated.image.width == 1920)
  #expect(player.renderError == nil)
  if let output = ProcessInfo.processInfo.environment["MOTIONSWIFT_REVIEW_FRAMES"] {
    for (frame, image) in [(0, first.image), (750, middle.image), (1499, last.image)] {
      let url = URL(fileURLWithPath: output).appendingPathComponent("IslandRailway-\(frame).png")
      let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      #expect(CGImageDestinationFinalize(destination))
    }
  }
}
