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
  let width = encoder == .software ? 64 : 320
  let height = encoder == .software ? 64 : 180
  let stream = try VideoStream(output: output, width: width, height: height, fps: 24, encoder: encoder)
  let frame = Data((0..<width * height).flatMap { _ in [UInt8(255), 0, 0, 255] })
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
  #expect(video["width"] as? Int == width && video["height"] as? Int == height)
  #expect(video["nb_read_packets"] as? String == "3")
  #expect(video["r_frame_rate"] as? String == "24/1")
  let decoded = try encoderCommand([
    "ffmpeg", "-v", "error", "-i", output.path, "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
  ])
  #expect(decoded.count == width * height * 3 * 3)
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
  let width = 320
  let height = 180
  let renderer = try Renderer(width: width, height: height, backend: .gpu)
  let composition = try JSONDecoder().decode(
    Composition.self,
    from: Data(#"{"id":"test","width":320,"height":180,"fps":24,"durationInFrames":3}"#.utf8))
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
  let stream = try SharedVideoStream(output: output, width: width, height: height, fps: 24)
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
  #expect(decoded.count == width * height * 3 * 3)
  if decoded.count == width * height * 3 * 3 {
    for frame in 0..<3 {
      for channel in 0..<3 {
        let value = decoded[frame * width * height * 3 + channel]
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

@Test func codecCombinationsAndFrameSegmentsAreValidated() throws {
  #expect(throws: MotionError.self) { try EncodingOptions(codec: .h264, pixelFormat: .yuva444p10le) }
  #expect(throws: MotionError.self) { try EncodingOptions(codec: .prores4444, encoder: .videotoolbox) }
  #expect(throws: MotionError.self) { try EncodingOptions(codec: .hevc, quality: .nan) }
  #expect(throws: MotionError.self) { try EncodingOptions(codec: .h264, quality: 52) }
  #expect(throws: MotionError.self) { try FrameSelection.segments("0-3,", duration: 10) }
  #expect(throws: MotionError.self) { try FrameSelection.segments("0-10", duration: 10) }
  #expect(throws: MotionError.self) { try FrameSelection.segments(nil, duration: 10, step: 0) }
  #expect(try FrameSelection.segments("4-8,0-2", duration: 10, step: 2) == [[4, 6, 8], [0, 2]])
}

@Test(arguments: [VideoCodec.hevc, .prores, .prores4444])
func remainingSoftwareCodecsDecodeWithMetadataAndAlpha(codec: VideoCodec) throws {
  let options = try EncodingOptions(codec: codec)
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let output = directory.appendingPathComponent("fixture." + options.fileExtension)
  try VideoStream.checkAvailability(options: options, width: 64, height: 64, fps: 12)
  let stream = try VideoStream(output: output, width: 64, height: 64, fps: 12, options: options)
  do {
    for alpha: UInt8 in [0, 128, 255] {
      try stream.write(Data((0..<64 * 64).flatMap { _ in [UInt8(255), 0, 0, alpha] }))
    }
    try stream.finish()
  } catch { stream.cancel(); throw error }
  let metadata = try encoderCommand(["ffprobe", "-v", "error", "-count_frames", "-show_entries",
    "stream=codec_name,pix_fmt,width,height,nb_read_frames,r_frame_rate", "-of", "json", output.path])
  let json = try #require(try JSONSerialization.jsonObject(with: metadata) as? [String: Any])
  let video = try #require((json["streams"] as? [[String: Any]])?.first)
  #expect(video["codec_name"] as? String == (codec == .hevc ? "hevc" : "prores"))
  #expect(video["nb_read_frames"] as? String == "3")
  #expect(video["width"] as? Int == 64 && video["height"] as? Int == 64)
  #expect(video["r_frame_rate"] as? String == "12/1")
  let decoded = try encoderCommand(["ffmpeg", "-v", "error", "-i", output.path,
    "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"])
  #expect(decoded.count == 64 * 64 * 4 * 3)
  if decoded.count == 64 * 64 * 4 * 3 {
    for frame in 0..<3 {
      let offset = frame * 64 * 64 * 4
      #expect(decoded[offset] > 240 && decoded[offset + 1] < 15)
      if codec == .prores4444 {
        #expect(abs(Int(decoded[offset + 3]) - [0, 128, 255][frame]) <= 2)
      } else { #expect(decoded[offset + 3] == 255) }
    }
  }
}

@Test func segmentConcatenationPreservesBoundaryFramesAndCleansScratch() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let output = directory.appendingPathComponent("ordered.mp4")
  var scratch: URL!
  do {
    let transaction = try SegmentOutput(output: output)
    scratch = transaction.directory
    for segment in 0..<2 {
      let stream = try VideoStream(output: transaction.segment(segment), width: 64, height: 64, fps: 12)
      for channel in (segment * 2)..<(segment * 2 + 2) {
        let rgb: [UInt8] = [channel == 0 ? 255 : 0, channel == 1 ? 255 : 0, channel >= 2 ? 255 : 0, 255]
        try stream.write(Data((0..<64 * 64).flatMap { _ in rgb }))
      }
      try stream.finish()
    }
    try transaction.publish(count: 2)
  }
  #expect(!FileManager.default.fileExists(atPath: scratch.path))
  let decoded = try encoderCommand(["ffmpeg", "-v", "error", "-i", output.path, "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"])
  #expect(decoded.count == 64 * 64 * 3 * 4)
  if decoded.count == 64 * 64 * 3 * 4 {
    #expect(decoded[0] > 240)
    #expect(decoded[64 * 64 * 3 + 1] > 240)
    #expect(decoded[64 * 64 * 3 * 2 + 2] > 240)
  }
  let original = try Data(contentsOf: output)
  do {
    let transaction = try SegmentOutput(output: output)
    scratch = transaction.directory
    #expect(throws: MotionError.self) { try transaction.publish(count: 2, cancelled: { true }) }
  }
  #expect(!FileManager.default.fileExists(atPath: scratch.path))
  #expect(try Data(contentsOf: output) == original)
  do {
    let transaction = try SegmentOutput(output: output)
    scratch = transaction.directory
    #expect(throws: MotionError.self) { try transaction.publish(count: 2) }
  }
  #expect(!FileManager.default.fileExists(atPath: scratch.path))
  #expect(try Data(contentsOf: output) == original)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MOTIONSWIFT_TEST_HARDWARE"] == "1"))
func hevcHardwareProducesDecodableVideo() throws {
  let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
  defer { try? FileManager.default.removeItem(at: output) }
  let options = try EncodingOptions(codec: .hevc, encoder: .videotoolbox)
  try VideoStream.checkAvailability(options: options, width: 320, height: 180, fps: 24)
  let stream = try VideoStream(output: output, width: 320, height: 180, fps: 24, options: options)
  do {
    for _ in 0..<3 { try stream.write(Data(repeating: 255, count: 320 * 180 * 4)) }
    try stream.finish()
  } catch { stream.cancel(); throw error }
  let decoded = try encoderCommand(["ffmpeg", "-v", "error", "-i", output.path, "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"])
  #expect(decoded.count == 320 * 180 * 3 * 3)
}
