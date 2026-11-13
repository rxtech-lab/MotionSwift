import Foundation
import JavaScriptCore
import MotionCore

/// A worker and its retained tree are confined to their creating thread.
public final class Runtime {
  private let context: JSContext
  private var nodes: [String: RetainedNode] = [:]
  private var identity: String?
  private let timeout: TimeInterval
  public private(set) var mutationCount = 0

  public init(bundle: String, timeoutInMilliseconds: Double = 30_000) throws {
    guard timeoutInMilliseconds.isFinite, timeoutInMilliseconds > 0 else {
      throw MotionError("Runtime timeout must be positive and finite")
    }
    timeout = timeoutInMilliseconds / 1000
    guard let context = JSContext() else { throw MotionError("Cannot create JavaScriptCore context") }
    self.context = context
    guard let url = Bundle.module.url(forResource: "engine", withExtension: "js", subdirectory: "JavaScript") else {
      throw MotionError("Missing JavaScript runtime resource")
    }
    context.setObject(timeoutInMilliseconds, forKeyedSubscript: "__ms_timeout" as NSString)
    RuntimeGlobals.install(in: context, timeout: timeout)
    context.evaluateScript(try String(contentsOf: url, encoding: .utf8), withSourceURL: URL(string: "motionswift:runtime"))
    context.evaluateScript(bundle, withSourceURL: URL(string: "motionswift:bundle"))
    try check()
    guard let reset = context.objectForKeyedSubscript("__ms_resetModules"), !reset.isUndefined else {
      throw MotionError("Runtime bundle lacks __ms_resetModules; recompile sources with the current compiler")
    }
  }

  private func check() throws {
    if let error = context.exception {
      var message = "JavaScript: \(error.toString() ?? "unknown error")\n\(error.forProperty("stack")?.toString() ?? "")"
      context.exception = nil
      if let mapper = context.objectForKeyedSubscript("__ms_mapStack"), !mapper.isUndefined {
        message = mapper.call(withArguments: [message])?.toString() ?? message
        context.exception = nil
      }
      throw MotionError(message)
    }
  }

  private func call(_ name: String, _ arguments: [Any] = []) throws -> JSValue {
    guard let function = context.objectForKeyedSubscript(name), !function.isUndefined else {
      throw MotionError("Runtime bundle is missing \(name); recompile with the current compiler")
    }
    let result = function.call(withArguments: arguments)
    try check()
    guard let result else { throw MotionError("Runtime returned no result for \(name)") }
    return result
  }

  public func compositions() throws -> [Composition] {
    let result = try call("__ms_catalog")
    guard let json = result.toString(), let data = json.data(using: .utf8) else {
      throw MotionError("Composition catalog is not valid JSON")
    }
    let catalog = try JSONDecoder().decode([Composition].self, from: data)
    guard !catalog.isEmpty, Set(catalog.map(\.id)).count == catalog.count else {
      throw MotionError("Composition IDs must be unique; catalog must not be empty")
    }
    try catalog.forEach { try $0.validate() }
    return catalog
  }

  /// Explicitly discard retained subtrees. Source changes require a new Runtime(bundle:).
  public func invalidate() throws {
    _ = try call("__ms_invalidate")
    nodes.removeAll()
    identity = nil
  }

