import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
#if canImport(MapKit)
import MapKit
#endif

/// Host services behind `@motionswift/map`: raster tiles for `motionmap://tile/…` image sources
/// and road/rail route geometry for `<MapRoute>`.
///
/// Rendering stays deterministic for a given cache: every tile and route is stored on disk the
/// first time it is fetched and read back from there afterwards, so later renders, exports and
/// offline sessions reproduce the same frames. Calls are synchronous; they run on render and
/// JavaScript worker threads, never on the main thread.
public enum MapServices {
  public static let userAgent = "MotionSwift/1.0 (motion graphics map renderer)"
  /// UserDefaults key for a Mapbox access token set in an app (for example the editor's map settings).
  public static let mapboxTokenDefaultsKey = "MotionSwiftMapboxAccessToken"

  /// `MAPBOX_ACCESS_TOKEN`, `MOTIONSWIFT_MAPBOX_TOKEN`, or the token saved in the app's defaults.
  public static var mapboxToken: String? {
    let environment = ProcessInfo.processInfo.environment
    for value in [environment["MOTIONSWIFT_MAPBOX_TOKEN"], environment["MAPBOX_ACCESS_TOKEN"],
                  UserDefaults.standard.string(forKey: mapboxTokenDefaultsKey)] {
      if let token = value?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty { return token }
    }
    return nil
  }

  private static let offlineOverride = LockedValue<Bool?>(nil)

  /// Offline mode (`MOTIONSWIFT_MAP_OFFLINE=1`, or set by tests): cached data is still used, but
  /// missing tiles are generated placeholders and missing routes fail without network requests.
  public static var isOffline: Bool {
    get { offlineOverride.withLock { $0 } ?? (ProcessInfo.processInfo.environment["MOTIONSWIFT_MAP_OFFLINE"] == "1") }
    set { offlineOverride.withLock { $0 = newValue } }
  }

  /// MapKit snapshots are available on Apple platforms; elsewhere maps fall back to OpenStreetMap.
  public static var isAppleMapsAvailable: Bool {
    #if canImport(MapKit)
    return true
    #else
    return false
    #endif
  }

  /// Providers the host can draw, read by `@motionswift/map` to choose fallbacks.
  public static func capabilitiesJSON() -> String {
    "{\"apple\":\(isAppleMapsAvailable),\"mapbox\":\(mapboxToken != nil)}"
  }

  private static let cacheOverride = LockedValue<URL?>(nil)

  /// `MOTIONSWIFT_MAP_CACHE`, else `Caches/MotionSwift/Maps`. Hosts and tests may set another folder.
  public static var cacheDirectory: URL {
    get { cacheOverride.withLock { $0 } ?? defaultCacheDirectory }
    set { cacheOverride.withLock { $0 = newValue } }
  }

  /// Restores the environment/default cache folder after `cacheDirectory` was set.
  public static func resetCacheDirectory() { cacheOverride.withLock { $0 = nil } }

