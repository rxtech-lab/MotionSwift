import Foundation

public struct MotionError: Error, CustomStringConvertible, Sendable {
  public let description: String
  public init(_ message: String) { description = message }
}

public struct Composition: Codable, Sendable {
  public let id: String
  public let width: Int
  public let height: Int
  public let fps: Double
  public let durationInFrames: Int

  public func validate() throws {
    guard !id.isEmpty, width > 0, height > 0, width <= 16384, height <= 16384,
      fps.isFinite, fps > 0, durationInFrames > 0
    else {
      throw MotionError("Invalid composition dimensions, fps, or duration: \(id)")
    }
  }
}

public enum JSONValue: Codable, Equatable, Sendable {
  case number(Double)
  case string(String)
  case bool(Bool)
  case null
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .null: try container.encodeNil()
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  public var number: Double? {
    if case .number(let value) = self { return value }
    return nil
  }
  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }
}

public struct RenderNode: Codable, Sendable {
  public let type: String
  public let style: [String: JSONValue]
  public let text: String?
  public let children: [RenderNode]

  public init(
    type: String, style: [String: JSONValue], text: String? = nil, children: [RenderNode] = []
  ) {
    self.type = type
    self.style = style
    self.text = text
    self.children = children
  }
}

public enum Subprocess {
  @discardableResult
  public static func run(_ executable: String, _ arguments: [String], directory: URL? = nil) throws
    -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = directory
    let output = Pipe()
    process.standardOutput = output
    // Inherit stderr so compiler/encoder errors remain visible and cannot fill a pipe.
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw MotionError("\(executable) exited with status \(process.terminationStatus)")
    }
    return data
  }
}

public struct Diagnostic: Codable, Sendable {
  public let rule: String
  public let file: String
  public let line: Int
  public let col: Int
  public let message: String
}
