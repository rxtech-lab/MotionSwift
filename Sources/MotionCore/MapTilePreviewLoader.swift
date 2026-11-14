import Foundation

/// Deduplicates background tile loads across preview workers, bounds concurrency per provider, and
/// coalesces resolution notifications so bursts of tiles do not thrash live playback.
final class MapTilePreviewLoader: @unchecked Sendable {
  private enum State {
    case loading
    case failed(String, Date)
  }
  private let states = LockedValue<[String: State]>([:])
  private let notifyScheduled = LockedValue<Bool>(false)
  private let snapshotQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "motionswift.map.snapshots"
    queue.maxConcurrentOperationCount = 2
    queue.qualityOfService = .userInitiated
    return queue
  }()
  private let networkQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "motionswift.map.tiles"
    queue.maxConcurrentOperationCount = 6
    queue.qualityOfService = .userInitiated
    return queue
  }()

  func request(key: String, isSnapshot: Bool = true, load: @escaping @Sendable () throws -> Data) throws -> Data? {
    let enqueue = try states.withLock { states in
      if let state = states[key] {
        switch state {
        case .loading: return false
        case .failed(let message, let expiry) where expiry > Date(): throw MotionError(message)
        case .failed: break
        }
      }
      states[key] = .loading
      return true
    }
    if enqueue {
      let target = isSnapshot ? snapshotQueue : networkQueue
      target.addOperation { [self] in
        do {
          _ = try load()
          states.withLock { $0[key] = nil }
        } catch {
          states.withLock { $0[key] = .failed(String(describing: error), Date().addingTimeInterval(30)) }
        }
        let shouldSchedule = notifyScheduled.withLock { scheduled in
          if scheduled { return false }
          scheduled = true
          return true
        }
        if shouldSchedule {
          DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [self] in
            notifyScheduled.withLock { $0 = false }
            NotificationCenter.default.post(name: MapServices.tilesDidResolve, object: nil)
          }
        }
      }
    }
    return nil
  }
}
