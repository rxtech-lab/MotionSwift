import CryptoKit
import Foundation

/// Content identities use SHA-256, never timestamps or Swift's randomized Hasher.
public enum CompilerContent {
  public static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public static func key<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return hash(try encoder.encode(value))
  }
}

public struct CompilerCacheStatistics: Sendable, Equatable {
  public var hits: Int
  public var misses: Int
  public init(hits: Int = 0, misses: Int = 0) { self.hits = hits; self.misses = misses }
}
