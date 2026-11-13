#if os(macOS)
import Foundation
import MotionCore

/// Offline stereo mix sampled from exactly the same evaluated trees as the picture frames.
/// Decoded sources are memory-mapped scratch files, avoiding an in-memory whole-film cache.
public final class AudioMix {
  private let directory: URL
  private let fps: Double
  private var sources: [String: Data] = [:]
  private var silentSources: Set<String> = []
  private var output: FileHandle?
  private var frameCount = 0
  private let sampleRate = 48000.0
  private var pcm: URL { directory.appendingPathComponent("mix.f32le") }

  public init(directory: URL, fps: Double) {
    self.directory = directory
    self.fps = fps
  }

  deinit { try? output?.close() }

  public func append(_ media: [ActiveMedia]) throws {
    let first = Int((Double(frameCount) * sampleRate / fps).rounded())
    frameCount += 1
    let last = Int((Double(frameCount) * sampleRate / fps).rounded())
    let audible = media.filter { $0.sample.volume > 0 }
    if output == nil && audible.isEmpty { return }
    if output == nil {
      FileManager.default.createFile(atPath: pcm.path, contents: nil)
      output = try FileHandle(forWritingTo: pcm)
      try output?.seek(toOffset: UInt64(first * 8))
    }
    var mixed = [Float](repeating: 0, count: (last - first) * 2)
    for voice in audible {
      guard let source = try decode(voice.src) else { continue }
      source.withUnsafeBytes { bytes in
        let samples = bytes.bindMemory(to: Float.self)
        let count = samples.count / 2
        for index in 0..<(last - first) {
          let seconds = voice.sample.time + Double(index) / sampleRate * voice.sample.playbackRate
          let position = seconds * sampleRate
          guard position.isFinite, position >= 0, position < Double(count) else { continue }
          let lower = Int(position)
          let upper = min(lower + 1, count - 1)
          let fraction = Float(position - Double(lower))
          for channel in 0..<2 {
            let value = samples[lower * 2 + channel] * (1 - fraction) + samples[upper * 2 + channel] * fraction
            mixed[index * 2 + channel] += value * Float(voice.sample.volume)
          }
        }
      }
    }
    for index in mixed.indices { mixed[index] = min(1, max(-1, mixed[index])) }
    try mixed.withUnsafeBytes { try output?.write(contentsOf: Data($0)) }
  }

  private func decode(_ source: String) throws -> Data? {
    if let data = sources[source] { return data }
    if silentSources.contains(source) { return nil }
    let url = try MediaSource.url(source)
    let input = url.isFileURL ? url.path : url.absoluteString
    let probe = try Subprocess.run("ffprobe", ["-v", "error", "-select_streams", "a:0",
      "-show_entries", "stream=index", "-of", "csv=p=0", input])
    if probe.isEmpty { silentSources.insert(source); return nil }
    let target = directory.appendingPathComponent("audio-\(sources.count).f32le")
    try Subprocess.run("ffmpeg", ["-v", "error", "-y", "-i", input, "-map", "0:a:0", "-vn",
      "-ac", "2", "-ar", "48000", "-f", "f32le", target.path])
    let data = try Data(contentsOf: target, options: .alwaysMapped)
    sources[source] = data
    return data
  }

  /// Replaces a completed silent movie with a movie containing its synchronized AAC mix.
  public func mux(video: URL) throws {
    guard let output else { return }
    try output.close()
    self.output = nil
    let target = directory.appendingPathComponent("mixed." + video.pathExtension)
    try Subprocess.run("ffmpeg", ["-v", "error", "-y", "-i", video.path,
      "-f", "f32le", "-ar", "48000", "-ac", "2", "-i", pcm.path,
      "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
      "-t", String(Double(frameCount) / fps), target.path])
    guard rename(target.path, video.path) == 0 else { throw MotionError("Cannot publish mixed audio") }
  }
}
#endif
