import Foundation
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func compositionNavigationMapsInstancesAndRestoresAncestorPlayheads() async throws {
  let player = MotionPlayer(configuration: .init(scale: 0.1))
  await player.load(try MediaDemo.source(), compositionID: MediaDemo.rootCompositionID)
  #expect(player.status == .ready)
  #expect(Set(player.compositions.map(\.id)) == ["MasterComposition", "MediaMontage", "ImageClip", "VideoClip"])
  #expect(player.composition?.durationInFrames == 720)
  let navigation = MediaCompositionNavigation()
  let montage = try #require(MediaDemo.clips["MasterComposition"]?.first { $0.id == "montage-b" })
  player.seek(to: 480)
  navigation.open(montage, player: player)
  #expect(player.composition?.id == "MediaMontage")
  #expect(player.currentFrame == 120)
  let inset = try #require(MediaDemo.clips["MediaMontage"]?.first { $0.id == "inset" })
  navigation.open(inset, player: player)
  #expect(player.composition?.id == "VideoClip")
  #expect(player.currentFrame == 30)
  #expect(navigation.parents.map(\.compositionID) == ["MasterComposition", "MediaMontage"])
  player.seek(to: 80)
  navigation.back(to: 1, player: player)
  #expect(player.composition?.id == "MediaMontage")
  #expect(player.currentFrame == 120)
  navigation.open(inset, player: player)
  navigation.back(to: 0, player: player)
  #expect(player.composition?.id == "MasterComposition")
  #expect(player.currentFrame == 480)
  #expect(navigation.parents.isEmpty)
  // Opening an inactive instance from the timeline clamps to its child range.
  let image = try #require(MediaDemo.clips["MasterComposition"]?.first { $0.id == "image" })
  navigation.open(image, player: player)
  #expect(player.currentFrame == 149)
  navigation.back(to: 0, player: player)
  player.seek(to: 0)
  navigation.open(montage, player: player)
  #expect(player.currentFrame == 0)
}

@Test @MainActor
func parentIncludesTheSameSmallerCompositionPixelsAndAudio() async throws {
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(try MediaDemo.source(), compositionID: MediaDemo.rootCompositionID)
  let parent = try await player.render(frame: 420) // Instance B, local frame 60.
  player.select(compositionID: "MediaMontage")
  let child = try await player.render(frame: 60)
  let parentPixels = try #require(parent.image.dataProvider?.data as Data?)
  let childPixels = try #require(child.image.dataProvider?.data as Data?)
  for row in 0..<540 {
    let parentOffset = (row + 90) * parent.image.bytesPerRow + 32 * 4
    let childOffset = row * child.image.bytesPerRow
    #expect(parentPixels[parentOffset..<(parentOffset + 960 * 4)] == childPixels[childOffset..<(childOffset + 960 * 4)])
  }
  #expect(parent.tree.activeMedia.map(\.sample) == child.tree.activeMedia.map(\.sample))
  #expect(parent.tree.activeMedia.first?.sample.time == 2)
}
