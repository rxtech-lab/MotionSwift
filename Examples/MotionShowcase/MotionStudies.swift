import MotionCore
import MotionSwiftUI
import SwiftUI

struct MotionStudy: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let category: String
  var example: ShowcaseExample = .project(MotionStudy.project, entry: "index.tsx")
  var compositionID: String { id == "TestFilm" ? "Main" : id }

  static var project: URL { Bundle.module.url(forResource: "Designs", withExtension: nil)! }
  static let designs = [
    MotionStudy(id: "Ribbon", title: "Make it move", subtitle: "Warm ribbons. Bold type. A confident entrance.", category: "01 / BRAND"),
    MotionStudy(id: "Orbit", title: "In good shape", subtitle: "Sculptural forms and an unexpected sense of balance.",
                category: "02 / FORM"),
    MotionStudy(id: "Signal", title: "Find your frequency", subtitle: "Four voices moving together in a pastel rhythm.",
                category: "03 / RHYTHM"),
    MotionStudy(id: "Atlas", title: "The long way home", subtitle: "Explore SFO Airport with an animated map camera.",
                category: "04 / MAPS"),
  ]

  static let maps = [
    MotionStudy(id: "HarbourJourney", title: "Map studio", subtitle: "Edit the SFO camera, provider, routes and airport markers.",
                category: "MAPS / EDITABLE", example: .project(mapStudioProject, entry: "index.tsx")),
    MotionStudy(id: "IslandRailway", title: "Yamanote Line", subtitle: "Zoom into Tokyo and follow the train through all 30 stations.",
                category: "MAPS / RAILWAY", example: .project(railwayProject, entry: "index.tsx")),
    MotionStudy(id: "OpenStreetMapTiles", title: "SFO map tiles",
                subtitle: "OpenStreetMap tiles around San Francisco International Airport.",
                category: "MAPS / TILES", example: .project(mapStudioProject, entry: "index.tsx")),
    MotionStudy(id: "MapKitSnapshot", title: "SFO map snapshot", subtitle: "Apple Maps imagery with an editable airport marker.",
                category: "MAPS / SNAPSHOT", example: .project(mapStudioProject, entry: "index.tsx")),
  ]
  static var railwayProject: URL { Bundle.module.url(forResource: "Railway", withExtension: nil)! }
  static var mapStudioProject: URL { Bundle.module.url(forResource: "MapStudio", withExtension: nil)! }
  static var mapProject: URL { ShowcaseDefaults.repository.appendingPathComponent("tests/maps") }
  static let film = MotionStudy(id: "TestFilm", title: "Test Film", subtitle: "The 90-second benchmark film, ready for your own edit.",
                                category: "FILM / BENCHMARK", example: .film)
  static let all = designs + maps + [film]

  static func study(_ id: String) -> MotionStudy? { all.first { $0.id == id } }
}

struct MotionStudiesView: View {
  let open: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(alignment: .firstTextBaseline) {
        Text("Motion studies").font(.title.bold())
        Spacer()
        Text("\(MotionStudy.all.count) EDITABLE STUDIES").font(.caption.monospaced()).foregroundStyle(.secondary)
      }
      Text("Pick a study. Make it yours.")
        .font(.system(size: 38, weight: .semibold, design: .rounded))
      Text("Open any study in the visual editor to adjust its layers, timing and supported properties. "
           + "Changes apply to this session and reset when you restart the app.")
        .font(.body).foregroundStyle(.secondary).frame(maxWidth: 650, alignment: .leading)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 24)], spacing: 28) {
        ForEach(MotionStudy.all) { study in
          Button { open(study.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
              StableTile { StudyPreview(study: study) }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .allowsHitTesting(false)
              Text(study.category).font(.caption.monospaced()).foregroundStyle(.secondary)
              HStack {
                Text(study.title).font(.title3.bold())
                Spacer()
                Image(systemName: "arrow.up.right")
              }
              Text(study.subtitle).font(.callout).foregroundStyle(.secondary)
              Label("Edit film", systemImage: "timeline.selection").font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
            .padding(14)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 22))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("study-\(study.id)")
        }
      }
    }
  }
}

