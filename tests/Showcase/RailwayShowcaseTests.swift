import Foundation
import ImageIO
import MotionCore
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func realOpenStreetMapRailwayRendersAndStagesForEditing() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("railway-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let location = try ShowcaseExample.project(MapsShowcaseView.railwayProject, entry: "index.tsx").prepare(root: directory)
  #expect(FileManager.default.fileExists(atPath: location.project.appendingPathComponent("public/map.png").path))
  let player = MotionPlayer(configuration: .init(scale: 1, backend: .gpu))
  await player.load(.portable(project: location.project, entry: location.entry), compositionID: "IslandRailway")
  #expect(player.composition?.durationInFrames == 360)
  let first = try await player.render(frame: 0)
  let middle = try await player.render(frame: 180)
  let last = try await player.render(frame: 359)
  #expect(middle.image.width == 960)
  #expect(middle.image.height == 540)
  #expect(first.image.dataProvider?.data != middle.image.dataProvider?.data)
  #expect(middle.image.dataProvider?.data != last.image.dataProvider?.data)
  let repeated = try await player.render(frame: 180)
  #expect(repeated.image.dataProvider?.data == middle.image.dataProvider?.data)
  // Gallery previews load multiple projects together. A different project's public folder
  // must not redirect this player's railway image, including after replacing its worker.
  let other = MotionPlayer(configuration: .init(scale: 1, backend: .gpu))
  await other.load(.portable(project: MotionStudy.project, entry: "index.tsx"), compositionID: "Ribbon")
  #expect(other.status == .ready)
  #expect(MediaSource.publicDirectory == MotionStudy.project.appendingPathComponent("public"))
  player.update(configuration: .init(scale: 1, backend: .cpu))
  let isolated = try await player.render(frame: 180)
  #expect(isolated.image.width == 960)
  #expect(player.renderError == nil)
  if let output = ProcessInfo.processInfo.environment["MOTIONSWIFT_REVIEW_FRAMES"] {
    for (frame, image) in [(0, first.image), (180, middle.image), (359, last.image)] {
      let url = URL(fileURLWithPath: output).appendingPathComponent("IslandRailway-\(frame).png")
      let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      #expect(CGImageDestinationFinalize(destination))
    }
  }
}
