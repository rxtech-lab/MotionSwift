import Foundation
import Metal
import MotionCore
import simd

public struct Scene3DPixelSize: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public let dpr: Double
}

/// Premultiplied RGBA8 pixels of one rendered `<ThreeCanvas>`, rows tightly packed.
public struct Scene3DImage: Sendable {
  public let pixels: Data
  public let width: Int
  public let height: Int
}

/// Draws `Scene3D` descriptions with Metal, reproducing three.js WebGLRenderer output: MSAA x4,
/// 8-bit sRGB-encoded blending, depth LessEqual, three's opaque/transparent sort order. Not
/// thread-safe; each `Renderer` (one per worker) owns one.
public final class SceneRenderer3D {
  private static let libraries = LibraryCache()
  private let device: any MTLDevice
  private let queue: any MTLCommandQueue
  private let opaquePipeline: any MTLRenderPipelineState
  private let blendPipeline: any MTLRenderPipelineState
  private var depthStates: [Int: any MTLDepthStencilState] = [:]
  private let lut: any MTLTexture
  private let lutSampler: any MTLSamplerState
  private let sampleCount: Int
  private var meshes: [Scene3D.Geometry: GPUMesh] = [:]
  private var models: [String: [ModelPart3D]] = [:]
  private var targets: RenderTargets?
  private var readback: (any MTLBuffer)?

