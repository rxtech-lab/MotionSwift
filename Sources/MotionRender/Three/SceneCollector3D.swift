import Foundation
import Metal
import MotionCore
import simd

// Layouts mirror the structs in Shaders3D.swift (float3 is 16-byte aligned in both languages).
struct FrameUniforms {
  var projection = matrix_identity_float4x4
  var ambient = SIMD3<Float>(repeating: 0)
  var fogColor = SIMD3<Float>(repeating: 0)
  var fogNear: Float = 0
  var fogFar: Float = 0
  var fogDensity: Float = 0
  var fogType: Int32 = 0
  var toneMapping: Int32 = 1
  var pointCount: Int32 = 0
  var spotCount: Int32 = 0
  var directionalCount: Int32 = 0
  var hemisphereCount: Int32 = 0
}

struct ObjectUniforms {
  var modelView = matrix_identity_float4x4
  var normalMatrix = matrix_identity_float4x4
  var diffuse = SIMD3<Float>(repeating: 1)
  var emissive = SIMD3<Float>(repeating: 0)
  var specular = SIMD3<Float>(repeating: 0)
  var specularColor = SIMD3<Float>(repeating: 0.04)
  var opacity: Float = 1
  var roughness: Float = 1
  var metalness: Float = 0
  var shininess: Float = 30
  var specularF90: Float = 1
  var material: Int32 = 0
  var flatShading: Int32 = 0
  var doubleSided: Int32 = 0
  var flipSided: Int32 = 0
  var opaque: Int32 = 1
  var toneMapped: Int32 = 1
  var fog: Int32 = 1
}

struct PointLightUniform {
  var position: SIMD3<Float>
  var color: SIMD3<Float>
  var distance: Float
  var decay: Float
}

struct SpotLightUniform {
  var position: SIMD3<Float>
  var direction: SIMD3<Float>
  var color: SIMD3<Float>
  var distance: Float
  var decay: Float
  var coneCos: Float
  var penumbraCos: Float
}

struct DirectionalLightUniform {
  var direction: SIMD3<Float>
  var color: SIMD3<Float>
}

struct HemisphereLightUniform {
  var direction: SIMD3<Float>
  var skyColor: SIMD3<Float>
  var groundColor: SIMD3<Float>
}

final class GPUMesh {
  let positions: any MTLBuffer
  let normals: any MTLBuffer
  let indices: (any MTLBuffer)?
  let count: Int
  let center: SIMD3<Double>

  init(_ mesh: Mesh3D, device: any MTLDevice) throws {
    guard mesh.vertexCount > 0,
      let positions = device.makeBuffer(bytes: mesh.positions, length: mesh.positions.count * 4),
      let normals = device.makeBuffer(bytes: mesh.normals, length: mesh.normals.count * 4)
    else { throw MotionError("Cannot allocate 3D geometry buffers") }
    self.positions = positions
    self.normals = normals
    if let indices = mesh.indices {
      guard let buffer = device.makeBuffer(bytes: indices, length: max(4, indices.count * 4)) else {
        throw MotionError("Cannot allocate 3D index buffer")
      }
      self.indices = buffer
    } else {
      self.indices = nil
    }
    count = mesh.drawCount
    center = mesh.center
  }
}

struct ModelPart3D {
  let mesh: GPUMesh
  let matrix: M4
  let material: Scene3D.Material
}

struct RenderItem3D {
  let mesh: GPUMesh
  let world: M4
  let material: Scene3D.Material
  let renderOrder: Double
  let materialID: Int
  let id: Int
  var depth: Double = 0
}

/// One frame of a `Scene3D` resolved the way WebGLRenderer resolves it: world matrices, view-space
/// lights in traversal order, and three's opaque (front to back) and transparent (back to front) lists.
struct SceneFrame3D {
  var frame = FrameUniforms()
  var view = M4.identity
  var points: [PointLightUniform] = []
  var spots: [SpotLightUniform] = []
  var directionals: [DirectionalLightUniform] = []
  var hemispheres: [HemisphereLightUniform] = []
  var opaque: [RenderItem3D] = []
  var transparent: [RenderItem3D] = []

