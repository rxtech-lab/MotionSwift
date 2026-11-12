import Foundation
import JavaScriptCore
import MotionCore

/// Compiles TS/TSX projects inside JavaScriptCore with the bundled Sucrase transform, and edits
/// inline styles of stamped elements. Works on iOS and iPadOS without JIT and without Node.
///
/// Type checking is not performed here; `motionswift check` on a Mac keeps the tsgo checker.
/// A compiler is confined to its creating thread. Babel recurses deeply, so run it on a thread
/// with a large stack (8 MiB) for big files.
public final class PortableCompiler {
  private let context: JSContext
  private let portable: JSValue

  public static let producer = "MotionSwift portable compiler (Sucrase in JavaScriptCore)"
  static let sourceExtensions: Set<String> = ["ts", "tsx", "js", "jsx", "mts", "mjs", "cts", "cjs", "json"]

  public init() throws {
    guard let context = JSContext() else { throw MotionError("Cannot create JavaScriptCore context") }
    context.evaluateScript(try Vendor.resource("portable", "js"), withSourceURL: URL(string: "motionswift:portable"))
    if let error = context.exception { throw MotionError("Portable compiler: \(error)") }
    guard let portable = context.objectForKeyedSubscript("MotionPortable"), portable.isObject else {
      throw MotionError("Portable compiler resource is invalid")
    }
    self.context = context
    self.portable = portable
  }

  /// Compiles in-memory sources keyed by project-relative POSIX paths.
  public func compile(files: [String: String], entry: String, stamp: Bool = false) throws -> ModuleGraph {
    let input = try JSONSerialization.data(withJSONObject: [
      "files": files, "entry": entry, "stamp": stamp, "vendor": Vendor.specifiers,
    ] as [String: Any])
    let output = try call("compile", String(bytes: input, encoding: .utf8) ?? "{}")
    struct Output: Decodable { let modules: [String: ModuleGraph.Module] }
    let modules = try JSONDecoder().decode(Output.self, from: Data(output.utf8)).modules
    return ModuleGraph(entry: entry, modules: modules, producer: Self.producer, stamped: stamp)
  }

  /// Compiles a project directory. Sources are read from the directory tree, skipping
  /// `node_modules`, hidden folders and declaration files.
  public func compile(project: URL, entry: String, stamp: Bool = false) throws -> ModuleGraph {
    try compile(files: Self.sources(in: project), entry: entry, stamp: stamp)
  }

  /// Inline style properties of the stamped element `src`, classified as static, animated,
  /// bound or computed.
  public func styles(source: String, src: String) throws -> StyleSummary {
    try JSONDecoder().decode(StyleSummary.self, from: Data(try call("styles", source, src).utf8))
  }

  /// Applies one edit operation; returns the new source and the exact inverse operation.
  public func edit(source: String, operation: EditOperation) throws -> (source: String, inverse: EditOperation) {
    let request = String(bytes: try JSONEncoder().encode(operation), encoding: .utf8) ?? "{}"
    struct Output: Decodable {
      let source: String
      let inverse: EditOperation
    }
    let output = try JSONDecoder().decode(Output.self, from: Data(try call("edit", source, request).utf8))
    return (output.source, output.inverse)
  }

  private func call(_ function: String, _ arguments: Any...) throws -> String {
    let result = portable.forProperty(function)?.call(withArguments: arguments)
    if let error = context.exception {
      context.exception = nil
      let message = error.forProperty("message")?.toString() ?? error.toString() ?? "unknown error"
      throw EditError(message)
    }
    guard let string = result?.toString() else { throw MotionError("Portable \(function) returned no result") }
    return string
  }

  /// Project-relative source files. Large or binary files are ignored.
  public static func sources(in project: URL) throws -> [String: String] {
    let root = project.standardizedFileURL.resolvingSymlinksInPath()
    guard let enumerator = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
    else { throw MotionError("Cannot read project: \(project.path)") }
    var files: [String: String] = [:]
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
      if values.isDirectory == true {
        if url.lastPathComponent == "node_modules" { enumerator.skipDescendants() }
        continue
      }
      let name = url.lastPathComponent
      guard sourceExtensions.contains(url.pathExtension), !name.hasSuffix(".d.ts"),
        (values.fileSize ?? 0) < 4 << 20
      else { continue }
      let relative = url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1)
      files[String(relative)] = try String(contentsOf: url, encoding: .utf8)
    }
    return files
  }
}

