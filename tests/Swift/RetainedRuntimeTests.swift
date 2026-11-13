import Foundation
import MotionCompiler
import MotionCore
import MotionRuntime
import Testing

private func lifecycleBundle() throws -> String {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  return try Compiler().compile(project: root.appendingPathComponent("tests/compiler-fixtures/lifecycle"), entry: "input.tsx")
}

private func encodedTree(_ tree: RenderNode) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  return try encoder.encode(tree)
}

@Test func retainedRuntimeIsIndependentAndInvalidates() throws {
  let bundle = try lifecycleBundle()
  let runtime = try Runtime(bundle: bundle)
  let catalog = try runtime.compositions()
  let composition = catalog[0]
  var expected: [Int: Data] = [:]
  for frame in 0..<6 {
    let fresh = try Runtime(bundle: bundle)
    expected[frame] = try encodedTree(fresh.frame(composition: composition, number: frame))
    #expect(try encodedTree(runtime.frame(composition: composition, number: frame)) == expected[frame])
  }
  for frame in [5, 0, 3, 1, 4, 2, 5] {
    #expect(try encodedTree(runtime.frame(composition: composition, number: frame)) == expected[frame])
  }
  let globals = try runtime.frame(composition: composition, number: 5, props: #"{"mode":"globals"}"#)
  #expect(globals.children[0].style["opacity"] == .number(1))
  _ = try runtime.frame(composition: composition, number: 5)
  _ = try runtime.frame(composition: composition, number: 5)
  #expect(runtime.mutationCount == 0)
  let blue = try runtime.frame(composition: composition, number: 5, props: #"{"color":"blue"}"#)
  #expect(blue.children[0].style["backgroundColor"] == .string("blue"))
  #expect(runtime.mutationCount > 0)
  _ = try runtime.frame(composition: catalog[1], number: 0, props: #"{"mode":"ok"}"#)
  #expect(try encodedTree(runtime.frame(composition: composition, number: 0)) == expected[0])
  try runtime.invalidate()
  #expect(try encodedTree(runtime.frame(composition: composition, number: 0)) == expected[0])
  let changed = try Runtime(bundle: bundle.replacingOccurrences(of: "red", with: "green"))
  let changedComposition = try #require(changed.compositions().first)
  #expect(try changed.frame(composition: changedComposition, number: 0).children[0].style["backgroundColor"] == .string("green"))
}

@Test(arguments: ["timeout", "cancel", "reject", "throw", "duplicate"])
func asyncLifecycleFailuresAreActionable(mode: String) throws {
  let runtime = try Runtime(bundle: lifecycleBundle())
  let composition = try #require(runtime.compositions().first)
  do {
    _ = try runtime.frame(composition: composition, number: 2, props: "{\"mode\":\"\(mode)\"}")
    Issue.record("Expected lifecycle failure: \(mode)")
  } catch {
    let message = String(describing: error)
    #expect(message.contains("frame 2"), "\(message)")
    let expected = ["timeout": "fixture asset", "cancel": "decode failed", "reject": "asset promise failed",
      "throw": "timer callback failed", "duplicate": "already completed"]
    #expect(message.contains(expected[mode]!), "\(message)")
  }
  #expect(try runtime.frame(composition: composition, number: 0).children[0].style["opacity"] == .number(1))
}

/// Run explicitly to compare the same workload with fresh and retained workers; compilation is excluded.
@Test func retainedRuntimeBenchmark() throws {
  guard ProcessInfo.processInfo.environment["MOTIONSWIFT_RUNTIME_BENCHMARK"] == "1" else { return }
  let bundle = try lifecycleBundle()
  let runtime = try Runtime(bundle: bundle)
  let composition = try #require(runtime.compositions().first)
  let frames = 100
  var counts = 0
  let start = ProcessInfo.processInfo.systemUptime
  for frame in 0..<frames {
    _ = try runtime.frame(composition: composition, number: frame % 20)
    counts += runtime.mutationCount
  }
  let retained = ProcessInfo.processInfo.systemUptime - start
  let freshStart = ProcessInfo.processInfo.systemUptime
  for frame in 0..<frames {
    let fresh = try Runtime(bundle: bundle)
    _ = try fresh.frame(composition: composition, number: frame % 20)
  }
  let fresh = ProcessInfo.processInfo.systemUptime - freshStart
  print("RUNTIME_BENCHMARK frames=\(frames) retained_ms=\(retained * 1000) fresh_ms=\(fresh * 1000) "
    + "speedup=\(fresh / retained) mutations=\(counts)")
}