  private static var defaultCacheDirectory: URL {
    if let path = ProcessInfo.processInfo.environment["MOTIONSWIFT_MAP_CACHE"], !path.isEmpty {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return caches.appendingPathComponent("MotionSwift/Maps", isDirectory: true)
  }

  // MARK: Tiles

  /// Posted when background preview tiles finish. Exports load synchronously.
  public static let tilesDidResolve = Notification.Name("MotionSwiftMapTilesDidResolve")
  private static let previewTiles = MapTilePreviewLoader()
  private static let tileMemory = LockedValue<[String: Data]>([:])

  private static func cachedTileData(at cache: URL) -> Data? {
    let key = cache.path
    if let memory = tileMemory.withLock({ $0[key] }) { return memory }
    guard let data = try? Data(contentsOf: cache), !data.isEmpty else { return nil }
    rememberTileData(data, key: key)
    return data
  }

  private static func rememberTileData(_ data: Data, key: String) {
    tileMemory.withLock { memory in
      if memory.count >= 512 { memory.removeAll(keepingCapacity: true) }
      memory[key] = data
    }
  }

  /// Missing remote or MapKit tiles must never block the interactive render thread. A nil result
  /// leaves the map background visible until the tile resolves; incomplete frames are not cached.
  public static func tileDataForRendering(_ source: String) throws -> Data? {
    let tile = try Tile(source)
    guard !isOffline, Thread.current.threadDictionary[interactiveKey] as? Bool == true else {
      return try tileData(source)
    }
    let cache = tile.cacheURL
    if let data = cachedTileData(at: cache) { return data }
    // Validate provider/token configuration synchronously so missing Mapbox tokens still fail fast.
    _ = try tile.remoteURL()
    Thread.current.threadDictionary[pendingTilesKey] = true
    return try previewTiles.request(key: cache.path, isSnapshot: tile.provider == "apple") {
      try tileData(source)
    }
  }

  /// Clears and returns whether the current preview thread skipped any still-loading tiles.
  public static func consumeThreadPendingTiles() -> Bool {
    let pending = Thread.current.threadDictionary[pendingTilesKey] as? Bool == true
    Thread.current.threadDictionary[pendingTilesKey] = false
    return pending
  }

  public struct Tile: Equatable, Sendable {
    public let provider: String
    public let style: String
    public let zoom: Int
    public let x: Int
    public let y: Int

    /// Parses `motionmap://tile/{provider}/{style}/{z}/{x}/{y}`.
    public init(_ source: String) throws {
      guard let url = URL(string: source), url.scheme == "motionmap", url.host == "tile" else {
        throw MotionError("Invalid map tile source: \(source.prefix(160))")
      }
      let parts = url.path.split(separator: "/").map(String.init)
      guard parts.count == 5, let zoom = Int(parts[2]), let x = Int(parts[3]), let y = Int(parts[4]),
        (0...22).contains(zoom), (0..<(1 << zoom)).contains(x), (0..<(1 << zoom)).contains(y),
        parts[0].allSatisfy({ $0.isLetter }), parts[1].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
      else { throw MotionError("Invalid map tile source: \(source.prefix(160))") }
      (provider, style, self.zoom, self.x, self.y) = (parts[0], parts[1], zoom, x, y)
    }

    /// The HTTPS tile for web providers; nil for Apple Maps (drawn with MapKit).
    func remoteURL() throws -> URL? {
      let path = "\(zoom)/\(x)/\(y)"
      let address: String
      switch (provider, style) {
      case ("openstreetmap", "standard"): address = "https://tile.openstreetmap.org/\(path).png"
      case ("openstreetmap", "humanitarian"): address = "https://a.tile.openstreetmap.fr/hot/\(path).png"
      case ("openstreetmap", "topographic"): address = "https://a.tile.opentopomap.org/\(path).png"
      case ("mapbox", let style) where Self.mapboxStyles.contains(style):
        guard let token = MapServices.mapboxToken else {
          throw MotionError("Mapbox tiles need an access token (MAPBOX_ACCESS_TOKEN or the editor's map settings)")
        }
        var components = URLComponents(string: "https://api.mapbox.com/styles/v1/mapbox/\(style)/tiles/256/\(path)@2x")!
        components.queryItems = [URLQueryItem(name: "access_token", value: token)]
        return components.url
      case ("apple", let style) where Self.appleStyles.contains(style): return nil
      default: throw MotionError("Unknown map provider style: \(provider)/\(style)")
      }
      return URL(string: address)
    }

    static let mapboxStyles: Set = ["streets-v12", "outdoors-v12", "light-v11", "dark-v11", "satellite-v9", "satellite-streets-v12"]
    static let appleStyles: Set = ["standard", "muted", "dark", "satellite", "hybrid"]

    var cacheURL: URL {
      MapServices.cacheDirectory.appendingPathComponent("tiles/\(provider)/\(style)/\(zoom)/\(x)/\(y).tile")
    }
  }

  /// Encoded image bytes for a `motionmap://` tile, from the disk cache or the provider.
  public static func tileData(_ source: String) throws -> Data {
    let tile = try Tile(source)
    let cache = tile.cacheURL
    if let data = cachedTileData(at: cache) { return data }
    return try exclusive("tile:\(cache.path)") {
      if let data = cachedTileData(at: cache) { return data }
      if isOffline { return try placeholderTile(tile) }
      let data: Data
      if let url = try tile.remoteURL() {
        data = try download(URLRequest(url: url, timeoutInterval: 20), retries: 1)
      } else {
        data = try appleTile(tile)
      }
      guard CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceGetCount($0) > 0 ? $0 : nil }) != nil else {
        throw MotionError("Map tile \(tile.provider)/\(tile.style)/\(tile.zoom)/\(tile.x)/\(tile.y) is not an image")
      }
      store(data, at: cache)
      rememberTileData(data, key: cache.path)
      return data
    }
  }

  /// A deterministic, uncached grid tile for offline renders.
  static func placeholderTile(_ tile: Tile) throws -> Data {
    guard let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw MotionError("Cannot draw an offline map tile") }
    let shade = (tile.x + tile.y).isMultiple(of: 2) ? 0.93 : 0.89
    context.setFillColor(red: shade, green: shade * 0.99, blue: shade * 0.95, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    context.setStrokeColor(red: 0.7, green: 0.72, blue: 0.74, alpha: 1)
    context.setLineWidth(2)
    context.stroke(CGRect(x: 1, y: 1, width: 254, height: 254))
    guard let image = context.makeImage() else { throw MotionError("Cannot draw an offline map tile") }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
      throw MotionError("Cannot encode an offline map tile")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw MotionError("Cannot encode an offline map tile") }
    return data as Data
  }

  private static func appleTile(_ tile: Tile) throws -> Data {
    #if canImport(MapKit)
    let options = MKMapSnapshotter.Options()
    // MKMapRect is a spherical Mercator plane, so a slippy-map tile is an exact map rect.
    let side = MKMapSize.world.width / pow(2, Double(tile.zoom))
    options.mapRect = MKMapRect(x: Double(tile.x) * side, y: Double(tile.y) * side, width: side, height: side)
    let dark = tile.style == "dark"
    switch tile.style {
    case "muted": options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
    case "satellite": options.preferredConfiguration = MKImageryMapConfiguration()
    case "hybrid": options.preferredConfiguration = MKHybridMapConfiguration()
    default: options.preferredConfiguration = MKStandardMapConfiguration()
    }
    #if os(macOS)
    options.size = CGSize(width: 256, height: 256)
    options.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    #else
    options.size = CGSize(width: 256, height: 256)
    options.traitCollection = UITraitCollection(traitsFrom: [
      UITraitCollection(displayScale: 2), UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
    ])
    #endif
    let box = SnapshotBox()
    let semaphore = DispatchSemaphore(value: 0)
    let snapshotter = MKMapSnapshotter(options: options)
    snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, error in
      box.lock.withLock {
        if let snapshot {
          #if os(macOS)
          var rect = CGRect(x: 0, y: 0, width: 512, height: 512)
          box.image = snapshot.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
          #else
          box.image = snapshot.image.cgImage
          #endif
        }
        box.error = error
      }
      semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 30) == .timedOut {
      snapshotter.cancel()
      throw MotionError("Apple Maps tile \(tile.zoom)/\(tile.x)/\(tile.y) timed out")
    }
    let (image, error) = box.lock.withLock { (box.image, box.error) }
    guard let image else {
      throw MotionError("Apple Maps tile \(tile.zoom)/\(tile.x)/\(tile.y) failed: \(error?.localizedDescription ?? "no image")")
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
      throw MotionError("Cannot encode an Apple Maps tile")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw MotionError("Cannot encode an Apple Maps tile") }
    return data as Data
    #else
    throw MotionError("Apple Maps tiles need MapKit; use another provider on this platform")
    #endif
  }
}

