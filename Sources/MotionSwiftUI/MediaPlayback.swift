import AVFoundation
import MotionCore

/// Main-actor audio voices follow evaluated media positions, including seeks and sequence exits.
@MainActor
final class MediaPlayback {
  private var voices: [String: AVPlayer] = [:]
  private var lastTimes: [String: Double] = [:]

  func pause() { for voice in voices.values { voice.pause() } }

  func reset() {
    pause()
    voices.removeAll()
    lastTimes.removeAll()
  }

  func synchronize(_ samples: [ActiveMedia], playing: Bool, muted: Bool) throws {
    let active = Set(samples.map(\.id))
    for id in Array(voices.keys) where !active.contains(id) {
      voices.removeValue(forKey: id)?.pause()
      lastTimes.removeValue(forKey: id)
    }
    for media in samples {
      let url = try MediaSource.url(media.src)
      let voice: AVPlayer
      if let existing = voices[media.id] { voice = existing } else {
        voice = AVPlayer(url: url)
        voices[media.id] = voice
      }
      if voice.status == .failed || voice.currentItem?.status == .failed {
        let message = voice.error?.localizedDescription ?? voice.currentItem?.error?.localizedDescription ?? media.src
        throw MotionError("Audio playback failed: \(message)")
      }
      voice.volume = muted ? 0 : Float(media.sample.volume)
      let actual = voice.currentTime().seconds
      let discontinuity = lastTimes[media.id].map { media.sample.time < $0 || media.sample.time - $0 > 0.2 } ?? true
      if !playing || discontinuity || !actual.isFinite || abs(actual - media.sample.time) > 0.15 {
        voice.seek(to: CMTime(seconds: media.sample.time, preferredTimescale: 60000),
                   toleranceBefore: .zero, toleranceAfter: .zero)
      }
      if playing && media.sample.volume > 0 && !muted {
        voice.rate = Float(media.sample.playbackRate)
      } else { voice.pause() }
      lastTimes[media.id] = media.sample.time
    }
  }
}
