import AVFoundation
import Foundation
import MotionCore
import MotionEncode
import MotionRender
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func mediaDemoRendersNestedClipsAtTheirBoundaries() async throws {
  let player = MotionPlayer(configuration: .init(scale: 0.2))
  await player.load(try MediaDemo.source())
  #expect(player.status == .ready)
  #expect(player.composition?.durationInFrames == 360)
  for (frame, voices) in [(0, 1), (89, 1), (90, 2), (149, 2), (150, 2), (239, 2), (240, 2), (359, 2)] {
    let rendered = try await player.render(frame: frame)
    #expect(rendered.tree.activeMedia.count == voices)
    #expect(rendered.image.width == 192)
    if frame == 90 || frame == 240 {
      let video = try #require(rendered.tree.activeMedia.first { $0.src.hasSuffix("motion.mp4") })
      #expect(video.sample.time == 1)
    }
    if frame == 239 {
      let video = try #require(rendered.tree.activeMedia.first { $0.src.hasSuffix("motion.mp4") })
      #expect(abs(video.sample.time - (1 + 149.0 / 30)) < 0.00001)
    }
  }
  // Repeated backwards seeks must reproduce the original decoded picture.
  let first = try await player.render(frame: 90)
  _ = try await player.render(frame: 239)
  let again = try await player.render(frame: 90)
  #expect(first.image.dataProvider?.data == again.image.dataProvider?.data)
}

@Test @MainActor
func mediaExportContainsVideoAndMixedAudio() async throws {
  let player = MotionPlayer(configuration: .init(scale: 0.1))
  await player.load(try MediaDemo.source())
  let bundle = try #require(player.bundle)
  let composition = try #require(player.composition)
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("media-export-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let output = directory.appendingPathComponent("demo.mp4")
  let video = try VideoStream(output: output, width: 96, height: 54, fps: 30)
  let audio = AudioMix(directory: directory, fps: 30)
  try FramePipeline.run(bundle: bundle, composition: composition, frames: Array(0..<360), props: "{}",
    options: .init(workers: 2, scale: 0.1)) { frame in
    try video.write(frame.pixels)
    try audio.append(frame.media)
  }
  try video.finish()
  try audio.mux(video: output)
  let asset = AVURLAsset(url: output)
  let duration = try await asset.load(.duration)
  #expect(abs(duration.seconds - 12) < 0.05)
  #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
  #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
  let pcm = try Data(contentsOf: directory.appendingPathComponent("mix.f32le"))
  let peak = pcm.withUnsafeBytes { $0.bindMemory(to: Float.self).map(abs).max() ?? 0 }
  #expect(peak > 0.005)
  #expect(peak <= 1)
}

@Test func audioMixPreservesSilentLeadInAndSequenceExit() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("audio-timing-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let audio = AudioMix(directory: directory, fps: 30)
  for _ in 0..<30 { try audio.append([]) }
  let source = try MediaDemo.asset("music", extension: "m4a").absoluteString
  for frame in 0..<30 {
    try audio.append([ActiveMedia(id: "music", src: source,
      sample: .init(time: 1 + Double(frame) / 30, playbackRate: 1.5, volume: 0.5))])
  }
  for _ in 0..<30 { try audio.append([]) }
  let data = try Data(contentsOf: directory.appendingPathComponent("mix.f32le"))
  #expect(data.count == 3 * 48000 * 2 * 4)
  data.withUnsafeBytes { bytes in
    let samples = bytes.bindMemory(to: Float.self)
    #expect(samples[0..<(48000 * 2)].allSatisfy { $0 == 0 })
    #expect(samples[(48000 * 2)..<(48000 * 4)].contains { abs($0) > 0.001 })
    #expect(samples[(48000 * 4)...].allSatisfy { $0 == 0 })
  }
}

@Test func segmentedMediaExportEncodesAudioOnceWithoutPrimingOffset() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("audio-segments-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let destination = directory.appendingPathComponent("joined.mp4")
  let transaction = try SegmentOutput(output: destination)
  let audio = AudioMix(directory: directory, fps: 15)
  let source = try MediaDemo.asset("music", extension: "m4a").absoluteString
  for segment in 0..<2 {
    let video = try VideoStream(output: transaction.segment(segment), width: 96, height: 54, fps: 15)
    for frame in 0..<15 {
      try video.write(Data(repeating: 0, count: 96 * 54 * 4))
      try audio.append(segment == 0 ? [] : [ActiveMedia(id: "music", src: source,
        sample: .init(time: Double(frame) / 15))])
    }
    try video.finish()
  }
  try transaction.publish(count: 2, beforePublish: { try audio.mux(video: $0) })
  let asset = AVURLAsset(url: destination)
  #expect(abs(try await asset.load(.duration).seconds - 2) < 0.001)
  let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
  #expect(try await video.load(.timeRange).start.seconds == 0)
  #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
}
