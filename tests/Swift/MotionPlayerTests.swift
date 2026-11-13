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

@MainActor
@Test(arguments: [0, 20])
func playerKeepsCachedSeekAheadOfPendingRenders(target: Int) async throws {
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(source, compositionID: "Motion")
  player.seek(to: target)
  try await waitUntil { player.displayedFrame?.frame == target }

  // Both seeks run in one main-actor turn: the worker's old delivery cannot be
  // processed until after the cached picture has already been presented.
  player.seek(to: 10)
  player.seek(to: target)
  #expect(player.displayedFrame?.frame == target)
  _ = try await player.render(frame: 21) // Drain the render worker.
  try await Task.sleep(for: .milliseconds(100))
  #expect(player.displayedFrame?.frame == target)
  #expect(player.currentFrame == target)
}

@MainActor
@Test func playerKeepsRestartAheadOfPendingEndFrame() async throws {
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(source, compositionID: "Motion")
  try await waitUntil { player.displayedFrame?.frame == 0 }

  player.seek(to: 29)
  player.play() // Restart at the cached first frame while frame 29 is pending.
  player.pause()
  #expect(player.displayedFrame?.frame == 0)
  _ = try await player.render(frame: 1)
  try await Task.sleep(for: .milliseconds(100))
  #expect(player.displayedFrame?.frame == 0)
  #expect(player.currentFrame == 0)
}

@MainActor
@Test func playerLoopsAcrossRepeatedEndBoundaries() async throws {
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(source, compositionID: "Timed")
  try await waitUntil { player.displayedFrame?.frame == 0 }
  player.seek(to: 27)
  try await waitUntil { player.displayedFrame?.frame == 27 }
  player.play()
  for _ in 0..<2 {
    try await waitUntil { player.currentFrame < 5 }
    #expect(player.isPlaying)
    #expect(player.renderError == nil)
    try await waitUntil { (player.displayedFrame?.frame ?? 29) < 10 }
    try await waitUntil { player.currentFrame >= 27 }
  }
  player.pause()
}
