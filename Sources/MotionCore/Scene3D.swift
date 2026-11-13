import Foundation

/// A `<ThreeCanvas>` scene as committed by the runtime. Values are already resolved the way
/// three.js r187 + React Three Fiber 8 resolve them: colors are linear sRGB, rotations are
/// quaternions and every material/light default is explicit. The native 3D renderer draws it.
public struct Scene3D: Codable, Sendable, Equatable {
  /// Stamped R3F elements, including material children consumed by scene serialization.
  public struct EditorElement: Codable, Sendable, Equatable {
    public let source: String
    public let type: String
    public let properties: [String: JSONValue]
  }

  public var editor: [EditorElement]?
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
    public var position: [Double]
    public var quaternion: [Double]
    public var scale: [Double]
    public let visible: Bool
    public let renderOrder: Double
    public let geometry: Geometry?
    public let material: Material?
    public let light: Light?
    /// Model source (`static:`, file path or URL) for `model` objects.
    public let src: String?
    /// Editor stamp (`file:line:column`) of the JSX element, present only in editor builds.
    public var source: String?
    public var children: [Object]
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

// MARK: Editor previews

extension Scene3D {
  /// three.js `Euler` (order XYZ, radians) → quaternion `[x, y, z, w]`.
  public static func quaternion(euler: [Double]) -> [Double] {
    let (c1, c2, c3) = (cos(euler[0] / 2), cos(euler[1] / 2), cos(euler[2] / 2))
    let (s1, s2, s3) = (sin(euler[0] / 2), sin(euler[1] / 2), sin(euler[2] / 2))
    return [s1 * c2 * c3 + c1 * s2 * s3, c1 * s2 * c3 - s1 * c2 * s3,
            c1 * c2 * s3 + s1 * s2 * c3, c1 * c2 * c3 - s1 * s2 * s3]
  }

  /// Quaternion `[x, y, z, w]` → three.js `Euler` (order XYZ, radians), as `Euler.setFromQuaternion`.
  public static func euler(quaternion value: [Double]) -> [Double] {
    let (qx, qy, qz, qw) = (value[0], value[1], value[2], value[3])
    let m11 = 1 - 2 * (qy * qy + qz * qz), m12 = 2 * (qx * qy - qz * qw), m13 = 2 * (qx * qz + qy * qw)
    let m22 = 1 - 2 * (qx * qx + qz * qz), m23 = 2 * (qy * qz - qx * qw)
    let m32 = 2 * (qy * qz + qx * qw), m33 = 1 - 2 * (qx * qx + qy * qy)
    let ry = asin(min(max(m13, -1), 1))
    if abs(m13) < 0.9999999 { return [atan2(-m23, m33), ry, atan2(-m12, m11)] }
    return [atan2(m32, m22), ry, 0]
  }

  /// Applies editor preview patches (keyed by editor stamp) to the camera of the canvas stamped
  /// `canvas` and to stamped objects, so 3D drags preview without re-running JavaScript.
  public func applying(_ overrides: [String: [String: JSONValue]], canvas: String?) -> Scene3D {
    var scene = self
    func patched(_ values: [Double], _ patch: [String: JSONValue], _ prefix: String) -> [Double]? {
      let keys = ["X", "Y", "Z"].map { prefix + $0 }
      guard keys.contains(where: { patch[$0]?.number != nil }) else { return nil }
      var result = values
      for (index, key) in keys.enumerated() { if let number = patch[key]?.number { result[index] = number } }
      return result
    }
    if let canvas, let patch = overrides[canvas] {
      if let position = patched(camera.position, patch, "cameraPosition") { scene.camera.position = position }
      if let euler = patched(Self.euler(quaternion: camera.quaternion), patch, "cameraRotation") {
        scene.camera.quaternion = Self.quaternion(euler: euler)
      }
      if let fov = patch["cameraFov"]?.number, fov > 0, fov < 180 { scene.camera.fov = fov }
      if let zoom = patch["cameraZoom"]?.number, zoom > 0 { scene.camera.zoom = zoom }
    }
    func visit(_ object: Object) -> Object {
      var object = object
      if let source = object.source, let patch = overrides[source] {
        if let position = patched(object.position, patch, "position") { object.position = position }
        if let euler = patched(Self.euler(quaternion: object.quaternion), patch, "rotation") {
          object.quaternion = Self.quaternion(euler: euler)
        }
        if let scale = patched(object.scale, patch, "scale") { object.scale = scale }
      }
      object.children = object.children.map(visit)
      return object
    }
    scene.objects = objects.map(visit)
    if let editor {
      scene.editor = editor.map { element in
        guard let patch = overrides[element.source] else { return element }
        let properties = element.properties.merging(patch.filter { element.properties[$0.key] != nil }) { _, new in new }
        return EditorElement(source: element.source, type: element.type, properties: properties)
      }
    }
    return scene
  }
}

extension RenderNode {
  public var threeEditorElements: [Scene3D.EditorElement] {
    (scene?.editor ?? []) + children.flatMap(\.threeEditorElements)
  }
}
