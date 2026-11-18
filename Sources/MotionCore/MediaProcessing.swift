import CoreGraphics
import Foundation

/// What a host processor is asked to produce for one media element in one frame.
public struct MediaProcessRequest: Sendable, Equatable {
  /// The element's `process` key, chosen by the host when it generated the composition.
  public let key: String
  /// Seconds on the element's media clock: source time for `<Video>`/`<OffthreadVideo>`, and the
  /// `processTime` (default: local frame ÷ fps) for `<Img>`.
  public let time: Double
  /// Output pixels the element covers (layout size × render scale). Returning an image of this
  /// size avoids a resample; any size is accepted and drawn with the element's `objectFit`.
  public let pixelWidth: Int
  public let pixelHeight: Int

  public init(key: String, time: Double, pixelWidth: Int, pixelHeight: Int) {
    self.key = key
    self.time = time
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }
}

/// Lets a host app run its own image pipeline (Core Image filters, overlays, presentation effects)
/// on decoded media before MotionSwift draws it. Media elements opt in with a `process` key; the
/// processor receives the decoded frame (or, for `<Img>`, the decoded still) and returns the image
/// to draw, or nil to draw nothing. Called on render worker threads, concurrently.
public enum MediaProcessing {
  public typealias Processor = @Sendable (_ image: CGImage, _ request: MediaProcessRequest) throws -> CGImage?

  private static let lock = NSLock()
  nonisolated(unsafe) private static var current: Processor?

  /// The process-wide processor. Elements with a `process` key fail to render when none is set.
  public static var processor: Processor? {
    get { lock.withLock { current } }
    set { lock.withLock { current = newValue } }
  }
}
