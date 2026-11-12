import MotionCore
import MotionSwiftUI
import SwiftUI

enum SidebarItem: Hashable {
  case gallery
  case testFilm
  case composition(String)
}

struct ShowcaseSettings: Equatable {
  var render = MotionPlayer.Configuration()
  var loops = true
  var showsLayoutBounds = false
}

struct ProjectLocation: Equatable {
  var project: URL
  var entry: String
}

struct ContentView: View {
  @State private var player = MotionPlayer()
  @State private var testFilmPlayer = MotionPlayer(configuration: .init(scale: 1, backend: .gpu))
  @State private var selection: SidebarItem? = .gallery
  @State private var settings = ShowcaseSettings()
  @State private var location = ProjectLocation(
    project: ShowcaseDefaults.project, entry: ShowcaseDefaults.entry)
  @State private var showsSettings = false
  @State private var showsOpenProject = false
  @State private var toast: String?

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      detail
    }
    .toolbar {
      ToolbarItemGroup {
        Button("Open Project", systemImage: "folder") { showsOpenProject = true }
          .help("Preview another Remotion-style TSX project")
          .disabled(selection == .testFilm)
        Button("Reload", systemImage: "arrow.clockwise") { Task { await load() } }
          .help("Recompile the project and re-render")
          .keyboardShortcut("r")
          .disabled(selection == .testFilm)
        Button("Render Settings", systemImage: "slider.horizontal.3") { showsSettings = true }
          .help("Backend, scale, looping and layout bounds")
          .disabled(selection == .testFilm)
      }
    }
    .sheet(isPresented: $showsSettings) {
      RenderSettingsSheet(settings: settings) { apply($0) }
    }
    .sheet(isPresented: $showsOpenProject) {
      OpenProjectSheet(location: location) { newLocation in
        location = newLocation
        Task { await load() }
      }
    }
    .overlay(alignment: .bottom) { ToastOverlay(message: toast) }
    .task { await load() }
    .onChange(of: selection) { _, item in
      if case .composition(let id) = item { player.select(compositionID: id) } else { player.pause() }
    }
  }

  private var sidebar: some View {
    List(selection: $selection) {
      Section("Showcase") {
        Label("Gallery", systemImage: "square.grid.2x2").tag(SidebarItem.gallery)
        VStack(alignment: .leading, spacing: 2) {
          Label("Test Film", systemImage: "film")
          Text("1920×1080 · \(liveRate(testFilmPlayer))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(SidebarItem.testFilm)
      }
      Section("Compositions") {
        ForEach(player.compositions, id: \.id) { composition in
          VStack(alignment: .leading, spacing: 2) {
            Text(composition.id)
            Text(selection == .composition(composition.id)
                 ? "\(composition.width)×\(composition.height) · \(liveRate(player))"
                 : composition.sidebarSummary)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .tag(SidebarItem.composition(composition.id))
        }
      }
    }
    .navigationTitle("MotionSwift")
    .navigationSplitViewColumnWidth(min: 200, ideal: 230)
  }

  @ViewBuilder private var detail: some View {
    switch selection {
    case .testFilm:
      TestFilmView(player: testFilmPlayer)
    case .composition(let id):
      MotionPlayerView(player: player, showsLayoutBounds: settings.showsLayoutBounds)
        .padding(20)
        .navigationTitle(id)
        .navigationSubtitle(player.composition?.summary ?? "")
    default:
      GalleryView(player: player, settings: settings) { selection = .composition($0) }
        .navigationTitle("Gallery")
        .navigationSubtitle(location.project.lastPathComponent)
    }
  }

  private func liveRate(_ player: MotionPlayer) -> String {
    player.liveFPS.map { String(format: "Live %.1f fps", $0) } ?? "Live — fps"
  }

  private func load() async {
    let selected: String? = if case .composition(let id) = selection { id } else { nil }
    await player.load(
      .project(
        repository: ShowcaseDefaults.repository, project: location.project, entry: location.entry),
      compositionID: selected)
    if case .ready = player.status {
      if let selected, player.composition?.id != selected { selection = .gallery }
      show("Loaded \(player.compositions.count) compositions")
    }
  }

  private func apply(_ newSettings: ShowcaseSettings) {
    settings = newSettings
    player.loops = newSettings.loops
    player.update(configuration: newSettings.render)
    show("Render settings applied")
  }

  private func show(_ message: String) {
    withAnimation { toast = message }
    Task {
      try? await Task.sleep(for: .seconds(2))
      withAnimation { if toast == message { toast = nil } }
    }
  }
}

extension Composition {
  var sidebarSummary: String { "\(width)×\(height) · \(fps.formatted()) fps" }

  var summary: String {
    let seconds = Double(durationInFrames) / fps
    return "\(width)×\(height) · \(fps.formatted()) fps · \(seconds.formatted(.number.precision(.fractionLength(0...2)))) s"
  }
}

private struct ToastOverlay: View {
  let message: String?

  var body: some View {
    if let message {
      Label(message, systemImage: "checkmark.circle.fill")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6, y: 2)
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }
}