extension MapServices {
  // MARK: Routes

  private struct RouteRequest: Codable {
    let mode: String
    let points: [[Double]]
  }

  /// Posted on the main queue when a route that was reported as pending finishes resolving.
  /// Players re-render so the placeholder line is replaced by the resolved route.
  public static let routesDidResolve = Notification.Name("MotionSwiftMapRoutesDidResolve")

  private static let interactiveKey = "motionswift.map.interactive"
  private static let pendingTilesKey = "motionswift.map.pendingTiles"
  private static let hostTimeKey = "motionswift.map.hostSeconds"

  /// Marks the current thread as an interactive preview: route lookups wait briefly, then report
  /// `pending` (drawn as a placeholder) while the route resolves in the background. Exports and
  /// the CLI keep the default, which waits for the route so every frame shows final geometry.
  public static func setInteractivePreviewThread() {
    Thread.current.threadDictionary[interactiveKey] = true
  }

  /// Seconds this thread has spent waiting on map services. The runtime excludes them from its
  /// async-lifecycle deadline: a slow routing service is not a stuck composition.
  public static var threadHostSeconds: Double {
    Thread.current.threadDictionary[hostTimeKey] as? Double ?? 0
  }

  private static func addHostTime(_ seconds: Double) {
    Thread.current.threadDictionary[hostTimeKey] = threadHostSeconds + seconds
  }

