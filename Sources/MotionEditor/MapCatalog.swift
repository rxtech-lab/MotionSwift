import CoreGraphics
import Foundation
import MotionCore

/// Map providers, styles and route modes offered by `@motionswift/map` (see `js/remotion-shim/map.js`).
public enum MapCatalog {
  public struct Provider: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let styles: [(id: String, label: String)]
    public let symbol: String
  }

  public static let providers: [Provider] = [
    Provider(id: "openstreetmap", label: "OpenStreetMap", styles: [
      ("standard", "Standard"), ("humanitarian", "Humanitarian"), ("topographic", "Topographic"),
      ("light", "Light"), ("dark", "Dark"),
    ], symbol: "map"),
    Provider(id: "apple", label: "Apple Maps", styles: [
      ("standard", "Standard"), ("muted", "Muted"), ("dark", "Dark"), ("satellite", "Satellite"), ("hybrid", "Hybrid"),
    ], symbol: "apple.logo"),
    Provider(id: "mapbox", label: "Mapbox", styles: [
      ("streets-v12", "Streets"), ("outdoors-v12", "Outdoors"), ("light-v11", "Light"), ("dark-v11", "Dark"),
      ("satellite-v9", "Satellite"), ("satellite-streets-v12", "Satellite Streets"),
    ], symbol: "globe"),
  ]

  public static func provider(_ id: String?) -> Provider { providers.first { $0.id == id } ?? providers[0] }

  public struct Mode: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let symbol: String
    public let detail: String
  }

  public static let modes: [Mode] = [
    Mode(id: "straight", label: "Straight line", symbol: "line.diagonal", detail: "Great-circle line, computed locally"),
    Mode(id: "arc", label: "Flight arc", symbol: "airplane", detail: "Curved arc, computed locally"),
    Mode(id: "driving", label: "Drive", symbol: "car.fill", detail: "Follows roads (OSRM, OpenStreetMap)"),
    Mode(id: "cycling", label: "Cycle", symbol: "bicycle", detail: "Follows cycleable roads (OSRM)"),
    Mode(id: "walking", label: "Walk", symbol: "figure.walk", detail: "Follows footpaths and streets (OSRM)"),
    Mode(id: "railway", label: "Railway", symbol: "tram.fill", detail: "Follows OpenStreetMap railway tracks"),
    Mode(id: "subway", label: "Subway", symbol: "tram.tunnel.fill", detail: "Follows metro and light-rail tracks"),
    Mode(id: "tram", label: "Tram", symbol: "lightrail.fill", detail: "Follows tram and light-rail tracks"),
  ]

  public static let attributionCorners = ["bottom-right", "bottom-left", "top-right", "top-left"]

  /// Keys captured by Add Keyframe for each component (camera moves, journeys, marker paths).
  public static func keyframeKeys(_ type: String?) -> Set<String> {
    switch type {
    case "MapView": ["centerLongitude", "centerLatitude", "zoom", "bearing"]
    case "MapRoute": ["progress"]
    case "MapMarker": ["longitude", "latitude"]
    default: []
    }
  }

  public static func label(for key: String) -> String {
    [
      "centerLongitude": "Center longitude", "centerLatitude": "Center latitude", "zoom": "Zoom", "bearing": "Bearing°",
      "provider": "Provider", "mapStyle": "Map style", "saturation": "Saturation", "brightness": "Brightness",
      "attribution": "Attribution", "fromLongitude": "Start longitude", "fromLatitude": "Start latitude",
      "toLongitude": "End longitude", "toLatitude": "End latitude", "mode": "Follow", "progress": "Progress",
      "color": "Color", "width": "Line width", "outlineColor": "Outline color", "markerSize": "Head marker size",
      "longitude": "Longitude", "latitude": "Latitude", "size": "Size", "label": "Label",
    ][key] ?? key
  }
}

extension StylePropertyDefinition {
  /// Typed controls for `@motionswift/map` props; styles depend on the map's provider.
  static func map(_ key: String, provider: String?) -> Self? {
    switch key {
    case "provider": return Self(id: key, control: .options(MapCatalog.providers.map(\.id)))
    case "mapStyle": return Self(id: key, control: .options(MapCatalog.provider(provider).styles.map(\.id)))
    case "mode": return Self(id: key, control: .options(MapCatalog.modes.map(\.id)))
    case "attribution": return Self(id: key, control: .options(MapCatalog.attributionCorners))
    case "color", "outlineColor": return Self(id: key, control: .color)
    case "label": return Self(id: key, control: .text)
    case "progress": return Self(id: key, control: .opacity)
    case "centerLongitude", "centerLatitude", "zoom", "bearing", "saturation", "brightness", "fromLongitude",
      "fromLatitude", "toLongitude", "toLatitude", "width", "markerSize", "longitude", "latitude", "size":
      return Self(id: key, control: .number)
    default: return nil
    }
  }
}

