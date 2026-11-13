import Foundation

/// A `<ThreeCanvas>` scene as committed by the runtime. Values are already resolved the way
/// three.js r187 + React Three Fiber 8 resolve them: colors are linear sRGB, rotations are
/// quaternions and every material/light default is explicit. The native 3D renderer draws it.
public struct Scene3D: Codable, Sendable, Equatable {
  public struct Fog: Codable, Sendable, Equatable {
    /// `linear` (three.js `Fog`) or `exp2` (`FogExp2`).
    public var type: String
    public var color: [Double]
    public var near: Double
    public var far: Double
    public var density: Double
  }

  public struct Camera: Codable, Sendable, Equatable {
    public var fov: Double
    public var near: Double
    public var far: Double
    public var zoom: Double
    /// Set only when the composition fixed the aspect ratio (`camera.manual` in R3F).
    public var aspect: Double?
    public var position: [Double]
    public var quaternion: [Double]
  }

  public struct Geometry: Codable, Sendable, Equatable, Hashable {
    /// `box`, `sphere`, `plane`, `cylinder`, `cone`, `torus`, `torusKnot`, `circle`, `ring`,
    /// `icosahedron`, `octahedron`, `tetrahedron` or `dodecahedron`.
    public var type: String
    /// Constructor arguments in three.js order; missing trailing arguments use three.js defaults.
    public var args: [Double]

    public init(type: String, args: [Double]) {
      self.type = type
      self.args = args
    }
  }

  public struct Material: Codable, Sendable, Equatable {
    /// `basic`, `lambert`, `phong`, `standard`, `physical` or `normal`.
    public var type: String
    public var color: [Double]
    public var emissive: [Double]
    public var emissiveIntensity: Double
    public var roughness: Double
    public var metalness: Double
    public var opacity: Double
    public var transparent: Bool
    /// 0 front, 1 back, 2 double.
    public var side: Int
    public var flatShading: Bool
    public var specular: [Double]
    public var shininess: Double
    public var toneMapped: Bool
    public var depthTest: Bool
    public var depthWrite: Bool
    public var fog: Bool
    public var ior: Double
    public var visible: Bool

    public init(
      type: String, color: [Double], emissive: [Double] = [0, 0, 0], emissiveIntensity: Double = 1,
      roughness: Double = 1, metalness: Double = 0, opacity: Double = 1, transparent: Bool = false, side: Int = 0,
      flatShading: Bool = false, specular: [Double] = [0.005181, 0.005181, 0.005181], shininess: Double = 30,
      toneMapped: Bool = true, depthTest: Bool = true, depthWrite: Bool = true, fog: Bool = true, ior: Double = 1.5,
      visible: Bool = true
    ) {
      self.type = type
      self.color = color
      self.emissive = emissive
      self.emissiveIntensity = emissiveIntensity
      self.roughness = roughness
      self.metalness = metalness
      self.opacity = opacity
      self.transparent = transparent
      self.side = side
      self.flatShading = flatShading
      self.specular = specular
      self.shininess = shininess
      self.toneMapped = toneMapped
      self.depthTest = depthTest
      self.depthWrite = depthWrite
      self.fog = fog
      self.ior = ior
      self.visible = visible
    }
  }

  public struct Light: Codable, Sendable, Equatable {
    public var color: [Double]
    public var groundColor: [Double]
    public var intensity: Double
    public var distance: Double
    public var decay: Double
    public var angle: Double
    public var penumbra: Double
  }

  public struct Object: Codable, Sendable, Equatable {
    /// `group`, `mesh`, `model`, `ambient`, `hemisphere`, `directional`, `point` or `spot`.
    public let kind: String
    public let position: [Double]
    public let quaternion: [Double]
    public let scale: [Double]
    public let visible: Bool
    public let renderOrder: Double
    public let geometry: Geometry?
    public let material: Material?
    public let light: Light?
    /// Model source (`static:`, file path or URL) for `model` objects.
    public let src: String?
    public let children: [Object]
  }

  /// Canvas size in CSS pixels.
  public var width: Double
  public var height: Double
  /// R3F `dpr` range; the device pixel ratio (render scale) is clamped into it.
  public var dpr: [Double]
  /// R3F `flat`: no tone mapping.
  public var flat: Bool
  public var background: [Double]?
  public var fog: Fog?
  public var camera: Camera
  public var objects: [Object]

  public static func decode(_ json: String) throws -> Scene3D {
    do {
      let scene = try JSONDecoder().decode(Scene3D.self, from: Data(json.utf8))
      try scene.validate()
      return scene
    } catch let error as MotionError {
      throw error
    } catch {
      throw MotionError("Invalid ThreeCanvas scene: \(error)")
    }
  }

  public func validate() throws {
    guard width > 0, height > 0, width.isFinite, height.isFinite else { throw MotionError("ThreeCanvas size must be positive") }
    guard dpr.count == 2, dpr[0] > 0, dpr[1] >= dpr[0] else { throw MotionError("ThreeCanvas dpr must be a positive range") }
    guard camera.near > 0, camera.far > camera.near, camera.fov > 0, camera.fov < 180, camera.zoom > 0,
      camera.position.count == 3, camera.quaternion.count == 4
    else { throw MotionError("ThreeCanvas camera needs 0 < near < far, 0 < fov < 180 and a positive zoom") }
    func check(_ object: Object) throws {
      guard object.position.count == 3, object.quaternion.count == 4, object.scale.count == 3 else {
        throw MotionError("Invalid 3D transform on \(object.kind)")
      }
      if let material = object.material {
        guard ["basic", "lambert", "phong", "standard", "physical", "normal"].contains(material.type),
          (0...1).contains(material.opacity), (0...2).contains(material.side)
        else { throw MotionError("Unsupported 3D material: \(material.type)") }
      }
      try object.children.forEach(check)
    }
    try objects.forEach(check)
  }

  /// Sources of every `model` object, for preloading.
  public var modelSources: [String] {
    func visit(_ object: Object) -> [String] { (object.src.map { [$0] } ?? []) + object.children.flatMap(visit) }
    return objects.flatMap(visit)
  }
}