  /// Route geometry for `{mode, points: [[lon, lat], …]}`: `{coordinates, source}`, `{pending, error}`
  /// or `{error}`. Never throws; `<MapRoute>` reports problems in the editor and draws a straight line.
  public static func route(_ requestJSON: String) -> String {
    guard let request = try? JSONDecoder().decode(RouteRequest.self, from: Data(requestJSON.utf8)) else {
      return failure("Invalid route request")
    }
    guard (2...25).contains(request.points.count), request.points.allSatisfy({ point in
      point.count == 2 && point.allSatisfy(\.isFinite) && abs(point[0]) <= 540 && abs(point[1]) <= 90
    }) else { return failure("A route needs 2–25 [longitude, latitude] points") }
    guard ["driving", "cycling", "walking", "railway", "subway", "tram"].contains(request.mode) else {
      return failure("Unsupported route mode \(request.mode)")
    }
    let normalized = RouteRequest(mode: request.mode, points: request.points.map { [normalizeLongitude($0[0]), $0[1]] })
    let canonical = (try? JSONEncoder.sorted.encode(normalized)) ?? Data()
    let key = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    if let memory = routeMemory.withLock({ $0[key] }) { return memory }
    let cache = cacheDirectory.appendingPathComponent("routes/\(key).json")
    if let data = try? Data(contentsOf: cache), let text = String(bytes: data, encoding: .utf8) {
      routeMemory.withLock { $0[key] = text }
      return text
    }
    if isOffline { return failure("Map routing is offline") }
    let interactive = Thread.current.threadDictionary[interactiveKey] as? Bool == true
    let group = resolving.withLock { groups -> DispatchGroup in
      if let group = groups[key] { return group }
      let group = DispatchGroup()
      groups[key] = group
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        let text = resolve(normalized, cache: cache)
        routeMemory.withLock { $0[key] = text }
        let notify = resolving.withLock { groups in
          groups[key] = nil
          return pendingNotifications.remove(key) != nil
        }
        group.leave()
        if notify { DispatchQueue.main.async { NotificationCenter.default.post(name: routesDidResolve, object: nil) } }
      }
      return group
    }
    let begin = ProcessInfo.processInfo.systemUptime
    let finished = group.wait(timeout: .now() + (interactive ? 3 : 180)) == .success
    addHostTime(ProcessInfo.processInfo.systemUptime - begin)
    if finished, let text = routeMemory.withLock({ $0[key] }) { return text }
    let waiting = resolving.withLock { groups in
      guard groups[key] != nil else { return false }
      pendingNotifications.insert(key)
      return true
    }
    if !waiting, let text = routeMemory.withLock({ $0[key] }) { return text }
    let tracks = ["railway", "subway", "tram"].contains(request.mode)
    let label = tracks ? "\(request.mode) tracks" : "\(request.mode) route"
    return (try? String(bytes: JSONSerialization.data(withJSONObject: [
      "pending": true, "error": "Fetching \(label) from OpenStreetMap…",
    ]), encoding: .utf8)) ?? "{\"pending\":true}"
  }

  private static func failure(_ message: String) -> String {
    (try? String(bytes: JSONSerialization.data(withJSONObject: ["error": message]), encoding: .utf8)) ?? "{\"error\":\"route failed\"}"
  }

  /// Fetches and stores one route. Failures are kept in memory only, so a later session retries.
  private static func resolve(_ request: RouteRequest, cache: URL) -> String {
    do {
      let (coordinates, source): ([[Double]], String)
      switch request.mode {
      case "driving", "cycling", "walking": (coordinates, source) = try osrm(mode: request.mode, points: request.points)
      default: (coordinates, source) = try rail(mode: request.mode, points: request.points)
      }
      let object: [String: Any] = ["coordinates": coordinates.map { [round6($0[0]), round6($0[1])] }, "source": source]
      let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      store(data, at: cache)
      return String(bytes: data, encoding: .utf8) ?? "{}"
    } catch {
      return failure(String(describing: error))
    }
  }

  private static let routeMemory = LockedValue<[String: String]>([:])
  private static let resolving = LockedValue<[String: DispatchGroup]>([:])
  nonisolated(unsafe) private static var pendingNotifications = Set<String>()

  private static func osrm(mode: String, points: [[Double]]) throws -> ([[Double]], String) {
    let profile = ["driving": "routed-car", "cycling": "routed-bike", "walking": "routed-foot"][mode]!
    let path = points.map { "\($0[0]),\($0[1])" }.joined(separator: ";")
    guard let url = URL(string: "https://routing.openstreetmap.de/\(profile)/route/v1/driving/\(path)?overview=full&geometries=geojson")
    else { throw MotionError("Invalid route coordinates") }
    let data = try download(URLRequest(url: url, timeoutInterval: 20), retries: 1)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw MotionError("Road routing returned invalid JSON")
    }
    guard object["code"] as? String == "Ok", let routes = object["routes"] as? [[String: Any]],
      let geometry = routes.first?["geometry"] as? [String: Any],
      let coordinates = geometry["coordinates"] as? [[Double]], coordinates.count >= 2
    else {
      throw MotionError("No \(mode) route: \(object["message"] as? String ?? object["code"] as? String ?? "unknown error")")
    }
    return (coordinates, "OSRM (routing.openstreetmap.de) · © OpenStreetMap contributors")
  }

  /// Shortest path over OpenStreetMap railway ways fetched from Overpass, one leg at a time.
  private static func rail(mode: String, points: [[Double]]) throws -> ([[Double]], String) {
    let kinds = switch mode {
    case "subway": "subway|light_rail|monorail"
    case "tram": "tram|light_rail"
    default: "rail|light_rail|narrow_gauge|subway|monorail|funicular"
    }
    var result: [[Double]] = []
    for index in 1..<points.count {
      let (start, end) = (points[index - 1], points[index])
      let span = (abs(start[0] - end[0]), abs(start[1] - end[1]))
      guard span.0 <= 4, span.1 <= 4 else {
        throw MotionError("Railway legs over about 400 km need via points")
      }
      let pad = (max(0.02, span.0 * 0.25), max(0.02, span.1 * 0.25))
      let box = (min(start[1], end[1]) - pad.1, min(start[0], end[0]) - pad.0,
                 max(start[1], end[1]) + pad.1, max(start[0], end[0]) + pad.0)
      let query = "[out:json][timeout:25];way[\"railway\"~\"^(\(kinds))$\"](\(box.0),\(box.1),\(box.2),\(box.3));(._;>;);out skel qt;"
      let graph = try RailGraph(overpass: overpass(query))
      let leg = try graph.path(from: start, to: end, mode: mode)
      result += result.isEmpty ? leg : Array(leg.dropFirst())
    }
    return (result, "OpenStreetMap railways via Overpass API · © OpenStreetMap contributors")
  }

  /// Public Overpass instances are often busy; try each mirror once, in order.
  static let overpassMirrors = [
    "https://overpass-api.de/api/interpreter", "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter", "https://overpass.private.coffee/api/interpreter",
  ]

  private static func overpass(_ query: String) throws -> Data {
    var form = URLComponents()
    form.queryItems = [URLQueryItem(name: "data", value: query)]
    let body = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    var failures: [String] = []
    for mirror in overpassMirrors {
      var request = URLRequest(url: URL(string: mirror)!, timeoutInterval: 35)
      request.httpMethod = "POST"
      request.httpBody = body
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      do { return try download(request, retries: 0) } catch { failures.append(String(describing: error)) }
    }
    throw MotionError("OpenStreetMap railway data is unavailable (\(failures.last ?? "no Overpass mirror answered"))")
  }
}

