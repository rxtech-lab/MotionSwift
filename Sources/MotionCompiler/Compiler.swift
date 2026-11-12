import Foundation
import MotionCore

/// Phase 0 SWC driver. The compiler subprocess is isolated here for replacement by the static C ABI.
public struct Compiler {
  public let repository: URL

  public init(repository: URL) { self.repository = repository }

  public func compile(project: URL, entry: String) throws -> String {
    let script = repository.appendingPathComponent("js/compiler/compile.cjs")
    let data = try Subprocess.run("node", [script.path, project.path, entry])
    guard let source = String(data: data, encoding: .utf8) else {
      throw MotionError("Compiler emitted invalid UTF-8")
    }
    return source
  }
  public func checkTypes(project: URL, entry: String) throws -> [Diagnostic] {
    let script = repository.appendingPathComponent("js/compiler/check.cjs")
    let data = try Subprocess.run("node", [script.path, project.path, entry])
    return try JSONDecoder().decode([Diagnostic].self, from: data)
  }

}
