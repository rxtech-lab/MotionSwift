import Darwin
import Foundation

/// The current app's resident memory, matching the RSS unit used by the benchmark sampler.
/// It excludes other processes and does not separately account for GPU allocations.
enum AppMemory {
  static func residentBytes() -> UInt64? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? info.resident_size : nil
  }

  static func formatted(_ bytes: UInt64?) -> String {
    guard let bytes else { return "Unavailable" }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
  }
}