extension MapServices {
  // MARK: Networking and cache

  private static func download(_ request: URLRequest, retries: Int) throws -> Data {
    var request = request
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    var lastError: any Error = MotionError("Map request failed")
    for attempt in 0...retries {
      if attempt > 0 { Thread.sleep(forTimeInterval: 0.6 * Double(attempt)) }
      let box = DownloadBox()
      let semaphore = DispatchSemaphore(value: 0)
      let task = URLSession.shared.dataTask(with: request) { data, response, error in
        box.lock.withLock {
          box.data = data
          box.status = (response as? HTTPURLResponse)?.statusCode
          box.error = error
        }
        semaphore.signal()
      }
      task.resume()
      if semaphore.wait(timeout: .now() + request.timeoutInterval + 5) == .timedOut {
        task.cancel()
        lastError = MotionError("Map request timed out: \(request.url?.host ?? "")")
        continue
      }
      let (data, status, error) = box.lock.withLock { (box.data, box.status, box.error) }
      if let error {
        lastError = MotionError("Map request to \(request.url?.host ?? "") failed: \(error.localizedDescription)")
        continue
      }
      if let data, status == 200 { return data }
      lastError = MotionError("Map request to \(request.url?.host ?? "") returned HTTP \(status ?? 0)")
      // Client errors (bad token, unknown style) will not succeed on retry.
      if let status, (400..<500).contains(status), status != 429 { break }
    }
    throw lastError
  }

