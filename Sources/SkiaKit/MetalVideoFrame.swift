import CoreVideo
import Foundation
import Metal
import MotionCore

/// Immutable after GPU completion. Retains the IOSurface and its Metal wrapper until
/// the ordered consumer and encoder release it; buffers are never reused while in flight.
public final class MetalVideoFrame: @unchecked Sendable {
  public let pixelBuffer: CVPixelBuffer
  private(set) var texture: CVMetalTexture?
  // CoreVideo may return a texture after its worker has exited. Keep its parent
  // cache alive until after the wrapper is finalized on the consumer thread.
  private let cache: CVMetalTextureCache

  init(pixelBuffer: CVPixelBuffer, texture: CVMetalTexture, cache: CVMetalTextureCache) {
    self.pixelBuffer = pixelBuffer
    self.texture = texture
    self.cache = cache
  }

  deinit {
    // Do not rely on stored-property destruction order for the CoreVideo parent.
    withExtendedLifetime(cache) { texture = nil }
  }
}

/// Confined to the Canvas worker thread, including its texture cache and buffer pool.
final class MetalVideoPool {
  private let pool: CVPixelBufferPool
  private let cache: CVMetalTextureCache
  private let width: Int
  private let height: Int

  init(device: any MTLDevice, width: Int, height: Int) throws {
    self.width = width
    self.height = height
    let attributes: [String: Any] = [
      kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]
    var pool: CVPixelBufferPool?
    guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess,
      let pool
    else { throw MotionError("Cannot create IOSurface video pool") }
    self.pool = pool
    var cache: CVMetalTextureCache?
    guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache
    else { throw MotionError("Cannot create Metal video texture cache") }
    self.cache = cache
  }

  func allocate() throws -> MetalVideoFrame {
    // Release unused cached wrappers so their IOSurfaces can return to the pool.
    // Frames still held by the pipeline/encoder remain retained and cannot be reused.
    CVMetalTextureCacheFlush(cache, 0)
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer
    else { throw MotionError("Cannot allocate IOSurface video frame") }
    CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, .shouldPropagate)
    var texture: CVMetalTexture?
    let attributes = [kCVMetalTextureUsage as String: MTLTextureUsage.renderTarget.rawValue | MTLTextureUsage.shaderRead.rawValue]
    guard CVMetalTextureCacheCreateTextureFromImage(
      nil, cache, buffer, attributes as CFDictionary, .bgra8Unorm, width, height, 0, &texture
    ) == kCVReturnSuccess, let texture
    else { throw MotionError("Cannot wrap IOSurface as Metal texture") }
    return MetalVideoFrame(pixelBuffer: buffer, texture: texture, cache: cache)
  }
}
