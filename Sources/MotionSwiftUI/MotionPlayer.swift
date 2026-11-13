import Foundation
#if os(macOS)
import MotionCompiler
#endif
import MotionCore
import MotionPortable
import MotionRender
import MotionRuntime
import Observation
import SkiaKit

/// Where a player gets its compiled JavaScript bundle.
public enum MotionSource: Sendable, Equatable {
  /// An already compiled bundle, for example one shared from another player.
  case bundle(String)
  /// A module graph from the portable compiler, a Mac (`motionswift graph`) or the cloud, linked
  /// with the precompiled vendor graph. Works on every platform.
  case graph(ModuleGraph)
  /// A TSX project compiled in JavaScriptCore by the portable compiler (iOS, iPadOS and macOS; no
  /// Node, no JIT required). `stamp` adds editor source stamps.
  case portable(project: URL, entry: String, stamp: Bool = false)
  /// In-memory project files compiled by the portable compiler.
  case files([String: String], entry: String, stamp: Bool = false)
  #if os(macOS)
  /// A Remotion-style TSX project compiled with bundled native TypeScript 7 (tsgo). macOS only.
  /// `repository` is retained for source compatibility; tools and runtime assets come from the package bundle.
  case project(repository: URL, project: URL, entry: String)
  #endif

  /// The project's `public/` folder for `staticFile()` assets, when the source is a project directory.
  var publicDirectory: URL? {
    switch self {
    case .portable(let project, _, _): return project.appendingPathComponent("public")
    #if os(macOS)
    case .project(_, let project, _): return project.appendingPathComponent("public")
    #endif
    default: return nil
    }
  }

  func compile() throws -> String {
    switch self {
    case .bundle(let bundle): return bundle
    case .graph(let graph): return try GraphLinker.link(graph)
    case .portable(let project, let entry, let stamp):
      return try GraphLinker.link(PortableCompiler().compile(project: project, entry: entry, stamp: stamp))
    case .files(let files, let entry, let stamp):
      return try GraphLinker.link(PortableCompiler().compile(files: files, entry: entry, stamp: stamp))
    #if os(macOS)
    case .project(let repository, let project, let entry):
      return try Compiler(repository: repository).compile(project: project, entry: entry)
    #endif
    }
  }
}

/// Drives a live preview of one composition: compiles a source, lists its compositions, renders
/// frames on a dedicated thread and plays them back at the composition's frame rate.
///
/// All state is main-actor isolated, so SwiftUI views can observe it directly.
@MainActor
@Observable
public final class MotionPlayer {
  public struct Configuration: Sendable, Equatable {
    /// Output pixels per composition pixel. 2 suits Retina displays.
    public var scale: Double
    public var backend: RenderBackend
    /// Upper bound for cached rendered frames, so replay and scrubbing skip re-rendering.
    public var cacheBytes: Int

    public init(scale: Double = 2, backend: RenderBackend = .cpu, cacheBytes: Int = 256 << 20) {
      self.scale = scale
      self.backend = backend
      self.cacheBytes = cacheBytes
    }
  }

  public enum Status: Sendable, Equatable {
    case idle
    case loading
    case ready
    case failed(String)
  }

  public private(set) var status: Status = .idle
  public private(set) var compositions: [Composition] = []
  public private(set) var composition: Composition?
  /// The frame the playhead is on. `displayedFrame` may briefly lag while it renders.
  public private(set) var currentFrame = 0
  public private(set) var displayedFrame: MotionFrame?
  /// The last frame render error. Rendering stops at unsupported styles instead of guessing.
  public private(set) var renderError: String?
  public private(set) var isPlaying = false
  /// Distinct preview-frame deliveries per wall-clock second, over a rolling one-second window.
  /// Includes cached frames; nil while paused or during the first quarter-second of playback.
  /// This measures updates delivered to SwiftUI, not physical display refreshes.
  public private(set) var liveFPS: Double?
  /// Throughput implied by the displayed frame's measured render time, excluding playback pacing.
  public var renderFPS: Double? {
    guard let milliseconds = displayedFrame?.renderMs, milliseconds.isFinite, milliseconds > 0 else { return nil }
    return 1000 / milliseconds
  }
  public private(set) var configuration: Configuration
  public private(set) var props = "{}"
  /// The compiled bundle, reusable through `MotionSource.bundle` without recompiling.
  public private(set) var bundle: String?
  public var loops = true
  public var isMuted = false {
    didSet { synchronizeAudio() }
  }
  /// Live style patches keyed by source stamp, applied on top of the reconciled tree of the
  /// current frame without re-running JavaScript. Frames rendered with overrides are not cached.
  public private(set) var previewOverrides: [String: [String: JSONValue]] = [:]

