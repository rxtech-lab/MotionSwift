import Foundation
import MotionCore
import MotionRuntime
import SkiaKit

public typealias RenderBackend = Backend

/// One rendered frame, delivered to the consumer in presentation order.
public struct RenderedFrame: Sendable {
  public let index: Int
  public let frame: Int
  public let pixels: Data
  public let videoFrame: MetalVideoFrame?
  public let layout: [LayoutBox]
  /// Evaluate + layout + paint + CPU readback or shared GPU resolve time.
  public let renderMs: Double
}

public struct PipelineOptions: Sendable {
  public var workers: Int
  public var backend: RenderBackend
  public var scale: Double
  public var sharedVideoFrames: Bool
  /// Frames that may be finished but not yet consumed; bounds memory for large surfaces.
  public var window: Int

  public init(
    workers: Int, backend: RenderBackend = .cpu, scale: Double = 1, window: Int? = nil,
    sharedVideoFrames: Bool = false
  ) {
    self.workers = max(1, workers)
    self.backend = backend
    self.scale = scale
    self.sharedVideoFrames = sharedVideoFrames
    self.window = max(self.workers, window ?? self.workers * 2)
  }
}

/// Renders frames on `workers` threads. Each worker owns a JavaScript runtime and a Skia
/// surface (and, for the GPU backend, its own Metal command queue and Ganesh context), so
/// nothing mutable is shared between workers. Frames are evaluated in fresh JS VMs, so
/// output is independent of which worker renders a frame or in which order.
public enum FramePipeline {
  public static func run(
    bundle: String, composition: Composition, frames: [Int], props: String,
    options: PipelineOptions, consume: (RenderedFrame) throws -> Void
  ) throws {
    guard !frames.isEmpty else { return }
    guard !options.sharedVideoFrames || options.backend == .gpu else {
      throw MotionError("Shared video frames require --backend=gpu")
    }
    let state = PipelineState(count: frames.count, window: options.window)
    let workers = min(options.workers, frames.count)
    let group = DispatchGroup()
    for _ in 0..<workers {
      group.enter()
      let thread = Thread {
        defer { group.leave() }
        worker(
          state: state, bundle: bundle, composition: composition, frames: frames, props: props,
          options: options)
      }
      thread.name = "motionswift.render"
      thread.stackSize = 8 << 20
      thread.qualityOfService = .userInitiated
      thread.start()
    }
    defer {
      state.cancel()
      group.wait()
    }
    for index in frames.indices {
      let frame = try state.take(index)
      do { try consume(frame) } catch {
        state.fail(error)
        throw error
      }
    }
  }

  private static func worker(
    state: PipelineState, bundle: String, composition: Composition, frames: [Int], props: String,
    options: PipelineOptions
  ) {
    do {
      let runtime = try Runtime(bundle: bundle)
      let renderer = try Renderer(
        width: composition.width, height: composition.height, scale: options.scale,
        backend: options.backend)
      while let index = state.claim() {
        let begin = DispatchTime.now().uptimeNanoseconds
        let tree = try runtime.frame(composition: composition, number: frames[index], props: props)
        let layout = try renderer.draw(tree, composition: composition)
        let videoFrame = options.sharedVideoFrames ? try renderer.videoFrame() : nil
        let pixels = options.sharedVideoFrames ? Data() : try renderer.pixels()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000
        state.complete(
          RenderedFrame(
            index: index, frame: frames[index], pixels: pixels, videoFrame: videoFrame,
            layout: layout, renderMs: elapsed))
      }
    } catch {
      state.fail(error)
    }
  }
}

/// Work queue plus ordered, bounded hand-off buffer shared by the pipeline threads.
private final class PipelineState: @unchecked Sendable {
  private let condition = NSCondition()
  private let count: Int
  private let window: Int
  private var next = 0
  private var consumed = 0
  private var finished: [Int: RenderedFrame] = [:]
  private var error: (any Error)?
  private var cancelled = false

  init(count: Int, window: Int) {
    self.count = count
    self.window = window
  }

  /// Next frame index to render, waiting while the reorder window is full. Nil when done.
  func claim() -> Int? {
    condition.lock()
    defer { condition.unlock() }
    while !cancelled, error == nil, next < count, next >= consumed + window { condition.wait() }
    guard !cancelled, error == nil, next < count else { return nil }
    next += 1
    return next - 1
  }

  func complete(_ frame: RenderedFrame) {
    condition.lock()
    finished[frame.index] = frame
    condition.broadcast()
    condition.unlock()
  }

  func fail(_ failure: any Error) {
    condition.lock()
    if error == nil { error = failure }
    condition.broadcast()
    condition.unlock()
  }

  func cancel() {
    condition.lock()
    cancelled = true
    condition.broadcast()
    condition.unlock()
  }

  func take(_ index: Int) throws -> RenderedFrame {
    condition.lock()
    defer { condition.unlock() }
    while finished[index] == nil, error == nil { condition.wait() }
    if let error { throw error }
    guard let frame = finished.removeValue(forKey: index) else {
      throw MotionError("Frame \(index) was not rendered")
    }
    consumed = index + 1
    condition.broadcast()
    return frame
  }
}
