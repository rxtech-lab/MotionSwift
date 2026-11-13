import MotionCore
import MotionSwiftUI
import Observation
import SwiftUI

/// One definition drives TSX clip placement, timeline rows, and canvas hit targets.
struct DemoCompositionClip: Codable, Identifiable {
  struct Bounds: Codable {
    let left: Double
    let top: Double
    let width: Double
    let height: Double
    var rect: CGRect { CGRect(x: left, y: top, width: width, height: height) }
  }
  let id: String
  let title: String
  let compositionID: String?
  let start: Int
  let duration: Int
  let bounds: Bounds?

  func contains(frame: Int) -> Bool { (start..<(start + duration)).contains(frame) }
  var color: Color {
    switch compositionID {
    case "ImageClip": .teal
    case "VideoClip": .blue
    case .some: .purple
    case nil: .orange
    }
  }
}

extension MediaDemo {
  static let rootCompositionID = "MasterComposition"
  static let clips: [String: [DemoCompositionClip]] = [
    "MasterComposition": [
      .init(id: "montage-a", title: "Media Montage · A", compositionID: "MediaMontage", start: 0, duration: 360,
            bounds: .init(left: 32, top: 90, width: 960, height: 540)),
      .init(id: "montage-b", title: "Media Montage · B", compositionID: "MediaMontage", start: 360, duration: 360,
            bounds: .init(left: 32, top: 90, width: 960, height: 540)),
      .init(id: "image", title: "Image Composition", compositionID: "ImageClip", start: 0, duration: 150,
            bounds: .init(left: 1024, top: 90, width: 224, height: 180)),
      .init(id: "video", title: "Video Composition", compositionID: "VideoClip", start: 150, duration: 150,
            bounds: .init(left: 1024, top: 300, width: 224, height: 180)),
    ],
    "MediaMontage": [
      .init(id: "image", title: "Image Composition", compositionID: "ImageClip", start: 0, duration: 150,
            bounds: .init(left: 48, top: 100, width: 416, height: 300)),
      .init(id: "inset", title: "Video Inset", compositionID: "VideoClip", start: 90, duration: 150,
            bounds: .init(left: 496, top: 100, width: 416, height: 300)),
      .init(id: "finale", title: "Video Finale", compositionID: "VideoClip", start: 240, duration: 120,
            bounds: .init(left: 48, top: 80, width: 864, height: 400)),
      .init(id: "music", title: "Music", compositionID: nil, start: 0, duration: 360, bounds: nil),
    ],
    "ImageClip": [.init(id: "image", title: "Image", compositionID: nil, start: 0, duration: 150, bounds: nil)],
    "VideoClip": [.init(id: "video", title: "Video & Audio", compositionID: nil, start: 0, duration: 150, bounds: nil)],
  ]
}

/// Retains each parent playhead and maps an instance's parent frame into its child-local frame.
@MainActor @Observable
final class MediaCompositionNavigation {
  struct Visit: Equatable {
    let compositionID: String
    let frame: Int
  }
  private(set) var parents: [Visit] = []

  func open(_ clip: DemoCompositionClip, player: MotionPlayer) {
    guard let parent = player.composition, let id = clip.compositionID,
      let child = player.compositions.first(where: { $0.id == id }), child.id != parent.id else { return }
    player.pause()
    parents.append(Visit(compositionID: parent.id, frame: player.currentFrame))
    let local = min(max(player.currentFrame - clip.start, 0), min(clip.duration, child.durationInFrames) - 1)
    player.select(compositionID: id)
    player.seek(to: local)
  }

  func back(to index: Int, player: MotionPlayer) {
    guard parents.indices.contains(index) else { return }
    let visit = parents[index]
    parents.removeSubrange(index...)
    player.select(compositionID: visit.compositionID)
    player.seek(to: visit.frame)
  }
}
