import Foundation
import MotionCore

/// A compiled project: CommonJS modules plus their resolved imports. Bare imports resolve to the
/// precompiled vendor graph (`vendor:<specifier>`), so a graph runs on any device with the same
/// vendor identity. Graphs come from the portable compiler (on device), or from a Mac
/// (`motionswift graph`) or the cloud when the project needs packages outside the vendor graph.
public struct ModuleGraph: Codable, Sendable, Equatable {
  public struct Module: Codable, Sendable, Equatable {
    public var code: String
    /// Import specifier → module path in this graph, or `vendor:<specifier>`.
    public var dependencies: [String: String]

    public init(code: String, dependencies: [String: String]) {
      self.code = code
      self.dependencies = dependencies
    }
  }

  public static let currentFormat = 1
  public static let fileExtension = "msgraph"

  public var format: Int
  /// The vendor identity the graph was compiled against, for example `react@18.3.1 …`.
  public var vendor: String
  public var entry: String
  public var modules: [String: Module]
  /// npm packages bundled into the modules (Mac/cloud graphs). Empty for on-device graphs.
  public var packages: [String]
  public var producer: String
  /// Whether host elements carry `data-ms-src` editor stamps.
  public var stamped: Bool

  public init(
    vendor: String = Vendor.identity, entry: String, modules: [String: Module], packages: [String] = [],
    producer: String, stamped: Bool
  ) {
    format = Self.currentFormat
    self.vendor = vendor
    self.entry = entry
    self.modules = modules
    self.packages = packages
    self.producer = producer
    self.stamped = stamped
  }

  public init(data: Data) throws {
    let graph = try JSONDecoder().decode(Self.self, from: data)
    try graph.validate()
    self = graph
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }

  /// Checks format, vendor compatibility and that every import resolves inside the graph or vendor.
  public func validate() throws {
    guard format == Self.currentFormat else {
      throw MotionError("Unsupported module graph format \(format); this build reads format \(Self.currentFormat)")
    }
    guard vendor == Vendor.identity else {
      throw MotionError(
        "Module graph was compiled for \(vendor), but this app ships \(Vendor.identity). Re-sync the graph.")
    }
    guard modules[entry] != nil else { throw MotionError("Module graph entry is missing: \(entry)") }
    let specifiers = Set(Vendor.specifiers)
    for (path, module) in modules {
      for (specifier, target) in module.dependencies {
        if target.hasPrefix("vendor:") {
          guard specifiers.contains(String(target.dropFirst(7))) else {
            throw MotionError("ms/unsupported-package: \(specifier) in \(path) is not in the vendor graph")
          }
        } else if modules[target] == nil {
          throw MotionError("Module graph is incomplete: \(path) imports missing \(target)")
        }
      }
    }
  }
}

/// The precompiled vendor graph shipped as a package resource.
public enum Vendor {
  private struct Info: Decodable {
    let identity: String
    let sha256: String
    let specifiers: [String]
  }

  private static let info: Result<Info, MotionError> = Result {
    guard let url = Bundle.module.url(forResource: "vendor", withExtension: "json", subdirectory: "JavaScript") else {
      throw MotionError("Missing portable resources. Run make compiler before building.")
    }
    return try JSONDecoder().decode(Info.self, from: Data(contentsOf: url))
  }.mapError { $0 as? MotionError ?? MotionError(String(describing: $0)) }

  /// Package identities, for example `react@18.3.1 react-reconciler@0.29.2 …`.
  public static var identity: String { (try? info.get().identity) ?? "unavailable" }
  public static var sha256: String { (try? info.get().sha256) ?? "unavailable" }
  /// Bare import specifiers that resolve into the vendor graph.
  public static var specifiers: [String] { (try? info.get().specifiers) ?? [] }

  static func script() throws -> String { try resource("vendor", "js") }

  static func resource(_ name: String, _ ext: String) throws -> String {
    _ = try info.get()
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "JavaScript") else {
      throw MotionError("Missing portable resource \(name).\(ext). Run make compiler before building.")
    }
    return try String(contentsOf: url, encoding: .utf8)
  }
}
