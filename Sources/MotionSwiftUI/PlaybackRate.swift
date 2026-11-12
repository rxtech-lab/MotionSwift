import Foundation

/// Counts preview deliveries over a rolling second, including cache hits.
/// Playhead jumps count as one delivery, regardless of how many source frames were skipped.
struct PlaybackRate {
  private var started: TimeInterval?
  private var deliveries: [TimeInterval] = []

  mutating func start(at time: TimeInterval) {
    started = time
    deliveries.removeAll(keepingCapacity: true)
  }

  mutating func record(at time: TimeInterval) { deliveries.append(time) }

  mutating func value(at time: TimeInterval) -> Double? {
    guard let started else { return nil }
    deliveries.removeAll { $0 <= time - 1 }
    let elapsed = min(time - started, 1)
    // Avoid a misleading spike from the first frame immediately after Play.
    guard elapsed >= 0.25 else { return nil }
    return Double(deliveries.count) / elapsed
  }
}