  init(_ scene: Scene3D, mesh: (Scene3D.Geometry) throws -> GPUMesh, model: (String) throws -> [ModelPart3D]) throws {
    let camera = scene.camera
    view = M4.compose(position: camera.position, quaternion: camera.quaternion, scale: [1, 1, 1]).inverted()
    let projection = M4.perspective(fov: camera.fov, aspect: camera.aspect ?? scene.width / scene.height,
      near: camera.near, far: camera.far, zoom: camera.zoom)
    frame.projection = projection.float
    frame.toneMapping = scene.flat ? 0 : 1
    if let fog = scene.fog {
      frame.fogType = fog.type == "exp2" ? 2 : 1
      frame.fogColor = Math3D.vector(fog.color.map(Math3D.linearToSRGB))
      frame.fogNear = Float(fog.near)
      frame.fogFar = Float(fog.far)
      frame.fogDensity = Float(fog.density)
    }
    var items: [RenderItem3D] = []
    var ambient = SIMD3<Double>(repeating: 0)
    var counter = 0
    func visit(_ object: Scene3D.Object, parent: M4?) throws {
      guard object.visible else { return }
      let local = M4.compose(position: object.position, quaternion: object.quaternion, scale: object.scale)
      // Root objects' parent is the scene, whose world matrix is the identity.
      let world = parent.map { $0 * local } ?? local
      counter += 1
      switch object.kind {
      case "mesh":
        if let geometry = object.geometry, let material = object.material, material.visible {
          items.append(RenderItem3D(mesh: try mesh(geometry), world: world, material: material,
            renderOrder: object.renderOrder, materialID: counter, id: counter))
        }
      case "model":
        for part in try object.src.map(model) ?? [] {
          counter += 1
          items.append(RenderItem3D(mesh: part.mesh, world: world * part.matrix, material: part.material,
            renderOrder: object.renderOrder, materialID: counter, id: counter))
        }
      case "ambient":
        if let light = object.light { ambient += Self.scaled(light.color, light.intensity) }
      case "group": break
      default:
        guard let light = object.light else { throw MotionError("Unsupported 3D object: \(object.kind)") }
        try addLight(object.kind, light, world: world)
      }
      for child in object.children { try visit(child, parent: world) }
    }
    for object in scene.objects { try visit(object, parent: nil) }
    frame.ambient = Math3D.vector(ambient)
    frame.pointCount = Int32(points.count)
    frame.spotCount = Int32(spots.count)
    frame.directionalCount = Int32(directionals.count)
    frame.hemisphereCount = Int32(hemispheres.count)
    let projectionView = projection * view
    for index in items.indices {
      items[index].depth = projectionView.clipZ(items[index].world.transformPoint(items[index].mesh.center))
    }
    opaque = items.filter { !$0.material.transparent }.sorted { lhs, rhs in
      if lhs.renderOrder != rhs.renderOrder { return lhs.renderOrder < rhs.renderOrder }
      if lhs.materialID != rhs.materialID { return lhs.materialID < rhs.materialID }
      if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
      return lhs.id < rhs.id
    }
    transparent = items.filter(\.material.transparent).sorted { lhs, rhs in
      if lhs.renderOrder != rhs.renderOrder { return lhs.renderOrder < rhs.renderOrder }
      if lhs.depth != rhs.depth { return lhs.depth > rhs.depth }
      return lhs.id < rhs.id
    }
  }

  private static func scaled(_ color: [Double], _ intensity: Double) -> SIMD3<Double> {
    SIMD3(color[0] * intensity, color[1] * intensity, color[2] * intensity)
  }

  /// WebGLLights.setupView: positions and directions in view space, colors times intensity.
  /// Directional and spot lights aim at their default target, the world origin.
  private mutating func addLight(_ kind: String, _ light: Scene3D.Light, world: M4) throws {
    let color = Math3D.vector(Self.scaled(light.color, light.intensity))
    let position = Math3D.vector(view.transformPoint(world.position))
    let direction = Math3D.vector(view.transformDirection(world.position))
    switch kind {
    case "hemisphere":
      hemispheres.append(HemisphereLightUniform(direction: direction, skyColor: color,
        groundColor: Math3D.vector(Self.scaled(light.groundColor, light.intensity))))
    case "directional":
      directionals.append(DirectionalLightUniform(direction: direction, color: color))
    case "point":
      points.append(PointLightUniform(position: position, color: color, distance: Float(light.distance),
        decay: Float(light.decay)))
    case "spot":
      spots.append(SpotLightUniform(position: position, direction: direction, color: color,
        distance: Float(light.distance), decay: Float(light.decay), coneCos: Float(cos(light.angle)),
        penumbraCos: Float(cos(light.angle * (1 - light.penumbra)))))
    default: throw MotionError("Unsupported 3D light: \(kind)")
    }
  }
}
