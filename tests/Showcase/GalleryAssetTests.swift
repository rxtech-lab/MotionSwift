import Foundation
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func galleryBundleRetainsAssetsAcrossPlayersAndBackends() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gallery-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let location = try ShowcaseExample.project(ShowcaseDefaults.project, entry: ShowcaseDefaults.entry)
    .prepare(root: directory)
  let main = MotionPlayer(configuration: .init(scale: 1))
  await main.load(.portable(project: location.project, entry: location.entry))
  #expect(main.status == .ready)
  let source = try #require(main.compiledSource)
  // Another project's load must not redirect the gallery tile's staticFile() lookups.
  let other = MotionPlayer()
  await other.load(.portable(project: MotionStudy.project, entry: "index.tsx"))
  let tile = MotionPlayer(configuration: .init(scale: 1))
  await tile.load(source, compositionID: "ExternalSVG")
  #expect(tile.status == .ready)
  let cpu = try await tile.render(frame: 15)
  #expect(cpu.image.width == 320)
  tile.update(configuration: .init(scale: 1, backend: .gpu))
  let gpu = try await tile.render(frame: 15)
  #expect(gpu.image.width == 320)
  #expect(tile.renderError == nil)
}
