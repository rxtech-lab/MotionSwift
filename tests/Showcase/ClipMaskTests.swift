import MotionRender
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func showcaseClipMaskPreviewRendersOnBothBackends() async throws {
  for backend in RenderBackend.allCases {
    let player = MotionPlayer(configuration: .init(scale: 0.5, backend: backend))
    await player.load(.portable(project: ShowcaseDefaults.project, entry: ShowcaseDefaults.entry), compositionID: "ClipMask")
    #expect(player.status == .ready)
    for frame in [0, 15, 29] {
      let rendered = try await player.render(frame: frame)
      #expect(rendered.image.width == 160)
      #expect(rendered.image.height == 90)
      #expect(player.renderError == nil)
    }
  }
}
