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
    MotionStudy(id: "Atlas", title: "The long way home", subtitle: "An offline map journey with a moving marker.", category: "04 / MAPS"),
  ]

  static let maps = [
    MotionStudy(id: "IslandRailway", title: "Hong Kong railway", subtitle: "Follow the Island Line across real OpenStreetMap geography.",
                category: "MAPS / RAILWAY", example: .project(railwayProject, entry: "index.tsx")),
    MotionStudy(id: "OpenStreetMapTiles", title: "Map tiles", subtitle: "Offline tiles with an animated route and marker.",
                category: "MAPS / TILES", example: .project(mapProject, entry: "src/index.tsx")),
    MotionStudy(id: "MapKitSnapshot", title: "Map snapshot", subtitle: "A snapshot composition with editable map overlays.",
                category: "MAPS / SNAPSHOT", example: .project(mapProject, entry: "src/index.tsx")),
  ]
  static var railwayProject: URL { Bundle.module.url(forResource: "Railway", withExtension: nil)! }
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
           + "Your work is saved in a separate copy.")
        .font(.body).foregroundStyle(.secondary).frame(maxWidth: 650, alignment: .leading)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 24)], spacing: 28) {
        ForEach(MotionStudy.all) { study in
          Button { open(study.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
              StudyPreview(study: study)
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

/// A still from the saved working copy keeps a large gallery from playing every film at once.
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
  private var project: URL {
    selectedExample == "IslandRailway" ? Self.railwayProject
      : ShowcaseDefaults.repository.appendingPathComponent("tests/maps")
  }
  private var entry: String { selectedExample == "IslandRailway" ? "index.tsx" : "src/index.tsx" }

  var body: some View {
    MotionPlayerView(player: player)
      .padding(20)
      .navigationTitle("Maps · Hong Kong railway")
      .navigationSubtitle(selectedExample == "IslandRailway"
        ? "OpenStreetMap geography · Island Line · Sheung Wan → Fortress Hill"
        : "Synthetic image regression examples")
      .toolbar {
        Picker("Map example", selection: $selectedExample) {
          Text("OpenStreetMap · Island Line").tag("IslandRailway")
          Text("Synthetic tiles").tag("OpenStreetMapTiles")
          Text("Synthetic snapshot").tag("MapKitSnapshot")
        }
        Button("Map details", systemImage: "info.circle") { showsMapDetails = true }
      }
      .editableExample(.project(project, entry: entry), compositionID: selectedExample) { player.pause() }
      .task(id: selectedExample) {
        await player.load(.portable(project: project, entry: entry), compositionID: selectedExample)
      }
      .sheet(isPresented: $showsMapDetails) { RailwayMapDetails() }
      .onDisappear { player.pause() }
  }
}

private struct RailwayMapDetails: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("OpenStreetMap · Hong Kong") {
          Text("The streets, coastline, railway geometry and station names come from a real OpenStreetMap data extract.")
          Text("The blue route follows the Island Line's eastbound track through seven stations, "
               + "from Sheung Wan to Fortress Hill. The train follows the track at a constant map speed.")
          Text("The bundled geographic extract keeps preview, editing and export reproducible without a network connection. "
               + "This is not a live navigation or timetable service.")
        }
        Section("Data & attribution") {
          Link("© OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
          Link("View the original railway relation", destination: URL(string: "https://www.openstreetmap.org/relation/4432666")!)
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
