import Foundation
import MotionCore
import MotionRender
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func sharedGalleryPreviewPreservesStaticAssets() async throws {
  let configuration = MotionPlayer.Configuration(scale: 0.5, backend: .cpu)
  let parent = MotionPlayer(configuration: configuration)
  await parent.load(.portable(project: ShowcaseDefaults.project, entry: ShowcaseDefaults.entry),
                    compositionID: "ExternalSVG")
  #expect(parent.status == .ready)
  let expected = try await parent.render(frame: 0)
  let shared = try #require(parent.compiledSource)

  // Another project's load must not change where a shared preview resolves its assets.
  let other = MotionPlayer(configuration: configuration)
  await other.load(.portable(project: MotionStudy.project, entry: "index.tsx"))
  #expect(other.status == .ready)

  let tile = MotionPlayer(configuration: configuration)
  await tile.load(shared, compositionID: "ExternalSVG")
  #expect(tile.status == .ready)
  for backend in RenderBackend.allCases {
    tile.update(configuration: .init(scale: 0.5, backend: backend))
    let frame = try await tile.render(frame: 0)
    #expect(frame.image.width == 160)
    #expect(frame.image.height == 90)
    #expect(tile.renderError == nil)
    if backend == .cpu {
      #expect(frame.image.dataProvider?.data == expected.image.dataProvider?.data)
    }
  }
}