  public init() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw MotionError("<ThreeCanvas> requires a Metal device")
    }
    self.device = device
    self.queue = queue
    let samples = device.supportsTextureSampleCount(4) ? 4 : 1
    sampleCount = samples
    let library = try Self.libraries.library(for: device)
    guard let vertex = library.makeFunction(name: "scene3d_vertex"),
      let fragment = library.makeFunction(name: "scene3d_fragment")
    else { throw MotionError("Missing 3D shader functions") }
    func pipeline(blending: Bool) throws -> any MTLRenderPipelineState {
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = vertex
      descriptor.fragmentFunction = fragment
      descriptor.rasterSampleCount = samples
      descriptor.depthAttachmentPixelFormat = .depth32Float
      let color = descriptor.colorAttachments[0]!
      color.pixelFormat = .rgba8Unorm
      if blending {
        // three.js NormalBlending without premultiplied alpha.
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .sourceAlpha
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
      }
      return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    opaquePipeline = try pipeline(blending: false)
    blendPipeline = try pipeline(blending: true)
    let lutDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Float, width: 16, height: 16,
      mipmapped: false)
    lutDescriptor.usage = .shaderRead
    guard let lut = device.makeTexture(descriptor: lutDescriptor) else { throw MotionError("Cannot allocate DFG LUT") }
    dfgLUTHalfFloats.withUnsafeBytes { bytes in
      lut.replace(region: MTLRegionMake2D(0, 0, 16, 16), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: 64)
    }
    self.lut = lut
    let samplerDescriptor = MTLSamplerDescriptor()
    samplerDescriptor.minFilter = .linear
    samplerDescriptor.magFilter = .linear
    samplerDescriptor.sAddressMode = .clampToEdge
    samplerDescriptor.tAddressMode = .clampToEdge
    guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
      throw MotionError("Cannot allocate DFG sampler")
    }
    lutSampler = sampler
  }

  /// Canvas pixel size for a CSS size at the render's device pixel ratio, like R3F + WebGLRenderer.
  public static func pixelSize(_ scene: Scene3D, devicePixelRatio: Double) -> Scene3DPixelSize {
    let dpr = min(max(devicePixelRatio, scene.dpr[0]), scene.dpr[1])
    return Scene3DPixelSize(width: max(1, Int((scene.width * dpr).rounded(.down))),
      height: max(1, Int((scene.height * dpr).rounded(.down))), dpr: dpr)
  }

  public func render(_ scene: Scene3D, devicePixelRatio: Double) throws -> Scene3DImage {
    let size = Self.pixelSize(scene, devicePixelRatio: devicePixelRatio)
    guard size.width <= 16384, size.height <= 16384 else { throw MotionError("ThreeCanvas is too large") }
    let targets = try target(width: size.width, height: size.height)
    var resolved = try SceneFrame3D(scene, mesh: mesh, model: model)
    let view = resolved.view
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = sampleCount > 1 ? targets.color : targets.resolve
    pass.colorAttachments[0].resolveTexture = sampleCount > 1 ? targets.resolve : nil
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = sampleCount > 1 ? .multisampleResolve : .store
    if let background = scene.background {
      let srgb = background.map(Math3D.linearToSRGB)
      pass.colorAttachments[0].clearColor = MTLClearColor(red: srgb[0], green: srgb[1], blue: srgb[2], alpha: 1)
    } else {
      pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    }
    pass.depthAttachment.texture = targets.depth
    pass.depthAttachment.loadAction = .clear
    pass.depthAttachment.storeAction = .dontCare
    pass.depthAttachment.clearDepth = 1
    guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
    else { throw MotionError("Cannot encode 3D render pass") }
    encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(size.width), height: Double(size.height),
      znear: 0, zfar: 1))
    encoder.setVertexBytes(&resolved.frame, length: MemoryLayout<FrameUniforms>.stride, index: 3)
    encoder.setFragmentBytes(&resolved.frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
    func lights<T>(_ values: [T], index: Int) {
      if values.isEmpty {
        // Metal validates space for one element of each shader pointer even when its
        // light count is zero. A fixed 16-byte placeholder is smaller than every light struct.
        let empty = [UInt8](repeating: 0, count: MemoryLayout<T>.stride)
        empty.withUnsafeBytes { bytes in
          encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: index)
        }
      } else {
        values.withUnsafeBytes { bytes in
          encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: index)
        }
      }
    }
    lights(resolved.points, index: 2)
    lights(resolved.spots, index: 3)
    lights(resolved.directionals, index: 4)
    lights(resolved.hemispheres, index: 5)
    encoder.setFragmentTexture(lut, index: 0)
    encoder.setFragmentSamplerState(lutSampler, index: 0)
    for item in resolved.opaque { draw(item, side: item.material.side, view: view, encoder: encoder, blending: false) }
    for item in resolved.transparent {
      if item.material.side == 2 {
        draw(item, side: 1, view: view, encoder: encoder, blending: true)
        draw(item, side: 0, view: view, encoder: encoder, blending: true)
      } else {
        draw(item, side: item.material.side, view: view, encoder: encoder, blending: true)
      }
    }
    encoder.endEncoding()
    // Copy the resolved frame into a linear shared buffer on the GPU. Reading a (losslessly
    // compressed) texture with getBytes serializes every worker on a driver queue.
    let row = size.width * 4
    let readback = try readbackBuffer(length: row * size.height)
    guard let blit = commands.makeBlitCommandEncoder() else { throw MotionError("Cannot encode 3D readback") }
    blit.copy(from: targets.resolve, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
      sourceSize: MTLSize(width: size.width, height: size.height, depth: 1), to: readback, destinationOffset: 0,
      destinationBytesPerRow: row, destinationBytesPerImage: row * size.height)
    blit.endEncoding()
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw MotionError("3D render failed: \(error.localizedDescription)") }
    var pixels = Data(count: row * size.height)
    let source = readback.contents()
    pixels.withUnsafeMutableBytes { bytes in
      // Bottom-up GL rows: copy them in reverse to get a top-down image.
      for y in 0..<size.height {
        (bytes.baseAddress! + (size.height - 1 - y) * row).copyMemory(from: source + y * row, byteCount: row)
      }
    }
    return Scene3DImage(pixels: pixels, width: size.width, height: size.height)
  }

  private func draw(_ item: RenderItem3D, side: Int, view: M4, encoder: any MTLRenderCommandEncoder,
                    blending: Bool) {
    let material = item.material
    let modelView = view * item.world
    var uniforms = ObjectUniforms()
    uniforms.modelView = modelView.float
    uniforms.normalMatrix = modelView.normalMatrix
    uniforms.diffuse = Math3D.vector(material.color)
    uniforms.opacity = Float(material.opacity)
    uniforms.emissive = Math3D.vector(material.emissive.map { $0 * material.emissiveIntensity })
    uniforms.roughness = Float(material.roughness)
    uniforms.metalness = Float(material.metalness)
    uniforms.specular = Math3D.vector(material.specular)
    uniforms.shininess = Float(max(material.shininess, 1e-4))
    if material.type == "physical" {
      let ior = Float(material.ior), reflectance = (ior - 1) / (ior + 1)
      uniforms.specularColor = SIMD3(repeating: min(reflectance * reflectance, 1))
    }
    uniforms.material = ["basic": 0, "lambert": 1, "phong": 2, "standard": 3, "physical": 3, "normal": 5][material.type] ?? 0
    uniforms.flatShading = material.flatShading ? 1 : 0
    uniforms.doubleSided = side == 2 ? 1 : 0
    uniforms.flipSided = side == 1 ? 1 : 0
    uniforms.opaque = material.transparent ? 0 : 1
    uniforms.toneMapped = material.toneMapped ? 1 : 0
    uniforms.fog = material.fog ? 1 : 0
    // WebGLRenderer: cull back faces unless double sided; BackSide and mirrored transforms swap the winding.
    var flip = side == 1
    if item.world.determinant < 0 { flip.toggle() }
    encoder.setCullMode(side == 2 ? .none : .back)
    // The vertical flip (see the vertex shader) mirrors window-space winding.
    encoder.setFrontFacing(flip ? .counterClockwise : .clockwise)
    encoder.setRenderPipelineState(blending ? blendPipeline : opaquePipeline)
    encoder.setDepthStencilState(depthState(test: material.depthTest, write: material.depthWrite))
    encoder.setVertexBuffer(item.mesh.positions, offset: 0, index: 0)
    encoder.setVertexBuffer(item.mesh.normals, offset: 0, index: 1)
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ObjectUniforms>.stride, index: 0)
    if let indices = item.mesh.indices {
      encoder.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.count, indexType: .uint32,
        indexBuffer: indices, indexBufferOffset: 0)
    } else {
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: item.mesh.count)
    }
  }

  private func depthState(test: Bool, write: Bool) -> any MTLDepthStencilState {
    let key = (test ? 1 : 0) | (write ? 2 : 0)
    if let state = depthStates[key] { return state }
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = test ? .lessEqual : .always
    descriptor.isDepthWriteEnabled = write
    let state = device.makeDepthStencilState(descriptor: descriptor)!
    depthStates[key] = state
    return state
  }

  private func mesh(_ geometry: Scene3D.Geometry) throws -> GPUMesh {
    if let mesh = meshes[geometry] { return mesh }
    // Geometries animated through their arguments would grow the cache without bound.
    if meshes.count > 512 { meshes.removeAll() }
    let mesh = try GPUMesh(GeometryFactory.make(geometry), device: device)
    meshes[geometry] = mesh
    return mesh
  }

  private func model(_ src: String) throws -> [ModelPart3D] {
    if let model = models[src] { return model }
    let parts = try USDModelLoader.load(src).map { part in
      ModelPart3D(mesh: try GPUMesh(part.mesh, device: device), matrix: part.matrix, material: part.material)
    }
    models[src] = parts
    return parts
  }

  private func readbackBuffer(length: Int) throws -> any MTLBuffer {
    if let readback, readback.length == length { return readback }
    guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
      throw MotionError("Cannot allocate 3D readback buffer")
    }
    readback = buffer
    return buffer
  }

  private func target(width: Int, height: Int) throws -> RenderTargets {
    if let targets, targets.resolve.width == width, targets.resolve.height == height { return targets }
    func texture(_ format: MTLPixelFormat, samples: Int, storage: MTLStorageMode) throws -> any MTLTexture {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height,
        mipmapped: false)
      descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
      descriptor.sampleCount = samples
      descriptor.usage = .renderTarget
      descriptor.storageMode = storage
      guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw MotionError("Cannot allocate \(width)x\(height) 3D render target")
      }
      return texture
    }
    let created = RenderTargets(color: try texture(.rgba8Unorm, samples: sampleCount, storage: .private),
      depth: try texture(.depth32Float, samples: sampleCount, storage: .private),
      resolve: try texture(.rgba8Unorm, samples: 1, storage: .private))
    targets = created
    return created
  }
}

private struct RenderTargets {
  let color: any MTLTexture
  let depth: any MTLTexture
  let resolve: any MTLTexture
}

/// Compiled shader libraries are shared per device; compiling MSL takes tens of milliseconds.
private final class LibraryCache: @unchecked Sendable {
  private let lock = NSLock()
  private var libraries: [UInt64: any MTLLibrary] = [:]

  func library(for device: any MTLDevice) throws -> any MTLLibrary {
    try lock.withLock {
      if let library = libraries[device.registryID] { return library }
      let options = MTLCompileOptions()
      // Keep projected vertices identical across pipeline variants and render passes.
      // Safe arithmetic alone does not request Metal's vertex-position invariance.
      options.preserveInvariance = true
      // Preserve floating-point edge cases across repeated exports and GPU driver implementations.
      if #available(macOS 15, iOS 18, *) {
        options.mathMode = .safe
        options.mathFloatingPointFunctions = .precise
      } else {
        options.fastMathEnabled = false
      }
      let library = try device.makeLibrary(source: scene3DShaderSource, options: options)
      libraries[device.registryID] = library
      return library
    }
  }
}