/// Web Mercator camera of an evaluated `<MapView>`, in composition pixels.
public struct MapCamera: Equatable, Sendable {
  public var longitude: Double
  public var latitude: Double
  public var zoom: Double
  public var bearing: Double
  public var size: CGSize
  /// Top-left of the map in the composition.
  public var origin: CGPoint

  static let tile = 256.0
  static let maxLatitude = 85.0511287798

  init?(_ properties: [String: JSONValue], origin: CGPoint) {
    guard let longitude = properties["centerLongitude"]?.number, let latitude = properties["centerLatitude"]?.number,
      let zoom = properties["zoom"]?.number else { return nil }
    self.longitude = longitude
    self.latitude = latitude
    self.zoom = zoom
    bearing = properties["bearing"]?.number ?? 0
    size = CGSize(width: properties["width"]?.number ?? 0, height: properties["height"]?.number ?? 0)
    self.origin = origin
  }

  public init(longitude: Double, latitude: Double, zoom: Double, bearing: Double = 0, size: CGSize, origin: CGPoint = .zero) {
    (self.longitude, self.latitude, self.zoom, self.bearing, self.size, self.origin) = (longitude, latitude, zoom, bearing, size, origin)
  }

  static func world(_ longitude: Double, _ latitude: Double, zoom: Double) -> CGPoint {
    let scale = tile * pow(2, zoom)
    let sine = sin(min(max(latitude, -maxLatitude), maxLatitude) * .pi / 180)
    return CGPoint(x: (longitude + 180) / 360 * scale, y: (0.5 - log((1 + sine) / (1 - sine)) / (4 * .pi)) * scale)
  }

  static func coordinate(_ point: CGPoint, zoom: Double) -> (longitude: Double, latitude: Double) {
    let scale = tile * pow(2, zoom)
    let mercator = Double.pi - 2 * .pi * point.y / scale
    return (point.x / scale * 360 - 180, 180 / .pi * atan(sinh(mercator)))
  }

  /// Composition point of a coordinate (the nearest copy of the world).
  public func project(_ longitude: Double, _ latitude: Double) -> CGPoint {
    let middle = Self.world(self.longitude, self.latitude, zoom: zoom)
    let point = Self.world(longitude, latitude, zoom: zoom)
    let world = Self.tile * pow(2, zoom)
    var dx = point.x - middle.x
    dx -= (dx / world).rounded() * world
    let dy = point.y - middle.y
    let angle = -bearing * .pi / 180
    return CGPoint(x: origin.x + size.width / 2 + dx * cos(angle) - dy * sin(angle),
                   y: origin.y + size.height / 2 + dx * sin(angle) + dy * cos(angle))
  }

  /// Coordinate under a composition point.
  public func unproject(_ point: CGPoint) -> (longitude: Double, latitude: Double) {
    let middle = Self.world(longitude, latitude, zoom: zoom)
    let dx = point.x - origin.x - size.width / 2, dy = point.y - origin.y - size.height / 2
    let angle = -bearing * .pi / 180
    var result = Self.coordinate(CGPoint(x: middle.x + dx * cos(angle) + dy * sin(angle),
                                         y: middle.y - dx * sin(angle) + dy * cos(angle)), zoom: zoom)
    result.longitude = (result.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
    return result
  }

  /// The camera that frames two coordinates with `padding` composition pixels on every side.
  public func framing(_ first: (Double, Double), _ second: (Double, Double), padding: Double = 80) -> MapCamera {
    let pa = Self.world(first.0, first.1, zoom: 0), pb = Self.world(second.0, second.1, zoom: 0)
    let width = max(abs(pa.x - pb.x), 1e-9), height = max(abs(pa.y - pb.y), 1e-9)
    let fit = min((size.width - 2 * padding) / width, (size.height - 2 * padding) / height)
    let center = Self.coordinate(CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2), zoom: 0)
    var camera = self
    camera.longitude = center.longitude
    camera.latitude = center.latitude
    camera.zoom = min(max(log2(max(fit, 1e-9)), 1), 18)
    camera.bearing = 0
    return camera
  }
}
