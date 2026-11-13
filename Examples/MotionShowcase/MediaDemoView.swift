import MotionCore
import MotionSwiftUI
import SwiftUI

/// A master composition with navigable montage, image and video compositions.
struct MediaDemoView: View {
  @State private var player = MotionPlayer(configuration: .init(scale: 1, backend: .gpu))
  @State private var navigation = MediaCompositionNavigation()

  var body: some View {
    VStack(spacing: 16) {
      breadcrumbs
      MotionView(player: player)
        .overlay { clipTargets }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      MotionTransportBar(player: player)
      MediaDemoTimeline(player: player, open: open)
    }
    .padding(20)
    .navigationTitle(player.composition?.id ?? "Master Composition")
    .navigationSubtitle("Double-click a composition in the preview or timeline to open it")
    .toolbar {
      Button("Export Composition", systemImage: "square.and.arrow.up") {
        player.pause()
        showsExport = true
      }
      .disabled(player.bundle == nil)
    }
    .sheet(isPresented: $showsExport) {
      if let bundle = player.bundle, let composition = player.composition {
        FilmExportSheet(bundle: bundle, composition: composition)
      }
    }
    .task {
      do {
        await player.load(try MediaDemo.source(), compositionID: MediaDemo.rootCompositionID)
      } catch { self.error = String(describing: error) }
    }
    .onDisappear { player.pause() }
    .overlay {
      if let error {
        Label(error, systemImage: "exclamationmark.triangle")
          .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      }
    }
  }

  private func open(_ clip: DemoCompositionClip) { navigation.open(clip, player: player) }

  private var breadcrumbs: some View {
    HStack(spacing: 8) {
      if !navigation.parents.isEmpty {
        Button {
          navigation.back(to: navigation.parents.count - 1, player: player)
        } label: { Image(systemName: "chevron.left") }
        .help("Back to parent composition")
        .accessibilityLabel("Back to parent composition")
      }
      ForEach(navigation.parents.indices, id: \.self) { index in
        Button(navigation.parents[index].compositionID) { navigation.back(to: index, player: player) }
        Image(systemName: "chevron.right").foregroundStyle(.secondary)
      }
      Text(player.composition?.id ?? "MasterComposition").fontWeight(.semibold)
      Spacer()
    }
    .buttonStyle(.borderless)
    .font(.callout)
  }

  @ViewBuilder private var clipTargets: some View {
    if let composition = player.composition {
      GeometryReader { geometry in
        let scale = geometry.size.width / Double(composition.width)
        ForEach(MediaDemo.clips[composition.id] ?? []) { clip in
          if let bounds = clip.bounds, clip.contains(frame: player.displayedFrame?.frame ?? player.currentFrame),
             clip.compositionID != nil {
            NestedCompositionTarget(title: clip.title) { open(clip) }
              .frame(width: bounds.width * scale, height: bounds.height * scale)
              .position(x: bounds.rect.midX * scale, y: bounds.rect.midY * scale)
          }
        }
      }
    }
  }

  @State private var showsExport = false
  @State private var error: String?
}

enum MediaDemo {
  static func asset(_ name: String, extension ext: String) throws -> URL {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Media") else {
      throw MotionError("Missing media demo asset: \(name).\(ext)")
    }
    return url
  }

  static func source() throws -> MotionSource {
    var code = try String(contentsOf: asset("Demo", extension: "tsx"), encoding: .utf8)
    for (token, name, ext) in [("__VIDEO__", "motion", "mp4"), ("__IMAGE__", "poster", "png"),
                               ("__AUDIO__", "music", "m4a")] {
      let url = try asset(name, extension: ext)
      let literal = String(bytes: try JSONEncoder().encode(url.absoluteString), encoding: .utf8)!
      code = code.replacingOccurrences(of: token, with: literal)
    }
    let layers = String(bytes: try JSONEncoder().encode(clips), encoding: .utf8)!
    code = code.replacingOccurrences(of: "__LAYERS__", with: layers)
    return .files(["index.tsx": code], entry: "index.tsx")
  }
}

private struct NestedCompositionTarget: View {
  let title: String
  let open: () -> Void
  @State private var hovering = false

  var body: some View {
    Rectangle().fill(.clear)
      .overlay { if hovering { Rectangle().stroke(.cyan, lineWidth: 2) } }
      .contentShape(Rectangle())
      .onHover { hovering = $0 }
      .onTapGesture(count: 2, perform: open)
      .help("Double-click to open \(title)")
      .accessibilityLabel("\(title), nested composition")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { open() }
  }
}
