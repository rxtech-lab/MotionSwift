import CoreVideo
import Foundation
import MotionCore
import MotionEncode
import MotionRender
import Testing

private func encoderCommand(_ arguments: [String]) throws -> Data {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = arguments
  let output = Pipe()
  process.standardOutput = output
  try process.run()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)
  return data
}

private func verifyVideo(encoder: VideoEncoder) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let output = directory.appendingPathComponent("video.mp4")
  let stream = try VideoStream(output: output, width: 64, height: 64, fps: 24, encoder: encoder)
  let frame = Data((0..<64 * 64).flatMap { _ in [UInt8(255), 0, 0, 255] })
  do {
    #expect(throws: MotionError.self) { try stream.write(Data([0])) }
    for _ in 0..<3 { try stream.write(frame) }
    try stream.finish()
  } catch {
    stream.cancel()
    throw error
  }
  #expect(stream.framesWritten == 3)
  let metadata = try encoderCommand([
    "ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets",
    "-show_entries", "stream=codec_name,width,height,r_frame_rate,nb_read_packets", "-of", "json", output.path,
  ])
  let json = try #require(try JSONSerialization.jsonObject(with: metadata) as? [String: Any])
  let video = try #require((json["streams"] as? [[String: Any]])?.first)
  #expect(video["codec_name"] as? String == "h264")
  #expect(video["width"] as? Int == 64 && video["height"] as? Int == 64)
  #expect(video["nb_read_packets"] as? String == "3")
  #expect(video["r_frame_rate"] as? String == "24/1")
  let decoded = try encoderCommand([
    "ffmpeg", "-v", "error", "-i", output.path, "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
  ])
  #expect(decoded.count == 64 * 64 * 3 * 3)
  if decoded.count >= 3 {
    #expect(decoded[0] > 240 && decoded[1] < 15 && decoded[2] < 15)
  }
}

@Test func softwareEncoderProducesDecodableVideo() throws {
  try verifyVideo(encoder: .software)
}

// Opt in on a host with an accessible hardware encoder; absence must not count as a pass.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MOTIONSWIFT_TEST_HARDWARE"] == "1"))
func hardwareEncoderProducesDecodableVideo() throws {
  try verifyVideo(encoder: .videotoolbox)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MOTIONSWIFT_TEST_HARDWARE"] == "1"))
func sharedIOSurfaceFramesStayIndependentAndEncodeInOrder() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let output = directory.appendingPathComponent("shared.mp4")
  let renderer = try Renderer(width: 64, height: 64, backend: .gpu)
  let composition = try JSONDecoder().decode(
    Composition.self,
    from: Data(#"{"id":"test","width":64,"height":64,"fps":24,"durationInFrames":3}"#.utf8))
  let frames = try ["#ff0000", "#00ff00", "#0000ff"].map { color in
    try renderer.draw(RenderNode(type: "div", style: ["backgroundColor": .string(color)]), composition: composition)
    return try renderer.videoFrame()
  }
  // Retaining all outputs while the renderer advances must not alias a reused surface.
  for (index, frame) in frames.enumerated() {
    let buffer = frame.pixelBuffer
    #expect(CVPixelBufferGetIOSurface(buffer) != nil)
    #expect(CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess)
    if let bytes = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
      #expect(bytes[2 - index] == 255) // BGRA -> red, green, blue.
    } else { Issue.record("Missing verification pixels") }
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
  }
  let stream = try SharedVideoStream(output: output, width: 64, height: 64, fps: 24)
  do {
    for frame in frames { try stream.write(frame.pixelBuffer) }
    try stream.finish()
  } catch {
    stream.cancel()
    throw error
  }
  let decoded = try encoderCommand([
    "ffmpeg", "-v", "error", "-i", output.path, "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
  ])
  #expect(decoded.count == 64 * 64 * 3 * 3)
  if decoded.count == 64 * 64 * 3 * 3 {
    for frame in 0..<3 {
      for channel in 0..<3 {
        let value = decoded[frame * 64 * 64 * 3 + channel]
        if channel == frame {
          #expect(value > 240, "frame \(frame), channel \(channel)")
        } else {
          #expect(value < 15, "frame \(frame), channel \(channel)")
        }
      }
    }
  }
}

@Test func encoderRejectsInvalidDimensionsBeforeLaunchingFFmpeg() throws {
  #expect(throws: MotionError.self) {
    _ = try VideoStream(output: URL(fileURLWithPath: "/unused.mp4"), width: 63, height: 64, fps: 24)
  }
}
