import CoreGraphics
import Foundation
import ImageIO
import MotionCore
import MotionRender
import MotionRuntime
import MotionSwiftUI
import Testing
import UniformTypeIdentifiers

private func solidPNG(red: UInt8, green: UInt8, blue: UInt8) throws -> String {
  let bytes = Data([red, green, blue, 255])
  let provider = try #require(CGDataProvider(data: bytes as CFData))
  let image = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
    bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
    decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  let encoded = NSMutableData()
  let encoder = try #require(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(encoder, image, nil)
  #expect(CGImageDestinationFinalize(encoder))
  return "data:image/png;base64," + (encoded as Data).base64EncodedString()
}

private func solidImage(width: Int, height: Int, rgba: [UInt8]) -> CGImage? {
  let bytes = Data((0..<(width * height)).flatMap { _ in rgba })
  guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
  return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
    decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

@Test @MainActor
func reversedMediaReadsTheTrimmedRangeBackwards() async throws {
  let code = """
    import React from 'react';
    import {AbsoluteFill, Audio, Composition, registerRoot} from 'remotion';
    const Film = () => <AbsoluteFill>
      <Audio src="/tmp/reverse.wav" trimBefore={30} durationInFrames={30} reverse />
    </AbsoluteFill>;
    registerRoot(() => <Composition id="Reverse" component={Film} width={16} height={16} fps={30} durationInFrames={40} />);
    """
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(.files(["index.tsx": code], entry: "index.tsx"))
  let bundle = try #require(player.bundle)
  let composition = try #require(player.composition)
  let runtime = try Runtime(bundle: bundle)
  func voice(_ frame: Int) throws -> ActiveMedia? {
    try runtime.frame(composition: composition, number: frame).activeMedia.first
  }
  #expect(abs(try #require(try voice(0)).sample.time - 59.0 / 30) < 0.000001)
  #expect(abs(try #require(try voice(29)).sample.time - 30.0 / 30) < 0.000001)
  #expect(try voice(30) == nil)
}

@Test @MainActor
func staticFileRootResolvesNestedProjectAssets() async throws {
  let code = """
    import React from 'react';
    import {AbsoluteFill, Audio, Composition, StaticFileRoot, registerRoot, staticFile} from 'remotion';
    const Nested = () => <Audio src={staticFile('sound/track.wav')} />;
    const Film = () => <AbsoluteFill>
      <StaticFileRoot root="/Projects/A/public/"><Nested /></StaticFileRoot>
      <Audio src={staticFile('own.wav')} />
    </AbsoluteFill>;
    registerRoot(() => <Composition id="Roots" component={Film} width={16} height={16} fps={30} durationInFrames={1} />);
    """
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(.files(["index.tsx": code], entry: "index.tsx"))
  let runtime = try Runtime(bundle: try #require(player.bundle))
  let sources = Set(try runtime.frame(composition: try #require(player.composition), number: 0).activeMedia.map(\.src))
  #expect(sources == ["/Projects/A/public/sound/track.wav", "static:own.wav"])
}

@Test @MainActor
func imgProcessKeyCarriesTheLocalTime() async throws {
  let code = """
    import React from 'react';
    import {AbsoluteFill, Composition, Img, Sequence, registerRoot} from 'remotion';
    const Film = () => <AbsoluteFill>
      <Sequence from={10}><Img src="/tmp/still.png" process="caption-1" style={{width: 16, height: 16}} /></Sequence>
    </AbsoluteFill>;
    registerRoot(() => <Composition id="Process" component={Film} width={16} height={16} fps={10} durationInFrames={30} />);
    """
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(.files(["index.tsx": code], entry: "index.tsx"))
  let runtime = try Runtime(bundle: try #require(player.bundle))
  let tree = try runtime.frame(composition: try #require(player.composition), number: 15)
  func find(_ node: RenderNode) -> RenderNode? {
    if node.type == "img" { return node }
    return node.children.lazy.compactMap(find).first
  }
  let image = try #require(find(tree))
  #expect(image.media?.process == "caption-1")
  #expect(image.media?.time == 0.5)
  // Processed stills are not audio/video voices.
  #expect(tree.activeMedia.isEmpty)
}

/// One test owns the process-wide processor, so parallel tests never observe each other's.
@Test func hostProcessorReplacesDecodedPixelsAndIsRequired() throws {
  let src = try solidPNG(red: 255, green: 0, blue: 0)
  let composition = try JSONDecoder().decode(Composition.self, from: Data(
    #"{"id":"Host","width":4,"height":4,"fps":30,"durationInFrames":1}"#.utf8))
  let node = RenderNode(type: "div", style: ["width": .number(4), "height": .number(4)], children: [
    RenderNode(type: "img", style: ["objectFit": .string("fill"), "width": .number(4), "height": .number(4)], src: src,
               media: MediaSample(time: 1.25, volume: 0, process: "blue")),
  ])

  MediaProcessing.processor = nil
  #expect(throws: MotionError.self) { try Renderer(width: 4, height: 4).draw(node, composition: composition) }

  let received = LockedRequests()
  MediaProcessing.processor = { image, request in
    received.append(request)
    #expect(image.width == 1)
    return solidImage(width: request.pixelWidth, height: request.pixelHeight, rgba: [0, 0, 255, 255])
  }
  defer { MediaProcessing.processor = nil }
  let renderer = try Renderer(width: 4, height: 4, scale: 2)
  try renderer.draw(node, composition: composition)
  let pixels = try renderer.pixels()
  #expect(pixels[0] == 0 && pixels[2] == 255)
  let request = try #require(received.values.first)
  #expect(request == MediaProcessRequest(key: "blue", time: 1.25, pixelWidth: 8, pixelHeight: 8))
}

private final class LockedRequests: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [MediaProcessRequest] = []
  func append(_ request: MediaProcessRequest) { lock.withLock { items.append(request) } }
  var values: [MediaProcessRequest] { lock.withLock { items } }
}
