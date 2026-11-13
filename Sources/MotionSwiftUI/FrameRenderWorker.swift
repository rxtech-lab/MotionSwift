import CoreGraphics
import Foundation
import MotionCore
import MotionRender
import MotionRuntime

/// One rendered preview frame: a display image plus the CSS-pixel layout boxes that produced it.
public struct MotionFrame: @unchecked Sendable {
  /// Frame number within the composition.
  public let frame: Int
  /// Unpremultiplied sRGB image at `pixelWidth` × `pixelHeight`. CGImage is immutable.
  public let image: CGImage
  /// Layout boxes in composition (CSS) pixels, in paint order.
  public let layout: [LayoutBox]
  /// Evaluate + layout + paint + readback time in milliseconds.
  public let renderMs: Double
  /// The reconciled render tree, before preview overrides. The editor reads styles from it.
  public let tree: RenderNode
  /// Whether preview overrides were applied (such frames are never cached).
  public let overridden: Bool

  var byteCount: Int { image.bytesPerRow * image.height }
}

/// Renders preview frames on one dedicated thread that owns a JavaScriptCore runtime and a Skia
/// surface, matching the confinement rules of `Runtime` and `Renderer`. Display requests coalesce:
/// while scrubbing or playing, only the newest pending display frame is rendered.
final class FrameRenderWorker: Sendable {
  typealias Completion = @Sendable (Result<MotionFrame, any Error>) -> Void

  private let queue = JobQueue()

  init(bundle: String, composition: Composition, props: String, scale: Double, backend: RenderBackend,
       publicDirectory: URL? = nil) {
    let queue = queue
    let thread = Thread {
      MediaSource.withPublicDirectory(publicDirectory) {
        Self.run(
          queue: queue, bundle: bundle, composition: composition, props: props, scale: scale,
          backend: backend)
      }
    }
    thread.name = "motionswift.preview"
    // React and the reconciler recurse deeply; match the render pipeline's worker stack.
    thread.stackSize = 8 << 20
    thread.qualityOfService = .userInteractive
    thread.start()
  }

  deinit { queue.stop() }

  /// Queues `frame`. With `coalesces`, any earlier coalescing request that has not started is
  /// dropped without calling its completion.
  func request(
    _ frame: Int, overrides: [String: [String: JSONValue]] = [:], coalesces: Bool,
    completion: @escaping Completion
  ) {
    queue.push(JobQueue.Job(frame: frame, overrides: overrides, coalesces: coalesces, completion: completion))
  }

  private static func run(
    queue: JobQueue, bundle: String, composition: Composition, props: String, scale: Double,
    backend: RenderBackend
  ) {
    let runtime: Runtime
    let renderer: Renderer
    do {
      runtime = try Runtime(bundle: bundle)
      renderer = try Renderer(
        width: composition.width, height: composition.height, scale: scale, backend: backend)
    } catch {
      queue.fail(error)
      return
    }
    // Override frames reuse the last evaluated tree: gestures re-layout and re-paint only.
    var lastTree: (frame: Int, tree: RenderNode)?
    while let job = queue.next() {
      let result = autoreleasepool {
        Result { () throws -> MotionFrame in
          let begin = DispatchTime.now().uptimeNanoseconds
          let tree: RenderNode
          if let lastTree, lastTree.frame == job.frame {
            tree = lastTree.tree
          } else {
            tree = try runtime.frame(composition: composition, number: job.frame, props: props)
            lastTree = (job.frame, tree)
          }
          let layout = try renderer.draw(tree.applying(job.overrides), composition: composition)
          let image = try makeImage(
            try renderer.pixels(), width: renderer.pixelWidth, height: renderer.pixelHeight)
          let elapsed = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000
          return MotionFrame(
            frame: job.frame, image: image, layout: layout, renderMs: elapsed, tree: tree,
            overridden: !job.overrides.isEmpty)
        }
      }
      job.completion(result)
    }
  }

  /// Wraps unpremultiplied RGBA8888 rows (the renderer's readback format) without copying.
  static func makeImage(_ pixels: Data, width: Int, height: Int) throws -> CGImage {
    guard pixels.count == width * height * 4, let provider = CGDataProvider(data: pixels as CFData),
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
        decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { throw MotionError("Cannot create a preview image from rendered pixels") }
    return image
  }
}

/// Pending jobs shared between the owner and the render thread.
private final class JobQueue: @unchecked Sendable {
  struct Job {
    let frame: Int
    let overrides: [String: [String: JSONValue]]
    let coalesces: Bool
    let completion: FrameRenderWorker.Completion
  }

  private let condition = NSCondition()
  private var jobs: [Job] = []
  private var stopped = false
  private var failure: (any Error)?

  func push(_ job: Job) {
    condition.lock()
    if let failure {
      condition.unlock()
      job.completion(.failure(failure))
      return
    }
    if job.coalesces { jobs.removeAll(where: \.coalesces) }
    jobs.append(job)
    condition.signal()
    condition.unlock()
  }

  /// Next job, waiting until one arrives. Nil once stopped.
  func next() -> Job? {
    condition.lock()
    defer { condition.unlock() }
    while !stopped, jobs.isEmpty { condition.wait() }
    return stopped ? nil : jobs.removeFirst()
  }

  /// Fails queued and future jobs, for example when the runtime cannot start.
  func fail(_ error: any Error) {
    condition.lock()
    failure = error
    let pending = jobs
    jobs = []
    condition.unlock()
    pending.forEach { $0.completion(.failure(error)) }
  }

  func stop() {
    condition.lock()
    stopped = true
    let pending = jobs
    jobs = []
    condition.broadcast()
    condition.unlock()
    pending.filter { !$0.coalesces }.forEach {
      $0.completion(.failure(MotionError("Preview renderer was replaced or released")))
    }
  }
}