  @ObservationIgnored private let mediaPlayback = MediaPlayback()
  @ObservationIgnored private var worker: FrameRenderWorker?
  @ObservationIgnored private var loadGeneration = 0
  @ObservationIgnored private var renderGeneration = 0
  @ObservationIgnored private var playback: Task<Void, Never>?
  @ObservationIgnored private var playbackRate = PlaybackRate()
  @ObservationIgnored private let cache = NSCache<NSNumber, CachedFrame>()

  public init(configuration: Configuration = Configuration()) {
    self.configuration = configuration
    cache.totalCostLimit = configuration.cacheBytes
  }

  // MARK: Loading

  /// Recompiles `source` and keeps the composition, playhead and displayed picture until the new
  /// frame arrives (hot reload). Clears preview overrides once the reloaded frame is requested.
  public func reload(_ source: MotionSource) async {
    let compositionID = composition?.id
    let frame = currentFrame
    await load(source, compositionID: compositionID, preservingFrame: frame)
  }

  /// Compiles `source` off the main thread and selects `compositionID`, or the first composition.
  public func load(_ source: MotionSource, compositionID: String? = nil) async {
    await load(source, compositionID: compositionID, preservingFrame: nil)
  }

  private func load(_ source: MotionSource, compositionID: String?, preservingFrame: Int?) async {
    pause()
    loadGeneration += 1
    let generation = loadGeneration
    mediaPlayback.reset()
    if let folder = source.publicDirectory { MediaSource.publicDirectory = folder }
    status = .loading
    do {
      let (bundle, catalog) = try await Self.onLargeStack {
        let bundle = try source.compile()
        return (bundle, try Runtime(bundle: bundle).compositions())
      }
      guard generation == loadGeneration else { return }
      self.bundle = bundle
      compositions = catalog
      status = .ready
      let selected = catalog.first { $0.id == compositionID } ?? catalog[0]
      if let preservingFrame, selected.id == composition?.id {
        composition = selected
        currentFrame = min(preservingFrame, selected.durationInFrames - 1)
        previewOverrides = [:]
        restartWorker()
      } else {
        select(compositionID: selected.id)
      }
    } catch {
      guard generation == loadGeneration else { return }
      worker = nil
      bundle = nil
      compositions = []
      composition = nil
      displayedFrame = nil
      status = .failed(String(describing: error))
    }
  }

  /// Switches to another composition from the loaded catalog and shows its first frame.
  public func select(compositionID: String) {
    guard let selected = compositions.first(where: { $0.id == compositionID }) else { return }
    pause()
    mediaPlayback.reset()
    composition = selected
    currentFrame = 0
    displayedFrame = nil
    restartWorker()
  }

  /// Replaces the input props (a JSON object) and re-renders the current frame.
  public func setProps(_ json: String) throws {
    guard (try JSONSerialization.jsonObject(with: Data(json.utf8))) is [String: Any] else {
      throw MotionError("Props must be a JSON object")
    }
    props = json
    restartWorker()
  }

  public func update(configuration: Configuration) {
    guard configuration != self.configuration else { return }
    self.configuration = configuration
    cache.totalCostLimit = configuration.cacheBytes
    restartWorker()
  }

  /// Replaces the preview overrides and re-renders the current frame with them.
  public func setPreviewOverrides(_ overrides: [String: [String: JSONValue]]) {
    guard overrides != previewOverrides else { return }
    previewOverrides = overrides
    show(currentFrame)
  }

  // MARK: Transport

  public func seek(to frame: Int) {
    guard let composition else { return }
    let resume = isPlaying
    if resume { pause() }
    show(min(max(frame, 0), composition.durationInFrames - 1))
    if resume { play() }
  }

  public func step(by frames: Int) {
    pause()
    seek(to: currentFrame + frames)
  }

  public func togglePlayback() {
    if isPlaying { pause() } else { play() }
  }

