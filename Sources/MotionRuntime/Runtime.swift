import Foundation
import JavaScriptCore
import MotionCore

/// A runtime is confined to its creating thread. Every evaluation starts with a fresh VM.
public final class Runtime {
  private let bundle: String
  private let bootstrap: String

  public init(bundle: String) throws {
    self.bundle = bundle
    guard
      let url = Bundle.module.url(
        forResource: "engine", withExtension: "js", subdirectory: "Resources")
    else {
      throw MotionError("Missing JavaScript runtime resource")
    }
    bootstrap = try String(contentsOf: url, encoding: .utf8)
  }

  private func context() throws -> JSContext {
    guard let context = JSContext() else {
      throw MotionError("Cannot create JavaScriptCore context")
    }
    context.evaluateScript(bootstrap, withSourceURL: URL(string: "motionswift:runtime"))
    context.evaluateScript(bundle, withSourceURL: URL(string: "motionswift:bundle"))
    try check(context)
    return context
  }

  private func check(_ context: JSContext) throws {
    if let error = context.exception {
      throw MotionError(
        "JavaScript: \(error.toString() ?? "unknown error")\n\(error.forProperty("stack")?.toString() ?? "")"
      )
    }
  }

  public func compositions() throws -> [Composition] {
    let context = try context()
    let result = context.objectForKeyedSubscript("__ms_catalog")?.call(withArguments: [])
    try check(context)
    guard let json = result?.toString(), let data = json.data(using: .utf8) else {
      throw MotionError("Composition catalog is not valid JSON")
    }
    let catalog = try JSONDecoder().decode([Composition].self, from: data)
    guard !catalog.isEmpty, Set(catalog.map(\.id)).count == catalog.count else {
      throw MotionError("Composition IDs must be unique; catalog must not be empty")
    }
    try catalog.forEach { try $0.validate() }
    return catalog
  }

  public func frame(composition: Composition, number: Int, props: String = "{}") throws
    -> RenderNode {
    guard number >= 0, number < composition.durationInFrames else {
      throw MotionError("Frame out of range: \(number)")
    }
    guard (try JSONSerialization.jsonObject(with: Data(props.utf8))) is [String: Any] else {
      throw MotionError("Props must be a JSON object")
    }
    let context = try context()
    let result = context.objectForKeyedSubscript("__ms_frame")?.call(withArguments: [
      composition.id, number, props,
    ])
    try check(context)
    guard let json = result?.toString(), let data = json.data(using: .utf8) else {
      throw MotionError("Frame did not produce a render tree")
    }
    return try JSONDecoder().decode(RenderNode.self, from: data)
  }
}
