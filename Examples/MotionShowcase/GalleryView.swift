import MotionSwiftUI
import SwiftUI

/// Every composition playing at once, each in its own drop-in `MotionCompositionView`. Tiles reuse
/// the main player's compiled bundle, so the project is compiled only once.
struct GalleryView: View {
  let player: MotionPlayer
  let settings: ShowcaseSettings
  let open: (SidebarItem) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        MotionStudiesView { open(.study($0)) }
        Divider().padding(.vertical, 12)
        Text("Explore the toolkit").font(.title2.bold())
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], spacing: 20) {
          destination("Maps", subtitle: "Yamanote full loop · SFO Airport cameras and markers",
                      icon: "map", color: .green, item: .maps)
          destination("Media Composition", subtitle: "Nested clips, audio, video and timeline",
                      icon: "rectangle.stack.fill", color: .teal, item: .media)
          destination("3D Scenes", subtitle: "three.js scenes, keyframed cameras, lights and USDZ",
                      icon: "cube.transparent", color: .indigo, item: .scenes3D)
          destination("Test Film", subtitle: "90-second benchmark film and export",
                      icon: "film", color: .blue, item: .testFilm)
          destination("Visual Editor", subtitle: "Canvas, inspector, timeline and keyframes",
                      icon: "cursorarrow.motionlines", color: .purple, item: .editor)
        }
        Text("Rendering essentials").font(.title2.bold())
        if let source = player.compiledSource {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], spacing: 20) {
            ForEach(player.compositions, id: \.id) { composition in
              Button { open(.composition(composition.id)) } label: {
                VStack(alignment: .leading, spacing: 8) {
                  StableTile {
                    MotionCompositionView(
                      source: source, compositionID: composition.id,
                      configuration: settings.render)
                      .id("\(settings.render.backend.rawValue)-\(settings.render.scale)")
                  }
                  .clipShape(RoundedRectangle(cornerRadius: 10))
                  Text(composition.id).font(.headline)
                  Text(composition.summary).font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .help("Open \(composition.id) to preview or edit its timeline")
            }
          }
        } else {
          // Project failures still leave the built-in showcase destinations available.
          MotionView(player: player)
        }
      }
      .padding(20)
    }
  }

  private func destination(_ title: String, subtitle: String, icon: String, color: Color,
                           item: SidebarItem) -> some View {
    Button { open(item) } label: {
      VStack(alignment: .leading, spacing: 8) {
        RoundedRectangle(cornerRadius: 10)
          .fill(color.gradient)
          .overlay { Image(systemName: icon).font(.system(size: 42)).foregroundStyle(.white) }
          .aspectRatio(16 / 9, contentMode: .fit)
        Text(title).font(.headline)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Open \(title)")
  }
}

/// A fixed 16:9 frame that letterboxes its preview. Previews only learn their composition's aspect
/// ratio after loading, and lazy grid tiles load (and reset) as they scroll into view; without a
/// fixed frame those height changes resize the scroll content mid-scroll and the gallery jumps
/// back to the top before reaching the bottom.
struct StableTile<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    Color.black
      .aspectRatio(16 / 9, contentMode: .fit)
      .overlay { content }
  }
}
