import Foundation
import MotionCore
import MotionPortable

/// Owns one `PortableCompiler` on a dedicated 8 MiB-stack thread (JavaScriptCore contexts are
/// thread-confined and Babel recurses deeply) and runs edit/compile work on it in order.
final class EditService: @unchecked Sendable {
  private let condition = NSCondition()
  private var work: [(PortableCompiler?) -> Void] = []
  private var stopped = false

  init() {
    let thread = Thread { [condition] in
      let compiler = try? PortableCompiler()
      while true {
        condition.lock()
        while !self.stopped, self.work.isEmpty { condition.wait() }
        if self.stopped {
          condition.unlock()
          return
        }
        let job = self.work.removeFirst()
        condition.unlock()
        autoreleasepool { job(compiler) }
      }
    }
    thread.name = "motionswift.editor.service"
    thread.stackSize = 8 << 20
    thread.qualityOfService = .userInitiated
    thread.start()
  }

  func stop() {
    condition.lock()
    stopped = true
    condition.broadcast()
    condition.unlock()
  }

  func perform<T: Sendable>(_ body: @escaping @Sendable (PortableCompiler) throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      condition.lock()
      work.append { compiler in
        guard let compiler else {
          continuation.resume(throwing: MotionError("Portable compiler is unavailable. Run make compiler."))
          return
        }
        continuation.resume(with: Result { try body(compiler) })
      }
      condition.signal()
      condition.unlock()
    }
  }
}
