import Foundation
import ModelIO
import MotionCore
import simd

/// Loads USD, USDA, USDC and USDZ files with ModelIO (Apple's USD importer) into triangle meshes
/// with UsdPreviewSurface materials. Like three.js' USDLoader, preview-surface colors are linear and
/// become MeshPhysicalMaterial-equivalent parameters. Textures are not supported yet.
enum USDModelLoader {
  struct Part {
    let mesh: Mesh3D
    let matrix: M4
    let material: Scene3D.Material
  }

  private static let cache = ModelCache()

  static func load(_ source: String) throws -> [Part] {
    let url = try MediaSource.url(source)
    if let parts = cache.parts(for: url.absoluteString) { return parts }
    guard url.isFileURL else { throw MotionError("3D models must be local files or staticFile() paths: \(source)") }
    guard FileManager.default.fileExists(atPath: url.path) else { throw MotionError("3D model not found: \(url.path)") }
    guard ["usd", "usda", "usdc", "usdz"].contains(url.pathExtension.lowercased()),
      MDLAsset.canImportFileExtension(url.pathExtension.lowercased())
    else { throw MotionError("Unsupported 3D model format: \(url.lastPathComponent); use USD/USDA/USDC/USDZ") }
    let descriptor = MDLVertexDescriptor()
    descriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0,
      bufferIndex: 0)
    descriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 0,
      bufferIndex: 1)
    descriptor.layouts[0] = MDLVertexBufferLayout(stride: 12)
    descriptor.layouts[1] = MDLVertexBufferLayout(stride: 12)
    let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: nil)
    var parts: [Part] = []
    for index in 0..<asset.count {
      try collect(asset.object(at: index), descriptor: descriptor, into: &parts)
    }
    guard !parts.isEmpty else { throw MotionError("3D model has no meshes: \(url.lastPathComponent)") }
    cache.store(parts, for: url.absoluteString)
    return parts
  }

  private static func collect(_ object: MDLObject, descriptor: MDLVertexDescriptor, into parts: inout [Part]) throws {
    if let mesh = object as? MDLMesh {
      if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
        mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0)
      }
      mesh.vertexDescriptor = descriptor
      let transform = MDLTransform.globalTransform(with: object, atTime: 0)
      let columns = [transform.columns.0, transform.columns.1, transform.columns.2, transform.columns.3]
      let matrix = M4(e: columns.flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] })
      let count = mesh.vertexCount
      let positions = floats(mesh.vertexBuffers[0], count: count * 3)
      let normals = floats(mesh.vertexBuffers[1], count: count * 3)
      for submesh in mesh.submeshes as? [MDLSubmesh] ?? [] {
        guard submesh.geometryType == .triangles else {
          throw MotionError("3D model submeshes must be triangulated (found \(submesh.geometryType.rawValue))")
        }
        parts.append(Part(mesh: Mesh3D(positions: positions, normals: normals, indices: indices(submesh)),
          matrix: matrix, material: material(submesh.material)))
      }
    }
    for child in object.children.objects { try collect(child, descriptor: descriptor, into: &parts) }
  }

  private static func floats(_ buffer: any MDLMeshBuffer, count: Int) -> [Float] {
    let map = buffer.map()
    return Array(UnsafeBufferPointer(start: map.bytes.assumingMemoryBound(to: Float.self), count: count))
  }

  private static func indices(_ submesh: MDLSubmesh) -> [UInt32] {
    let map = submesh.indexBuffer.map()
    let count = submesh.indexCount
    switch submesh.indexType {
    case .uInt8: return UnsafeBufferPointer(start: map.bytes.assumingMemoryBound(to: UInt8.self), count: count).map(UInt32.init)
    case .uInt16: return UnsafeBufferPointer(start: map.bytes.assumingMemoryBound(to: UInt16.self), count: count).map(UInt32.init)
    default: return Array(UnsafeBufferPointer(start: map.bytes.assumingMemoryBound(to: UInt32.self), count: count))
    }
  }

  private static func material(_ source: MDLMaterial?) -> Scene3D.Material {
    func value(_ semantic: MDLMaterialSemantic) -> MDLMaterialProperty? { source?.property(with: semantic) }
    func color(_ semantic: MDLMaterialSemantic, _ fallback: [Double]) -> [Double] {
      guard let property = value(semantic) else { return fallback }
      switch property.type {
      case .float3: return [Double(property.float3Value.x), Double(property.float3Value.y), Double(property.float3Value.z)]
      case .float4: return [Double(property.float4Value.x), Double(property.float4Value.y), Double(property.float4Value.z)]
      case .float: return Array(repeating: Double(property.floatValue), count: 3)
      case .color:
        guard let components = property.color?.components, components.count >= 3 else { return fallback }
        return components.prefix(3).map(Double.init)
      default: return fallback
      }
    }
    func scalar(_ semantic: MDLMaterialSemantic, _ fallback: Double) -> Double {
      guard let property = value(semantic), property.type == .float else { return fallback }
      return Double(property.floatValue)
    }
    let opacity = min(1, max(0, scalar(.opacity, 1)))
    return Scene3D.Material(
      type: "physical", color: color(.baseColor, [0.18, 0.18, 0.18]), emissive: color(.emission, [0, 0, 0]),
      roughness: scalar(.roughness, 0.5), metalness: scalar(.metallic, 0), opacity: opacity, transparent: opacity < 1)
  }
}

private final class ModelCache: @unchecked Sendable {
  private let lock = NSLock()
  private var models: [String: [USDModelLoader.Part]] = [:]

  func parts(for source: String) -> [USDModelLoader.Part]? { lock.withLock { models[source] } }
  func store(_ parts: [USDModelLoader.Part], for source: String) { lock.withLock { models[source] = parts } }
}
