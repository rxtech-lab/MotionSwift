import Foundation
import JavaScriptCore

/// Host operations return values on the owning JS thread; URLSession callbacks never touch JSC.
enum RuntimeGlobals {
  static func install(in context: JSContext, timeout: TimeInterval) {
    let url: @convention(block) (String, String) -> [String: String] = { input, base in
      guard let value = URL(string: input, relativeTo: URL(string: base))?.absoluteURL,
        let parts = URLComponents(url: value, resolvingAgainstBaseURL: true), parts.scheme != nil else {
        return ["error": "Invalid URL: \(input)"]
      }
      return ["href": value.absoluteString, "protocol": (parts.scheme ?? "") + ":",
        "hostname": parts.host ?? "", "host": (parts.host ?? "") + (parts.port.map { ":\($0)" } ?? ""),
        "pathname": parts.percentEncodedPath, "search": parts.percentEncodedQuery.map { "?" + $0 } ?? "",
        "hash": parts.percentEncodedFragment.map { "#" + $0 } ?? "",
        "origin": "\(parts.scheme ?? "")://\(parts.host ?? "")\(parts.port.map { ":\($0)" } ?? "")"]
    }
    context.setObject(url, forKeyedSubscript: "__ms_url" as NSString)
    let encode: @convention(block) (String) -> [UInt8] = { Array($0.utf8) }
    // TextDecoder intentionally replaces malformed UTF-8 rather than failing.
    // swiftlint:disable:next optional_data_string_conversion
    let decode: @convention(block) ([UInt8]) -> String = { String(decoding: $0, as: UTF8.self) }
    let base64: @convention(block) (String, Bool) -> String? = { value, decoding in
      if decoding { return Data(base64Encoded: value).flatMap { String(bytes: $0, encoding: .isoLatin1) } }
      return value.data(using: .isoLatin1)?.base64EncodedString()
    }
    context.setObject(encode, forKeyedSubscript: "__ms_encode" as NSString)
    context.setObject(decode, forKeyedSubscript: "__ms_decode" as NSString)
    context.setObject(base64, forKeyedSubscript: "__ms_base64" as NSString)
    let fetch: @convention(block) (String, String, [String: String], String) -> [String: Any] = { address, method, headers, body in
      guard let url = URL(string: address), ["http", "https"].contains(url.scheme ?? "") else {
        return ["error": "fetch requires an absolute HTTP(S) URL: \(address)"]
      }
      var request = URLRequest(url: url, timeoutInterval: timeout)
      request.httpMethod = method
      request.allHTTPHeaderFields = headers
      if !body.isEmpty { request.httpBody = Data(body.utf8) }
      let result = FetchResult()
      let semaphore = DispatchSemaphore(value: 0)
      let task = URLSession.shared.dataTask(with: request) { data, response, error in
        result.lock.withLock {
          if let error {
            result.value = ["error": "fetch \(address): \(error.localizedDescription)"]
          } else if let response = response as? HTTPURLResponse {
            result.value = ["status": response.statusCode, "url": response.url?.absoluteString ?? address,
              "headers": response.allHeaderFields.reduce(into: [String: String]()) {
                $0[String(describing: $1.key)] = String(describing: $1.value)
              },
              "body": Array(data ?? Data())]
          }
        }
        semaphore.signal()
      }
      task.resume()
      if semaphore.wait(timeout: .now() + timeout) == .timedOut {
        task.cancel()
        return ["error": "fetch \(address) timed out after \(timeout)s"]
      }
      return result.lock.withLock { result.value }
    }
    context.setObject(fetch, forKeyedSubscript: "__ms_fetch" as NSString)
    if let url = Bundle.module.url(forResource: "globals", withExtension: "js", subdirectory: "JavaScript"),
      let script = try? String(contentsOf: url, encoding: .utf8) { context.evaluateScript(script) }
  }
}

private final class FetchResult: @unchecked Sendable {
  let lock = NSLock()
  var value: [String: Any] = ["error": "fetch returned no response"]
}
