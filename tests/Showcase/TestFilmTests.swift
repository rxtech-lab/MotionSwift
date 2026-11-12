import AVFoundation
import Foundation
import MotionCore
import MotionEditor
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

/// The showcase's Visual Editor opens a writable copy of the sample and edits it, never the repo.
@Test @MainActor
func showcaseEditorEditsACopyOfTheSampleProject() async throws {
  let sample = try EditorWorkspace.prepareSample(reset: true)
  #expect(sample.path.hasPrefix(EditorWorkspace.root.path))
  let model = EditorModel(project: sample, entry: ShowcaseDefaults.entry, configuration: .init(scale: 1))
  await model.open(compositionID: "Cards")
  for _ in 0..<500 where model.player.displayedFrame == nil { try await Task.sleep(for: .milliseconds(10)) }
  model.select(at: CGPoint(x: 400, y: 200))
  #expect(model.selection == "src/Cards.tsx:7:3")
  for _ in 0..<500 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  await model.setStyle("borderRadius", .number(40))
  let edited = try String(contentsOf: sample.appendingPathComponent("src/Cards.tsx"), encoding: .utf8)
  #expect(edited.contains("height: 180, borderRadius: 40"))
  let original = try String(
    contentsOf: EditorWorkspace.bundledSample.appendingPathComponent("src/Cards.tsx"), encoding: .utf8)
  #expect(original.contains("height: 180, borderRadius: 90"))
  let track = try #require(model.timelineTracks.first { $0.src == model.selection })
  model.selectTrack(track)
  await model.setTiming(of: track.src, start: 10, duration: 50)
  await model.setKeyframe(of: track.src, key: "left", frame: 10, value: 320)
  await model.setKeyframe(of: track.src, key: "left", frame: 30, value: 400)
  let frame = try await model.player.render(frame: 20)
  #expect(frame.layout.first { $0.source == track.src }?.x == 360)
  #expect(try String(contentsOf: sample.appendingPathComponent("src/Cards.tsx"), encoding: .utf8)
    .contains("data-ms-timeline"))
  #expect(try String(contentsOf: EditorWorkspace.bundledSample.appendingPathComponent("src/Cards.tsx"), encoding: .utf8)
    == original)
  _ = try EditorWorkspace.prepareSample(reset: true)
}
