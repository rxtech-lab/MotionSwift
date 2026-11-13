import MotionSwiftUI
import SwiftUI

/// Frame mapping shared by the ruler, track scrub gestures and the playhead's grab area.
enum MediaTimelineScrubbing {
  static func frame(at position: Double, width: Double, duration: Int) -> Int {
    guard position.isFinite, width.isFinite, width > 0, duration > 0 else { return 0 }
    let frame = (position / width * Double(duration)).rounded()
    return Int(min(Double(duration - 1), max(0, frame)))
  }
}

struct MediaDemoTimeline: View {
  let player: MotionPlayer
  let open: (DemoCompositionClip) -> Void
  @State private var isScrubbing = false
  @State private var playheadDragFrame: Int?
  private let labelWidth = 156.0
  private let trackSpacing = 12.0
  private var duration: Int { player.composition?.durationInFrames ?? 1 }
  private var fps: Double { player.composition?.fps ?? 30 }
  private var tracks: [DemoCompositionClip] { MediaDemo.clips[player.composition?.id ?? ""] ?? [] }

  var body: some View {
    VStack(spacing: 6) {
      HStack {
        Text("Composition timeline").font(.headline)
        Spacer()
        Text(String(format: "%.2f / %.2f s", Double(player.currentFrame) / fps, Double(duration) / fps))
          .monospacedDigit().foregroundStyle(.secondary)
      }
      VStack(spacing: 6) {
        ruler
        ForEach(tracks) { track in
          HStack(spacing: trackSpacing) {
            Label(track.title, systemImage: track.compositionID == nil ? "waveform" : "rectangle.stack")
              .font(.caption).frame(width: labelWidth, alignment: .leading)
              .onTapGesture(count: 2) { open(track) }
            trackBar(track)
          }
        }
      }
      .overlay(alignment: .topLeading) { playhead }
      .coordinateSpace(name: "mediaCompositionTimeline")
    }
    .onChange(of: player.composition?.id) { _, _ in
      isScrubbing = false
      playheadDragFrame = nil
    }
    .padding(12)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
  }

  private var ruler: some View {
    HStack(spacing: trackSpacing) {
      Text("Time").font(.caption).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .leading)
      GeometryReader { geometry in
        HStack {
          ForEach(0..<5) { index in
            if index > 0 { Spacer(minLength: 0) }
            Text(String(format: "%.1fs", Double(duration * index) / (4 * fps)))
              .font(.caption2).monospacedDigit()
          }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
          .onChanged { value in scrub(value.location.x, width: geometry.size.width) }
          .onEnded { _ in isScrubbing = false })
        .help("Click or drag to move the playhead")
      }
      .frame(height: 22)
    }
  }

  private var playhead: some View {
    GeometryReader { geometry in
      let gutter = labelWidth + trackSpacing
      let width = max(0, geometry.size.width - gutter)
      let position = gutter + Double(player.currentFrame) / Double(duration) * width
      ZStack(alignment: .top) {
        Rectangle().fill(Color.accentColor).frame(width: 2)
          .padding(.top, 8)
        Image(systemName: "arrowtriangle.down.fill")
          .font(.system(size: 14)).foregroundStyle(Color.accentColor)
      }
      .frame(width: 24, height: geometry.size.height)
      .contentShape(Rectangle())
      .overlay(alignment: .top) {
        if isScrubbing {
          Text("Frame \(player.currentFrame)").font(.caption.monospacedDigit())
            .fixedSize().padding(6).background(.regularMaterial, in: Capsule()).offset(y: -30)
        }
      }
      .offset(x: position - 12)
      .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("mediaCompositionTimeline"))
        .onChanged { value in
          let origin = playheadDragFrame ?? player.currentFrame
          playheadDragFrame = origin
          scrub(Double(origin) / Double(duration) * width + value.translation.width, width: width)
        }
        .onEnded { _ in isScrubbing = false; playheadDragFrame = nil })
      .help("Drag the playhead to scrub")
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Timeline playhead")
      .accessibilityValue("Frame \(player.currentFrame) of \(duration - 1)")
      .accessibilityAdjustableAction { direction in player.step(by: direction == .increment ? 1 : -1) }
    }
  }

  private func trackBar(_ track: DemoCompositionClip) -> some View {
    GeometryReader { geometry in
      let unit = geometry.size.width / Double(duration)
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
        RoundedRectangle(cornerRadius: 4).fill(track.color.opacity(0.7))
          .frame(width: Double(track.duration) * unit).offset(x: Double(track.start) * unit)
      }
      .contentShape(Rectangle())
      .gesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture()).onEnded { result in
        switch result {
        case .first(let tap):
          let frame = MediaTimelineScrubbing.frame(at: tap.location.x, width: geometry.size.width, duration: duration)
          if track.compositionID != nil, track.contains(frame: frame) { open(track) }
        case .second(let tap): scrub(tap.location.x, width: geometry.size.width); isScrubbing = false
        }
      })
      .simultaneousGesture(DragGesture(minimumDistance: 3)
        .onChanged { value in scrub(value.location.x, width: geometry.size.width) }
        .onEnded { _ in isScrubbing = false })
      .help("Drag to scrub; double-click a composition to open it")
      .accessibilityElement()
      .accessibilityLabel("\(track.title), frames \(track.start) to \(track.start + track.duration - 1)")
      .accessibilityAdjustableAction { direction in player.step(by: direction == .increment ? 1 : -1) }
      .accessibilityAction(named: Text("Open composition")) { open(track) }
      .contextMenu {
        if track.compositionID != nil {
          Button("Open Composition", systemImage: "rectangle.stack") { open(track) }
        }
      }
    }
    .frame(height: 24)
  }

  private func scrub(_ position: Double, width: Double) {
    player.pause()
    isScrubbing = true
    player.seek(to: MediaTimelineScrubbing.frame(at: position, width: width, duration: duration))
  }
}
