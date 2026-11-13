import Foundation

public enum MediaSource {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var publicFolder: URL?

  /// The project's `public/` folder, used for `staticFile()` (`static:` sources). Hosts set it
  /// when they open a project; it is process-wide like Remotion's single public directory.
  public static var publicDirectory: URL? {
    get { lock.withLock { publicFolder } }
    set { lock.withLock { publicFolder = newValue } }
  }

  /// Absolute paths/file URLs are portable when the caller stages assets on the device.
  public static func url(_ source: String) throws -> URL {
    if source.hasPrefix("/") { return URL(fileURLWithPath: source) }
    if source.hasPrefix("static:") {
      let relative = String(source.dropFirst(7))
      guard let decoded = relative.removingPercentEncoding, !decoded.isEmpty,
        !decoded.split(separator: "/").contains("..")
      else { throw MotionError("Invalid staticFile() path: \(source)") }
      guard let folder = publicDirectory else {
        throw MotionError("staticFile(\"\(decoded)\") needs a public/ folder; render from a project directory")
      }
      return folder.appendingPathComponent(decoded)
    }
    guard let url = URL(string: source), ["file", "https", "http"].contains(url.scheme?.lowercased() ?? "") else {
      throw MotionError("Media requires an absolute file path or file/HTTPS URL: \(source.prefix(160))")
    }
    return url
  }

  public static func data(_ source: String) throws -> Data {
    guard source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") else {
      throw MotionError("Invalid media data URI")
    }
    let header = source[..<comma].lowercased()
    let body = String(source[source.index(after: comma)...])
    if header.hasSuffix(";base64"), let data = Data(base64Encoded: body) { return data }
    if !header.hasSuffix(";base64"), let data = body.removingPercentEncoding?.data(using: .utf8) { return data }
    throw MotionError("Invalid media data URI payload")
  }
}

public struct ActiveMedia: Sendable {
  public let id: String
  public let src: String
  public let sample: MediaSample

  public init(id: String, src: String, sample: MediaSample) {
    self.id = id
    self.src = src
    self.sample = sample
  }
}

extension RenderNode {
  /// Audio and video voices active in this evaluated frame, including nested sequences.
  public var activeMedia: [ActiveMedia] {
    func visit(_ node: RenderNode, path: String) -> [ActiveMedia] {
      var result: [ActiveMedia] = []
      if ["ms-audio", "ms-video"].contains(node.type), let src = node.src, let sample = node.media {
        result.append(ActiveMedia(id: path + ":" + src, src: src, sample: sample))
      }
      for (index, child) in node.children.enumerated() {
        result += visit(child, path: "\(path).\(index)")
      }
      return result
    }
    return visit(self, path: "0")
  }
}
