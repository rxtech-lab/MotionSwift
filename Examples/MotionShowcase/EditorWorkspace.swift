import Foundation
import MotionCore

/// The showcase editor works on a writable copy of the MotionStudio sample project, so edits never
/// touch the repository's golden fixtures. Other projects are edited in place after confirmation.
enum EditorWorkspace {
  /// Shared by every window for this process, but never reused by another launch.
  static let root: URL = {
    if let path = ProcessInfo.processInfo.environment["MOTIONSWIFT_SHOWCASE_WORKSPACE"] {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    return makeSessionRoot()
  }()

  static func makeSessionRoot(in directory: URL = FileManager.default.temporaryDirectory) -> URL {
    directory.appendingPathComponent("MotionSwiftShowcase-\(UUID().uuidString)", isDirectory: true)
  }

  static var sample: URL { root.appendingPathComponent("Sample", isDirectory: true) }

  static var bundledSample: URL {
    ShowcaseDefaults.repository.appendingPathComponent("Examples/MotionStudio/SampleProject")
  }

  /// Returns the sample copy, creating (or recreating, with `reset`) it from the repository.
  static func prepareSample(reset: Bool = false) throws -> URL {
    let files = FileManager.default
    if reset || !files.fileExists(atPath: sample.appendingPathComponent("src/index.ts").path) {
      guard files.fileExists(atPath: bundledSample.path) else {
        throw MotionError("Sample project not found at \(bundledSample.path). Set MOTIONSWIFT_HOME.")
      }
      try files.createDirectory(at: root, withIntermediateDirectories: true)
      if files.fileExists(atPath: sample.path) { try files.removeItem(at: sample) }
      try files.copyItem(at: bundledSample, to: sample)
    }
    return sample
  }
}