/// A source edit failure. `isRefusal` marks gestures the editor declines on purpose (animated,
/// bound or computed values); `isStale` means the stamp no longer matches the file.
public struct EditError: Error, CustomStringConvertible, Sendable {
  public let description: String
  public init(_ message: String) { description = message }
  public var isRefusal: Bool { description.hasPrefix("refused: ") }
  public var isStale: Bool { description.hasPrefix("stale-source: ") }
  /// The message without its machine-readable prefix.
  public var reason: String {
    for prefix in ["refused: ", "stale-source: "] where description.hasPrefix(prefix) {
      return String(description.dropFirst(prefix.count))
    }
    return description
  }
}

/// A write-back operation (see docs/editor.md → Write-back).
public struct EditOperation: Codable, Sendable, Equatable {
  public enum Kind: String, Codable, Sendable {
    case setStyle, removeStyle, insertStyle, setTimeline
  }

  public var op: Kind
  /// `file:line:column` stamp of the element.
  public var src: String
  public var key: String
  public var value: JSONValue?
  /// Exact source text, used by inverse operations to restore bytes.
  public var raw: String?
  public var text: String?
  public var lead: Int?
  public var index: Int?
  public var offset: Int?

  public static func setStyle(_ src: String, _ key: String, _ value: JSONValue) -> Self {
    Self(op: .setStyle, src: src, key: key, value: value)
  }

  public static func removeStyle(_ src: String, _ key: String) -> Self { Self(op: .removeStyle, src: src, key: key) }

  public init(
    op: Kind, src: String, key: String, value: JSONValue? = nil, raw: String? = nil, text: String? = nil,
    lead: Int? = nil, index: Int? = nil, offset: Int? = nil
  ) {
    self.op = op
    self.src = src
    self.key = key
    self.value = value
    self.raw = raw
    self.text = text
    self.lead = lead
    self.index = index
    self.offset = offset
  }

  /// The project-relative file named by `src`.
  public var file: String { SourceStamp(src)?.file ?? "" }
}

/// A parsed `file:line:column` editor stamp.
public struct SourceStamp: Hashable, Sendable {
  public let file: String
  public let line: Int
  public let column: Int

  public init?(_ value: String) {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count >= 3, let line = Int(parts[parts.count - 2]), let column = Int(parts[parts.count - 1]) else {
      return nil
    }
    file = parts.dropLast(2).joined(separator: ":")
    self.line = line
    self.column = column
  }
}

/// How a style property is expressed in source (docs/editor.md → Property classification).
public enum StylePropertyKind: String, Decodable, Sendable {
  case `static`, animated, bound, computed
}

public struct StyleSummary: Decodable, Sendable, Equatable {
  public struct Property: Decodable, Sendable, Equatable, Identifiable {

    public let key: String
    public let kind: StylePropertyKind
    public let value: JSONValue?
    public let raw: String?
    public var id: String { key }
  }

  /// False when the style prop is an expression rather than an object literal.
  public let editable: Bool
  public let properties: [Property]

  public func property(_ key: String) -> Property? { properties.first { $0.key == key } }
}

/// Numeric, frame-based animation authored by the visual editor. Frames are local to the object.
public struct EditorKeyframe: Codable, Sendable, Equatable {
  public var frame: Int
  public var value: Double
  public var easing: String

  public init(frame: Int, value: Double, easing: String = "linear") {
    self.frame = frame
    self.value = value
    self.easing = easing
  }
}

public struct ObjectTiming: Codable, Sendable, Equatable {
  public var from: Int
  public var duration: Int?
  public var keyframes: [String: [EditorKeyframe]]

  public init(from: Int = 0, duration: Int? = nil, keyframes: [String: [EditorKeyframe]] = [:]) {
    self.from = from
    self.duration = duration
    self.keyframes = keyframes
  }
}

public struct ObjectTrack: Decodable, Sendable, Equatable, Identifiable {
  public let src: String
  public let label: String
  public let owner: String?
  public let offset: Int
  public let limit: Int?
  public let reason: String?
  public let from: Int
  public let duration: Int?
  public let keyframes: [String: [EditorKeyframe]]
  public var id: String { src }
  public var timing: ObjectTiming { .init(from: from, duration: duration, keyframes: keyframes) }
  public var start: Int { offset + from }
  public func end(in compositionDuration: Int) -> Int {
    min(compositionDuration, limit ?? compositionDuration, duration.map { start + $0 } ?? compositionDuration)
  }
}

extension PortableCompiler {
  public func timeline(source: String, file: String) throws -> [ObjectTrack] {
    try JSONDecoder().decode([ObjectTrack].self, from: Data(try call("timeline", source, file).utf8))
  }
}

extension EditOperation {
  public static func setTimeline(_ src: String, _ timing: ObjectTiming) throws -> Self {
    var object = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(timing))
    if timing.duration == nil { object["duration"] = .null }
    let value = JSONValue.object(object)
    return Self(op: .setTimeline, src: src, key: "timeline", value: value)
  }
}