  private static func store(_ data: Data, at url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  private static let locks = LockedValue<[String: NSLock]>([:])

  /// One fetch per key across render workers; the others wait and then read the cache.
  private static func exclusive<T>(_ key: String, _ body: () throws -> T) rethrows -> T {
    let lock = locks.withLock { locks in
      if let lock = locks[key] { return lock }
      if locks.count > 4096 { locks.removeAll() }
      let lock = NSLock()
      locks[key] = lock
      return lock
    }
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  static func normalizeLongitude(_ value: Double) -> Double {
    var longitude = value.truncatingRemainder(dividingBy: 360)
    if longitude > 180 { longitude -= 360 } else if longitude < -180 { longitude += 360 }
    return longitude
  }

  private static func round6(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }
}

/// Haversine distance in meters.
func geodesicDistance(_ first: [Double], _ second: [Double]) -> Double {
  let rad = Double.pi / 180
  let dLat = (second[1] - first[1]) * rad, dLon = (second[0] - first[0]) * rad
  let haversine = sin(dLat / 2) * sin(dLat / 2) + cos(first[1] * rad) * cos(second[1] * rad) * sin(dLon / 2) * sin(dLon / 2)
  return 2 * 6_371_008.8 * asin(min(1, sqrt(haversine)))
}

/// An undirected railway graph from an Overpass `out skel` response.
struct RailGraph {
  private(set) var coordinates: [[Double]] = []
  private(set) var edges: [[(node: Int, cost: Double)]] = []

  init(overpass data: Data) throws {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let elements = object["elements"] as? [[String: Any]]
    else { throw MotionError("Overpass returned invalid JSON") }
    var index: [Int: Int] = [:]
    for element in elements where element["type"] as? String == "node" {
      guard let id = element["id"] as? Int, let lat = element["lat"] as? Double, let lon = element["lon"] as? Double else { continue }
      index[id] = coordinates.count
      coordinates.append([lon, lat])
    }
    edges = Array(repeating: [], count: coordinates.count)
    for element in elements where element["type"] as? String == "way" {
      let nodes = (element["nodes"] as? [Int] ?? []).compactMap { index[$0] }
      for (from, to) in zip(nodes, nodes.dropFirst()) {
        let cost = geodesicDistance(coordinates[from], coordinates[to])
        edges[from].append((to, cost))
        edges[to].append((from, cost))
      }
    }
  }

  init(coordinates: [[Double]], ways: [[Int]]) {
    self.coordinates = coordinates
    edges = Array(repeating: [], count: coordinates.count)
    for nodes in ways {
      for (from, to) in zip(nodes, nodes.dropFirst()) {
        let cost = geodesicDistance(coordinates[from], coordinates[to])
        edges[from].append((to, cost))
        edges[to].append((from, cost))
      }
    }
  }

  /// Nearby track nodes with their snapping distance, closest first.
  func candidates(near point: [Double], radius: Double = 1500, limit: Int = 12) -> [(node: Int, offset: Double)] {
    coordinates.indices.lazy.filter { !edges[$0].isEmpty }
      .map { ($0, geodesicDistance(point, coordinates[$0])) }
      .filter { $0.1 <= radius }
      .sorted { $0.1 < $1.1 }
      .prefix(limit).map { (node: $0.0, offset: $0.1) }
  }

  /// Shortest track path between the best-connected snapping candidates at each end.
  func path(from start: [Double], to end: [Double], mode: String) throws -> [[Double]] {
    let sources = candidates(near: start), targets = candidates(near: end)
    guard !sources.isEmpty else { throw MotionError("No \(mode) track within 1.5 km of the route start") }
    guard !targets.isEmpty else { throw MotionError("No \(mode) track within 1.5 km of the route end") }
    // Snapping costs more than riding the track, so the nearest connected track wins.
    let snap = 4.0
    let targetOffset = Dictionary(targets.map { ($0.node, $0.offset * snap) }) { first, _ in first }
    var distance = [Int: Double](), previous = [Int: Int]()
    var heap = MinHeap()
    for source in sources where source.offset * snap < distance[source.node, default: .infinity] {
      distance[source.node] = source.offset * snap
      heap.push(source.offset * snap, source.node)
    }
    var best: (cost: Double, node: Int)?
    while let (cost, node) = heap.pop() {
      if cost > distance[node, default: .infinity] { continue }
      if let best, cost >= best.cost { break }
      if let offset = targetOffset[node], cost + offset < (best?.cost ?? .infinity) { best = (cost + offset, node) }
      for edge in edges[node] {
        let next = cost + edge.cost
        if next < distance[edge.node, default: .infinity] {
          distance[edge.node] = next
          previous[edge.node] = node
          heap.push(next, edge.node)
        }
      }
    }
    guard let best else { throw MotionError("The route's start and end are not connected by \(mode) track") }
    var nodes = [best.node]
    while let node = previous[nodes.last!] { nodes.append(node) }
    let path = nodes.reversed().map { coordinates[$0] }
    return path.count >= 2 ? path : [start, end]
  }
}

private struct MinHeap {
  private var items: [(Double, Int)] = []
  mutating func push(_ cost: Double, _ node: Int) {
    items.append((cost, node))
    var child = items.count - 1
    while child > 0 {
      let parent = (child - 1) / 2
      guard items[child].0 < items[parent].0 else { break }
      items.swapAt(child, parent)
      child = parent
    }
  }
  mutating func pop() -> (Double, Int)? {
    guard !items.isEmpty else { return nil }
    items.swapAt(0, items.count - 1)
    let top = items.removeLast()
    var parent = 0
    while true {
      let left = parent * 2 + 1, right = left + 1
      var smallest = parent
      if left < items.count, items[left].0 < items[smallest].0 { smallest = left }
      if right < items.count, items[right].0 < items[smallest].0 { smallest = right }
      if smallest == parent { break }
      items.swapAt(parent, smallest)
      parent = smallest
    }
    return top
  }
}

final class LockedValue<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value
  init(_ value: Value) { self.value = value }
  func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }
}

private final class DownloadBox: @unchecked Sendable {
  let lock = NSLock()
  var data: Data?
  var status: Int?
  var error: (any Error)?
}

#if canImport(MapKit)
private final class SnapshotBox: @unchecked Sendable {
  let lock = NSLock()
  var image: CGImage?
  var error: (any Error)?
}
#endif

private extension JSONEncoder {
  static var sorted: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return encoder
  }
}