  public func play() {
    guard let composition, !isPlaying, renderError == nil else { return }
    let duration = composition.durationInFrames
    if currentFrame >= duration - 1 { show(0) }
    isPlaying = true
    synchronizeAudio()
    guard isPlaying else { return }
    liveFPS = nil
    playbackRate.start(at: ProcessInfo.processInfo.systemUptime)
    let fps = composition.fps
    let startFrame = currentFrame
    let start = ContinuousClock.now
    playback = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1 / fps))
        guard let self, !Task.isCancelled else { return }
        let elapsed = start.duration(to: .now)
        let seconds = Double(elapsed.components.seconds)
          + Double(elapsed.components.attoseconds) / 1e18
        var next = startFrame + Int(seconds * fps)
        if next >= duration {
          guard loops else {
            show(duration - 1)
            pause()
            return
          }
          next %= duration
        }
        if next != currentFrame { show(next) }
        refreshLiveFPS()
      }
    }
  }

  public func pause() {
    playback?.cancel()
    playback = nil
    isPlaying = false
    mediaPlayback.pause()
    liveFPS = nil
  }

  /// Renders `frame` (bypassing display coalescing) and returns it, for snapshots and tests.
  public func render(frame: Int) async throws -> MotionFrame {
    guard let worker, let composition else { throw MotionError("No composition is loaded") }
    guard (0..<composition.durationInFrames).contains(frame) else {
      throw MotionError("Frame out of range: \(frame)")
    }
    return try await withCheckedThrowingContinuation { continuation in
      worker.request(frame, overrides: previewOverrides, coalesces: false) { continuation.resume(with: $0) }
    }
  }

  // MARK: Rendering

  private func restartWorker() {
    renderGeneration += 1
    cache.removeAllObjects()
    renderError = nil
    if isPlaying {
      playbackRate.start(at: ProcessInfo.processInfo.systemUptime)
      liveFPS = nil
    }
    guard let bundle, let composition else {
      worker = nil
      return
    }
    worker = FrameRenderWorker(
      bundle: bundle, composition: composition, props: props, scale: configuration.scale,
      backend: configuration.backend)
    show(currentFrame)
  }

  private func show(_ frame: Int) {
    currentFrame = frame
    let overrides = previewOverrides
    if overrides.isEmpty, let cached = cache.object(forKey: frame as NSNumber) {
      present(cached.frame)
      return
    }
    let generation = renderGeneration
    worker?.request(frame, overrides: overrides, coalesces: true) { [weak self] result in
      Task { @MainActor in self?.receive(result, generation: generation) }
    }
  }

  private func receive(_ result: Result<MotionFrame, any Error>, generation: Int) {
    guard generation == renderGeneration else { return }
    switch result {
    case .success(let frame):
      if frame.overridden {
        // A late override frame must not replace the picture after the gesture ended.
        guard !previewOverrides.isEmpty else { return }
      } else {
        cache.setObject(CachedFrame(frame), forKey: frame.frame as NSNumber, cost: frame.byteCount)
      }
      // Frames finish in request order, so the newest delivery is the best available picture.
      renderError = nil
      present(frame)
    case .failure(let error):
      renderError = String(describing: error)
      pause()
    }
  }

  private func present(_ frame: MotionFrame) {
    if isPlaying, displayedFrame?.frame != frame.frame {
      playbackRate.record(at: ProcessInfo.processInfo.systemUptime)
    }
    displayedFrame = frame
    synchronizeAudio()
    refreshLiveFPS()
  }

  private func refreshLiveFPS() {
    guard isPlaying else { return }
    liveFPS = playbackRate.value(at: ProcessInfo.processInfo.systemUptime)
  }

  /// Runs `body` on a thread with an 8 MiB stack; bundle evaluation recurses deeply.
  private static func onLargeStack<T: Sendable>(
    _ body: @escaping @Sendable () throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      let thread = Thread { continuation.resume(with: Result(catching: body)) }
      thread.name = "motionswift.preview.load"
      thread.stackSize = 8 << 20
      thread.qualityOfService = .userInitiated
      thread.start()
    }
  }
}

private final class CachedFrame {
  let frame: MotionFrame
  init(_ frame: MotionFrame) { self.frame = frame }
}

extension MotionPlayer {
  private func synchronizeAudio() {
    do {
      try mediaPlayback.synchronize(displayedFrame?.tree.activeMedia ?? [], playing: isPlaying, muted: isMuted)
    } catch {
      renderError = String(describing: error)
      pause()
    }
  }

}
