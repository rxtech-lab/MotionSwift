import CryptoKit
import Foundation
import MotionCore

enum TestFilmFixture {
  /// Extract exactly the reviewed project archive used by tests/perf/test-film.mjs.
  /// The caller owns and removes this unique staging directory after compilation.
  static func prepare(repository: URL) throws -> URL {
    let fixture = repository.appendingPathComponent("tests/fixtures/test-film")
    let archive = fixture.appendingPathComponent("project.zip")
    let expected = try String(contentsOf: archive.appendingPathExtension("sha256"), encoding: .utf8)
      .split(whereSeparator: \.isWhitespace).first.map(String.init)
    let actual = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
    guard expected == actual else { throw MotionError("Test Film archive checksum mismatch") }
    let project = FileManager.default.temporaryDirectory.appendingPathComponent("motionswift-showcase-\(UUID())")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    do {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
      process.arguments = ["-q", archive.path, "-d", project.path]
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { throw MotionError("Cannot extract Test Film") }
      return project
    } catch {
      try? FileManager.default.removeItem(at: project)
      throw error
    }
  }
}
