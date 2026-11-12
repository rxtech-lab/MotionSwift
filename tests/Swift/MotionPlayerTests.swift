import Foundation
import MotionCompiler
import MotionCore
import MotionRender
import MotionRuntime
import MotionSwiftUI
import Testing

private var repository: URL {
  URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
}

private var source: MotionSource {
  .project(
    repository: repository, project: repository.appendingPathComponent("tests/compositions"),
    entry: "src/index.ts")
}

/// Polls the main actor until `condition` holds; the player delivers frames asynchronously.
@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
  for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
  #expect(condition())
}

@MainActor
@Test func playerLoadsSelectsAndRendersFrames() async throws {
  let player = MotionPlayer(configuration: .init(scale: 2))
  await player.load(source, compositionID: "Motion")
  #expect(player.status == .ready)
  #expect(player.compositions.map(\.id).contains("Timed"))
  #expect(player.composition?.id == "Motion")

  let frame = try await player.render(frame: 15)
  #expect(frame.frame == 15)
  #expect(frame.image.width == 640)
  #expect(frame.image.height == 360)
  // The moving 60×60 square, in composition (CSS) pixels.
  #expect(frame.layout.contains { $0.width == 60 && $0.height == 60 && $0.y == 50 })

  // The preview must match the pixels the CLI renderer produces for the same frame.
  let bundle = try #require(player.bundle)
  let composition = try #require(player.composition)
  let renderer = try Renderer(width: 320, height: 180, scale: 2)
  try renderer.draw(Runtime(bundle: bundle).frame(composition: composition, number: 15),
    composition: composition)
  let expected = try renderer.pixels()
  let provided = try #require(frame.image.dataProvider?.data as Data?)
  #expect(provided == expected)

  player.seek(to: 29)
  try await waitUntil { player.displayedFrame?.frame == 29 }
  player.seek(to: 99)
  #expect(player.currentFrame == 29)
}

@MainActor
@Test func playerPlaysAndStopsAtEndWithoutLooping() async throws {
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(source, compositionID: "Timed")
  player.loops = false
  player.play()
  #expect(player.isPlaying)
  try await waitUntil { (player.liveFPS ?? 0) > 0 }
  #expect((player.renderFPS ?? 0) > 0)
  try await waitUntil { !player.isPlaying }
  #expect(player.liveFPS == nil)
  #expect(player.currentFrame == 29)
  try await waitUntil { player.displayedFrame?.frame == 29 }
}

@MainActor
@Test func playerReportsCompileAndRenderFailures() async throws {
  let player = MotionPlayer()
  await player.load(.bundle("throw new Error('broken bundle')"))
  guard case .failed(let message) = player.status else {
    Issue.record("Expected a failed status, got \(player.status)")
    return
  }
  #expect(message.contains("broken bundle"))
  #expect(player.composition == nil)
  await #expect(throws: MotionError.self) { _ = try await player.render(frame: 0) }
}
