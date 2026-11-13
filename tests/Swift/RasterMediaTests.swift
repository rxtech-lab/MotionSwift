import CoreGraphics
import Foundation
import ImageIO
import MotionCore
import MotionRender
import Testing
import UniformTypeIdentifiers

@Test func rasterMediaFitsAndClipsOnCPUAndMetal() throws {
  // A two-pixel red/blue PNG makes contain/cover/fill and CPU/Metal parity observable.
  let bytes = Data([255, 0, 0, 255, 0, 0, 255, 255])
  let provider = try #require(CGDataProvider(data: bytes as CFData))
  let image = try #require(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
    bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
    decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  let encoded = NSMutableData()
  let encoder = try #require(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(encoder, image, nil)
  #expect(CGImageDestinationFinalize(encoder))
  let src = "data:image/png;base64," + (encoded as Data).base64EncodedString()
  let composition = try JSONDecoder().decode(Composition.self, from: Data(
    #"{"id":"Raster","width":4,"height":4,"fps":30,"durationInFrames":1}"#.utf8))
  for fit in ["contain", "cover", "fill"] {
    let node = RenderNode(type: "img", style: ["objectFit": .string(fit)], src: src)
    let cpu = try Renderer(width: 4, height: 4)
    let metal = try Renderer(width: 4, height: 4, backend: .gpu)
    try cpu.draw(node, composition: composition)
    try metal.draw(node, composition: composition)
    let pixels = try cpu.pixels()
    let gpuPixels = try metal.pixels()
    #expect(pixels == gpuPixels)
    #expect(pixels[3] == (fit == "contain" ? 0 : 255))
    #expect(pixels[(2 * 4) * 4] == 255) // left center remains red
    #expect(pixels[(2 * 4 + 3) * 4 + 2] == 255) // right center remains blue
  }
}