  public func frame(composition: Composition, number: Int, props: String = "{}") throws -> RenderNode {
    guard number >= 0, number < composition.durationInFrames else {
      throw MotionError("Frame out of range: \(number)")
    }
    guard let object = try JSONSerialization.jsonObject(with: Data(props.utf8)) as? [String: Any] else {
      throw MotionError("Props must be a JSON object")
    }
    let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard let canonicalProps = String(bytes: canonical, encoding: .utf8) else {
      throw MotionError("Props could not be encoded as UTF-8 JSON")
    }
    let key = composition.id + ":" + canonicalProps
    if key != identity { try invalidate(); identity = key }
    do {
      let deadline = ProcessInfo.processInfo.systemUptime + timeout
      _ = try call("__ms_begin", [composition.id, number, props])
      var settled = false
      for iteration in 0..<10_000 {
        let done = try call("__ms_step").toBool()
        if done && settled { break }
        settled = done
        if iteration == 9_999 || ProcessInfo.processInfo.systemUptime >= deadline {
          let pending = try call("__ms_pending").toString() ?? ""
          throw MotionError("Composition \(composition.id), frame \(number): async lifecycle did not settle within \(timeout)s. \(pending)")
        }
      }
      let operations = try call("__ms_commit")
      mutationCount = Int(operations.forProperty("length").toInt32())
      for index in 0..<mutationCount { try apply(operations.atIndex(index)!) }
      guard nodes["0"] != nil else { throw MotionError("Frame did not produce a render tree") }
      return try snapshot("0")
    } catch {
      try? invalidate()
      throw MotionError("Composition \(composition.id), frame \(number): \(error)")
    }
  }

  private func apply(_ operation: JSValue) throws {
    let kind = operation.atIndex(0)!.toString()!
    let path = operation.atIndex(1)!.toString()!
    let payload = operation.atIndex(2)!
    switch kind {
    case "create": nodes[path] = RetainedNode(type: payload.forProperty("type").toString()!)
      fallthrough
    case "patch":
      guard let node = nodes[path] else { throw MotionError("Mutation refers to missing node \(path)") }
      if let style = payload.forProperty("style"), !style.isUndefined {
        for key in (style.toDictionary() as? [String: Any] ?? [:]).keys {
          let value = try jsonValue(style.forProperty(key)!)
          node.style[key] = value == .null ? nil : value
        }
      }
      if let media = payload.forProperty("media"), !media.isUndefined {
        node.media = media.isNull ? nil : MediaSample(
          time: media.forProperty("time").toDouble(),
          playbackRate: media.forProperty("playbackRate").toDouble(),
          volume: media.forProperty("volume").toDouble())
      }
      if let scene = payload.forProperty("scene"), !scene.isUndefined {
        node.scene = scene.isNull ? nil : try Scene3D.decode(scene.toString())
      }
      for key in ["text", "src", "source"] {
        let value = payload.forProperty(key)!
        if !value.isUndefined { node.properties[key] = value.isNull ? nil : value.toString() }
      }
    case "children": nodes[path]?.children = payload.toArray() as? [String] ?? []
    case "delete": nodes.removeValue(forKey: path)
    default: throw MotionError("Unknown runtime mutation: \(kind)")
    }
    var ancestor = path
    while true {
      nodes[ancestor]?.cached = nil
      guard let separator = ancestor.lastIndex(of: ".") else { break }
      ancestor = String(ancestor[..<separator])
    }
  }

  private func snapshot(_ path: String) throws -> RenderNode {
    guard let node = nodes[path] else { throw MotionError("Missing retained child: \(path)") }
    if let cached = node.cached { return cached }
    let result = RenderNode(type: node.type, style: node.style, text: node.properties["text"],
      src: node.properties["src"], source: node.properties["source"], media: node.media, scene: node.scene,
      children: try node.children.map(snapshot))
    node.cached = result
    return result
  }

  private func jsonValue(_ value: JSValue) throws -> JSONValue {
    if value.isNull || value.isUndefined { return .null }
    if value.isBoolean { return .bool(value.toBool()) }
    if value.isNumber { return .number(value.toDouble()) }
    if value.isString { return .string(value.toString()) }
    if value.isArray {
      return .array(try (0..<Int(value.forProperty("length").toInt32())).map { try jsonValue(value.atIndex($0)!) })
    }
    var result: [String: JSONValue] = [:]
    for key in (value.toDictionary() as? [String: Any] ?? [:]).keys { result[key] = try jsonValue(value.forProperty(key)!) }
    return .object(result)
  }
}

private final class RetainedNode {
  let type: String
  var style: [String: JSONValue] = [:]
  var properties: [String: String] = [:]
  var media: MediaSample?
  var scene: Scene3D?
  var children: [String] = []
  var cached: RenderNode?
  init(type: String) { self.type = type }
}
