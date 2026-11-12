import MotionSwiftUI
import SwiftUI

/// Every composition playing at once, each in its own drop-in `MotionCompositionView`. Tiles reuse
/// the main player's compiled bundle, so the project is compiled only once.
struct GalleryView: View {
  let player: MotionPlayer
  let settings: ShowcaseSettings
  let open: (String) -> Void

  var body: some View {
    if let bundle = player.bundle {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], spacing: 20) {
          ForEach(player.compositions, id: \.id) { composition in
            Button { open(composition.id) } label: {
              VStack(alignment: .leading, spacing: 8) {
                MotionCompositionView(
                  source: .bundle(bundle), compositionID: composition.id,
                  configuration: settings.render)
                  .id("\(settings.render.backend.rawValue)-\(settings.render.scale)")
                  .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(composition.id).font(.headline)
                Text(composition.summary).font(.caption).foregroundStyle(.secondary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(composition.id) with transport controls")
          }
        }
        .padding(20)
      }
    } else {
      // Loading and load failures are reported by the player's own overlays.
      MotionView(player: player).padding(20)
    }
  }
}
