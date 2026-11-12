import Foundation
import MotionCore
import MotionRuntime
import SkiaKit

/// Measures preview frame cost by stage on the current device: JavaScript evaluation (fresh VM,
/// bundle evaluation, React render), layout + paint, and pixel readback. On iOS and iPadOS,
/// JavaScriptCore runs without a JIT, so this is the number that decides preview resolution and
/// frame rate there. On macOS, `JSC_useJIT=false` reproduces the no-JIT interpreter.
public struct PreviewBudgetReport: Codable, Sendable {
  public struct Stage: Codable, Sendable {
    public let p50: Double
    public let p95: Double
    public let max: Double

    init(_ samples: [Double]) {
      let sorted = samples.sorted()
      func percentile(_ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
      }
      p50 = percentile(0.5)
      p95 = percentile(0.95)
      self.max = sorted.last ?? 0
    }
  }

  public let composition: String
  public let width: Int
  public let height: Int
  public let scale: Double
  public let backend: String
  public let fps: Double
  /// 1000 / fps: the per-frame budget for real-time playback.
  public let budgetMs: Double
  public let frames: Int
  public let bundleBytes: Int
  /// First frame, including runtime startup.
  public let coldMs: Double
  /// Warm frames, in milliseconds.
  public let javascript: Stage
  public let paint: Stage
  public let readback: Stage
  public let total: Stage
  /// Share of warm frames whose total fits the budget.
  public let withinBudget: Double
  /// Highest sustainable preview rate from the p50 total, capped at the composition fps.
  public let sustainableFPS: Double
  public let jit: String
  public let platform: String

  public var summary: String {
    String(
      format: "%@ %dx%d@%.2gx %@: JS p50 %.1f ms · paint %.1f ms · readback %.1f ms · "
        + "total p50 %.1f / p95 %.1f ms (budget %.1f ms, %.0f%% within) · %.1f fps sustainable · JIT %@",
      composition, width, height, scale, backend, javascript.p50, paint.p50, readback.p50, total.p50, total.p95,
      budgetMs, withinBudget * 100, sustainableFPS, jit)
  }
}

public enum PreviewBudget {
  /// Renders `frames` (default: every frame up to 60) and reports per-stage timings.
  public static func measure(
    bundle: String, composition: Composition, frames: [Int]? = nil, props: String = "{}", scale: Double = 1,
    backend: RenderBackend = .cpu
  ) throws -> PreviewBudgetReport {
    let numbers = frames ?? Array(0..<min(composition.durationInFrames, 60))
    guard !numbers.isEmpty else { throw MotionError("No frames to measure") }
    let coldStart = DispatchTime.now().uptimeNanoseconds
    let runtime = try Runtime(bundle: bundle)
    let renderer = try Renderer(
      width: composition.width, height: composition.height, scale: scale, backend: backend)
    var javascript: [Double] = []
    var paint: [Double] = []
    var readback: [Double] = []
    var total: [Double] = []
    var cold = 0.0
    for (index, number) in numbers.enumerated() {
      try autoreleasepool {
        let begin = DispatchTime.now().uptimeNanoseconds
        let tree = try runtime.frame(composition: composition, number: number, props: props)
        let evaluated = DispatchTime.now().uptimeNanoseconds
        try renderer.draw(tree, composition: composition)
        let painted = DispatchTime.now().uptimeNanoseconds
        _ = try renderer.pixels()
        let end = DispatchTime.now().uptimeNanoseconds
        if index == 0 {
          cold = Double(end - coldStart) / 1e6
          if numbers.count > 1 { return }
        }
        javascript.append(Double(evaluated - begin) / 1e6)
        paint.append(Double(painted - evaluated) / 1e6)
        readback.append(Double(end - painted) / 1e6)
        total.append(Double(end - begin) / 1e6)
      }
    }
    let budget = 1000 / composition.fps
    let totals = PreviewBudgetReport.Stage(total)
    return PreviewBudgetReport(
      composition: composition.id, width: composition.width, height: composition.height, scale: scale,
      backend: backend.rawValue, fps: composition.fps, budgetMs: budget, frames: total.count,
      bundleBytes: bundle.utf8.count, coldMs: cold, javascript: .init(javascript), paint: .init(paint),
      readback: .init(readback), total: totals,
      withinBudget: Double(total.filter { $0 <= budget }.count) / Double(max(total.count, 1)),
      sustainableFPS: min(composition.fps, totals.p50 > 0 ? 1000 / totals.p50 : composition.fps),
      jit: jitMode, platform: platform)
  }

  /// JIT availability for this process. Embedded JavaScriptCore on macOS only JITs when the
  /// process is signed with `com.apple.security.cs.allow-jit`; iOS devices never JIT.
  public static var jitMode: String {
    #if os(iOS) && !targetEnvironment(simulator)
    return "unavailable (iOS device)"
    #else
    let value = ProcessInfo.processInfo.environment["JSC_useJIT"]?.lowercased()
    if value == "false" || value == "0" { return "off (JSC_useJIT=false)" }
    return "process default (macOS needs the allow-jit entitlement)"
    #endif
  }

  public static var platform: String {
    var system = utsname()
    uname(&system)
    let machine = withUnsafeBytes(of: &system.machine) { buffer in
      String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
    }
    #if os(iOS) && targetEnvironment(simulator)
    let name = "iOS Simulator"
    #elseif os(iOS)
    let name = "iOS"
    #else
    let name = "macOS"
    #endif
    return "\(name) \(ProcessInfo.processInfo.operatingSystemVersionString) \(machine)"
  }
}
