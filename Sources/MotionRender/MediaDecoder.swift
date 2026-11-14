import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import MotionCore

/// Worker-confined decoders. Raster images have a bounded cache; videos retain only generators.
final class MediaDecoder {
  private let images = NSCache<NSString, RasterImage>()
  private var videos: [String: AVAssetImageGenerator] = [:]

  init() { images.totalCostLimit = 64 << 20 }

  func image(_ source: String, time: Double? = nil) throws -> RasterImage? {
    if let time {
      guard time.isFinite, time >= 0 else { throw MotionError("Invalid video time") }
      let generator: AVAssetImageGenerator
      if let existing = videos[source] { generator = existing } else {
        // Keep decoder resources bounded when a composition uses many different clips.
        if videos.count >= 16 { videos.removeAll() }
        generator = AVAssetImageGenerator(asset: AVURLAsset(url: try MediaSource.url(source)))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        videos[source] = generator
      }
      do {
        let image = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 60000), actualTime: nil)
        return try RasterImage(image)
      } catch {
        // Past the source duration the clip is silent/transparent. Decode failures within it fail.
        let duration = generator.asset.duration.seconds
        if duration.isFinite, time >= duration { return nil }
        throw MotionError("Cannot decode video \(source) at \(time)s: \(error)")
      }
    }
    if let image = images.object(forKey: source as NSString) { return image }
    let data: Data
    if source.hasPrefix("data:") { data = try MediaSource.data(source) } else if source.hasPrefix("motionmap:") {
      // @motionswift/map tiles: disk cached provider rasters or MapKit snapshots.
      guard let tile = try MapServices.tileDataForRendering(source) else { return nil }
      data = tile
    } else {
      let url = try MediaSource.url(source)
      guard url.isFileURL else { throw MotionError("Stage remote images locally before rendering") }
      data = try Data(contentsOf: url)
    }
    guard let decoder = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(decoder, 0, nil)
    else { throw MotionError("Cannot decode image: \(source.prefix(160))") }
    let result = try RasterImage(image)
    images.setObject(result, forKey: source as NSString, cost: result.pixels.count)
    return result
  }
}

final class RasterImage {
  let width: Int
  let height: Int
  let pixels: Data

  init(_ image: CGImage) throws {
    let width = image.width
    let height = image.height
    self.width = width
    self.height = height
    guard width > 0, height > 0, width <= 16384, height <= 16384 else {
      throw MotionError("Invalid media dimensions")
    }
    var data = Data(count: width * height * 4)
    let rendered = data.withUnsafeMutableBytes { bytes -> Bool in
      guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard rendered else { throw MotionError("Cannot convert media pixels") }
    pixels = data
  }
}
