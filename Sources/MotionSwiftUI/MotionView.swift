import MotionCore
import MotionRender
import SwiftUI

/// Displays a player's current frame, letterboxed to the composition's aspect ratio. Loading and
/// render failures appear as overlays on the canvas.
public struct MotionView: View {
  private let player: MotionPlayer
  private let showsLayoutBounds: Bool

  /// - Parameter showsLayoutBounds: Outlines every layout box of the retained render tree. Boxes
  ///   are Yoga layout rectangles before CSS transforms, the basis for editor hit testing.
  public init(player: MotionPlayer, showsLayoutBounds: Bool = false) {
    self.player = player
    self.showsLayoutBounds = showsLayoutBounds
  }

  public var body: some View {
    let composition = player.composition
    let ratio = composition.map { Double($0.width) / Double($0.height) } ?? 16 / 9
    ZStack {
      Rectangle().fill(.black)
      if let frame = player.displayedFrame {
        Image(decorative: frame.image, scale: 1)
          .resizable()
          .interpolation(.high)
        if showsLayoutBounds, let composition {
          LayoutBoundsOverlay(boxes: frame.layout, composition: composition)
        }
      }
    }
    .aspectRatio(ratio, contentMode: .fit)
    .overlay { StatusOverlay(player: player) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(composition.map { "\($0.id) preview, frame \(player.currentFrame)" } ?? "Preview")
  }
}

/// A preview with transport controls: play/pause, frame stepping, a scrubber and render timing.
public struct MotionPlayerView: View {
  private let player: MotionPlayer
  private let showsLayoutBounds: Bool

  public init(player: MotionPlayer, showsLayoutBounds: Bool = false) {
    self.player = player
    self.showsLayoutBounds = showsLayoutBounds
  }

  public var body: some View {
    VStack(spacing: 12) {
      MotionView(player: player, showsLayoutBounds: showsLayoutBounds)
      MotionTransportBar(player: player)
    }
  }
}

/// A self-contained preview: owns its player, loads `source` and optionally autoplays.
public struct MotionCompositionView: View {
  private let source: MotionSource
  private let compositionID: String?
  private let autoplay: Bool
  private let showsControls: Bool
  @State private var player: MotionPlayer

  public init(
    source: MotionSource, compositionID: String? = nil,
    configuration: MotionPlayer.Configuration = .init(), autoplay: Bool = true,
    showsControls: Bool = false
  ) {
    self.source = source
    self.compositionID = compositionID
    self.autoplay = autoplay
    self.showsControls = showsControls
    _player = State(initialValue: MotionPlayer(configuration: configuration))
  }

  public var body: some View {
    Group {
      if showsControls { MotionPlayerView(player: player) } else { MotionView(player: player) }
    }
    .task(id: TaskKey(source: source, compositionID: compositionID)) {
      await player.load(source, compositionID: compositionID)
      if autoplay { player.play() }
    }
    .onDisappear { player.pause() }
  }

  private struct TaskKey: Equatable {
    let source: MotionSource
    let compositionID: String?
  }
}

/// Play/pause, frame stepping, a scrubber and render timing for a player.
public struct MotionTransportBar: View {
  private let player: MotionPlayer
  @State private var feedback = 0

  public init(player: MotionPlayer) { self.player = player }

  public var body: some View {
    // Narrow layouts (iPhone, iPad split view) move the timing readouts below the scrubber.
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        controls
        scrubber.frame(minWidth: 180)
        position
        rates
      }
      VStack(spacing: 6) {
        HStack(spacing: 12) {
          controls
          scrubber
          position
        }
        HStack(spacing: 12) { rates }.font(.caption)
      }
    }
    .buttonStyle(.borderless)
    .disabled(player.composition == nil)
    .sensoryFeedback(.selection, trigger: feedback)
  }

  private var duration: Int { player.composition?.durationInFrames ?? 1 }

  @ViewBuilder private var controls: some View {
    Button { player.isMuted.toggle(); feedback += 1 } label: {
      Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
    }
    .accessibilityLabel(player.isMuted ? "Unmute audio" : "Mute audio")
    Button { player.step(by: -1); feedback += 1 } label: { Image(systemName: "backward.frame.fill") }
      .help("Previous frame")
      .accessibilityLabel("Previous frame")
    Button { player.togglePlayback(); feedback += 1 } label: {
      Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 16)
    }
    .keyboardShortcut(.space, modifiers: [])
    .help(player.isPlaying ? "Pause" : "Play")
    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    Button { player.step(by: 1); feedback += 1 } label: { Image(systemName: "forward.frame.fill") }
      .help("Next frame")
      .accessibilityLabel("Next frame")
  }

  private var scrubber: some View {
    Slider(
      value: Binding(
        get: { Double(player.currentFrame) },
        set: {
          player.pause()
          player.seek(to: Int($0.rounded()))
          feedback += 1
        }),
      in: 0...Double(max(duration - 1, 1))
    )
    .accessibilityLabel("Playhead")
  }

  private var position: some View {
    Text("\(player.currentFrame) / \(duration - 1)")
      .monospacedDigit()
      .frame(minWidth: 64, alignment: .trailing)
  }

  @ViewBuilder private var rates: some View {
    Text(player.liveFPS.map { String(format: "Live %.1f fps", $0) } ?? "Live — fps")
      .monospacedDigit()
      .foregroundStyle(.secondary)
      .help("Preview-frame deliveries over the last second, including cached frames. Play to measure.")
    Text(player.renderFPS.map { String(format: "Render %.1f fps", $0) } ?? "Render — fps")
      .monospacedDigit()
      .foregroundStyle(.secondary)
      .help("1000 divided by the displayed frame's render time: JS, layout, paint and readback. Excludes playback pacing.")
  }
}

private struct LayoutBoundsOverlay: View {
  let boxes: [LayoutBox]
  let composition: Composition

  var body: some View {
    Canvas { context, size in
      let sx = size.width / Double(composition.width)
      let sy = size.height / Double(composition.height)
      // The root box is the whole canvas; skip it so content boxes stay visible.
      for box in boxes.dropFirst() {
        let rect = CGRect(
          x: box.x * sx, y: box.y * sy, width: box.width * sx, height: box.height * sy)
        context.stroke(
          Path(rect), with: .color(.cyan), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      }
    }
    .allowsHitTesting(false)
  }
}

private struct StatusOverlay: View {
  let player: MotionPlayer

  var body: some View {
    switch player.status {
    case .loading:
      badge { ProgressView().controlSize(.small); Text("Compiling TSX…") }
    case .failed(let message):
      failure(title: "Could not load project", message: message)
    case .idle where player.composition == nil:
      badge { Text("No project loaded").foregroundStyle(.secondary) }
    default:
      if let message = player.renderError {
        failure(title: "Render failed", message: message)
      }
    }
  }

  private func badge(@ViewBuilder _ content: () -> some View) -> some View {
    HStack(spacing: 8, content: content)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(.regularMaterial, in: Capsule())
  }

  private func failure(title: String, message: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: "exclamationmark.triangle.fill")
        .font(.headline)
        .foregroundStyle(.orange)
      ScrollView {
        Text(message)
          .font(.caption.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 120)
    }
    .padding(14)
    .frame(maxWidth: 420)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .padding()
  }
}
