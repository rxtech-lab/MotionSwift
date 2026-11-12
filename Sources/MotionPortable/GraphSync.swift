import Foundation
import MotionCore

/// Fetches module graphs from a Mac (`motionswift serve-graph`) or a cloud graph service, for
/// projects that import packages outside the device's precompiled vendor graph.
///
/// Protocol: `GET <base>/graph` returns a `.msgraph` JSON document; the server adds the
/// `X-MotionSwift-Vendor` header with its vendor identity. `GET <base>/health` returns `ok`.
public struct GraphSyncClient: Sendable {
  public var baseURL: URL
  public var timeout: TimeInterval

  public init(baseURL: URL, timeout: TimeInterval = 30) {
    self.baseURL = baseURL
    self.timeout = timeout
  }

  public func fetchGraph(session: URLSession = .shared) async throws -> ModuleGraph {
    var request = URLRequest(url: baseURL.appendingPathComponent("graph"), timeoutInterval: timeout)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(Vendor.identity, forHTTPHeaderField: "X-MotionSwift-Vendor")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw MotionError("Graph server returned no HTTP response") }
    guard http.statusCode == 200 else {
      let message = String(data: data.prefix(2000), encoding: .utf8) ?? ""
      throw MotionError("Graph server returned \(http.statusCode): \(message)")
    }
    return try ModuleGraph(data: data)
  }
}
