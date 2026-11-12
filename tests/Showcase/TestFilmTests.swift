import AVFoundation
import Foundation
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func showcaseLoadsTheExactBenchmarkFilmAndRendersItsFrames() async throws {
  let project = try TestFilmFixture.prepare(repository: ShowcaseDefaults.repository)
  defer { try? FileManager.default.removeItem(at: project) }
  let player = MotionPlayer(configuration: .init(scale: 0.25, backend: .cpu))
  await player.load(
    .project(repository: ShowcaseDefaults.repository, project: project, entry: "src/index.ts"), compositionID: "Main")
  #expect(player.status == .ready)
  #expect(player.composition?.id == "Main")
  #expect(player.composition?.durationInFrames == 2700)
  #expect(player.composition?.width == 1920)
  #expect(player.composition?.height == 1080)
  let first = try await player.render(frame: 0)
  let middle = try await player.render(frame: 1350)
  let last = try await player.render(frame: 2699)
  #expect(first.image.width == 480 && first.image.height == 270)
  #expect(middle.frame == 1350)
  #expect(last.frame == 2699)
  #expect((AppMemory.residentBytes() ?? 0) > 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MOTIONSWIFT_TEST_HARDWARE"] == "1"))
@MainActor
func showcaseExportsFullBenchmarkFilmWithMemory() async throws {
  let project = try TestFilmFixture.prepare(repository: ShowcaseDefaults.repository)
  defer { try? FileManager.default.removeItem(at: project) }
  let player = MotionPlayer(configuration: .init(scale: 0.25, backend: .cpu))
  await player.load(
    .project(repository: ShowcaseDefaults.repository, project: project, entry: "src/index.ts"), compositionID: "Main")
  let bundle = try #require(player.bundle)
  let composition = try #require(player.composition)
  let output = FileManager.default.temporaryDirectory.appendingPathComponent("showcase-test-film-\(UUID()).mp4")
  defer { try? FileManager.default.removeItem(at: output) }
  let job = FilmExport()
  let baseline = try #require(AppMemory.residentBytes())
  // Reuse the same process and exporter to catch accumulation across exports.
  for run in 1...2 {
    await job.render(bundle: bundle, composition: composition, destination: output, workers: 8)
    #expect(job.error == nil)
    #expect(job.output == output)
    #expect(!job.isRunning)
    #expect(job.completedFrames == 2700)
    let peak = try #require(job.peakBytes)
    #expect(peak > 0)
    // Eight 1080p workers and a bounded 16-frame window should not retain gigabytes
    // of per-frame JS/Metal temporaries. The old loop grew by over 8 GiB per film.
    #expect(peak < baseline + (1 << 30))
    // Idle samples must not change the completed render's peak.
    job.sampleMemory()
    #expect(job.peakBytes == peak)
    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration)
    #expect(abs(CMTimeGetSeconds(duration) - 90) < 0.01)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let size = try await track.load(.naturalSize)
    #expect(size.width == 1920 && size.height == 1080)
    print("Showcase full-film export run \(run): 2700 frames, 1080p, 90 s; "
      + "baseline RSS \(AppMemory.formatted(baseline)); peak RSS \(AppMemory.formatted(peak)); "
      + "end RSS \(AppMemory.formatted(job.currentBytes))")
  }
}