/// A still from the session working copy keeps a large gallery from playing every film at once.
private struct StudyPreview: View {
  let study: MotionStudy
  @State private var player = MotionPlayer(configuration: .init(scale: 0.5, backend: .gpu))
  @State private var failure: String?

  var body: some View {
    MotionView(player: player)
      .overlay {
        if let failure {
          Label(failure, systemImage: "exclamationmark.triangle")
            .font(.caption).padding().background(.regularMaterial)
        }
      }
      .task {
        do {
          let example = study.example
          let location = try await Task.detached { try example.prepare() }.value
          guard !Task.isCancelled else { return }
          await player.load(.portable(project: location.project, entry: location.entry), compositionID: study.compositionID)
          player.seek(to: min(90, (player.composition?.durationInFrames ?? 1) - 1))
        } catch { failure = String(describing: error) }
      }
      .onDisappear { player.pause() }
  }
}

struct MapsShowcaseView: View {
  @State private var player = MotionPlayer(configuration: .init(scale: 1, backend: .gpu))
  @State private var selectedExample = "IslandRailway"
  @State private var showsMapDetails = false
  static var railwayProject: URL { MotionStudy.railwayProject }
  private var project: URL { selectedExample == "IslandRailway" ? Self.railwayProject : MotionStudy.mapStudioProject }
  private var entry: String { "index.tsx" }

  var body: some View {
    MotionPlayerView(player: player)
      .padding(20)
      .navigationTitle(selectedExample == "IslandRailway" ? "Maps · Yamanote Line" : "Maps · SFO Airport")
      .navigationSubtitle(selectedExample == "IslandRailway"
        ? "Tokyo, Japan · 30 stations · Clockwise full loop"
        : "San Francisco International Airport · Editable maps")
      .toolbar {
        Picker("Map example", selection: $selectedExample) {
          Text("Yamanote · All 30 stations").tag("IslandRailway")
          Text("SFO tiles").tag("OpenStreetMapTiles")
          Text("SFO snapshot").tag("MapKitSnapshot")
        }
        Button("Map details", systemImage: "info.circle") { showsMapDetails = true }
      }
      .editableExample(.project(project, entry: entry), compositionID: selectedExample) { player.pause() }
      .task(id: selectedExample) {
        await player.load(.portable(project: project, entry: entry), compositionID: selectedExample)
      }
      .sheet(isPresented: $showsMapDetails) { RailwayMapDetails(isRailway: selectedExample == "IslandRailway") }
      .onDisappear { player.pause() }
  }
}

private struct RailwayMapDetails: View {
  let isRailway: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        if isRailway {
          Section("Yamanote Line · Tokyo, Japan") {
            Text("The railway study follows the full clockwise Yamanote Line through all 30 stations, starting and finishing at Tokyo.")
            Text("The green route follows real OpenStreetMap railway geometry. "
                 + "Japanese and English labels appear beside stations on the map.")
            Text("The camera zooms from the whole loop to the train, follows every station, then zooms out at Tokyo. "
                 + "Map tiles load on first use and are cached. Journey timing is illustrative.")
          }
        } else {
          Section("San Francisco International Airport") {
            Text("The tile and snapshot studies show the SFO Airport area using OpenStreetMap and Apple Maps imagery.")
            Text("Map tiles are fetched on first use and cached on this device.")
          }
        }
        Section("Data & attribution") {
          Link("© OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
          if isRailway {
            Link("View the Yamanote route", destination: URL(string: "https://www.openstreetmap.org/relation/1972920")!)
          } else {
            Link("View SFO on OpenStreetMap", destination: URL(string: "https://www.openstreetmap.org/#map=14/37.6213/-122.3790")!)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Map details")
      .toolbar { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 540, height: 480)
  }
}

/// Maps open directly in the visual editor, with navigation between the map studies.
struct MapsStudyEditor: View {
  @State private var selected = "IslandRailway"

  var body: some View {
    if let study = MotionStudy.study(selected) {
      ExampleEditorSheet(example: study.example, compositionID: study.compositionID, isSheet: false)
        .id(selected)
        .toolbar {
          Picker("Map study", selection: $selected) {
            ForEach(MotionStudy.maps) { Text($0.title).tag($0.id) }
          }
        }
    }
  }
}
