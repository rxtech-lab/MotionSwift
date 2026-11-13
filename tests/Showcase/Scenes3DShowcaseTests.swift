import Foundation
import MotionCore
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func showcase3DScenesCompileAndRenderEveryScene() async throws {
  let player = MotionPlayer(configuration: .init(scale: 0.5, backend: .gpu))
  await player.load(Showcase3D.source)
  #expect(player.status == .ready)
  #expect(Set(player.compositions.map(\.id)) == Set(Showcase3D.scenes.map(\.id)))
  for scene in Showcase3D.scenes {
    player.select(compositionID: scene.id)
    let rendered = try await player.render(frame: 30)
    #expect(rendered.image.width == 320 && rendered.image.height == 180, "\(scene.id)")
    let canvas = try #require(rendered.tree.children.first?.children.first, "\(scene.id)")
    #expect(canvas.type == "ms-three" && canvas.scene != nil, "\(scene.id)")
    #expect(!scene.features.isEmpty)
  }
}
