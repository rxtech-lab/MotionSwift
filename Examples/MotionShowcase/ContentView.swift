import MotionCore
import MotionEditor
import MotionSwiftUI
import SwiftUI

enum SidebarItem: Hashable {
  case media
  case gallery
  case testFilm
  case editor
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
  /// `MOTIONSWIFT_SHOWCASE_START=editor` opens the visual editor first (demos and screenshots).
  @State private var selection: SidebarItem? =
    ProcessInfo.processInfo.environment["MOTIONSWIFT_SHOWCASE_START"] == "editor" ? .editor :
      (ProcessInfo.processInfo.environment["MOTIONSWIFT_SHOWCASE_START"] == "media" ? .media : .gallery)
  @State private var settings = ShowcaseSettings()
  @State private var location = ProjectLocation(
    project: ShowcaseDefaults.project, entry: ShowcaseDefaults.entry)
  @State private var showsSettings = false
  @State private var showsOpenProject = false
  @State private var toast: String?
  /// The visual editor and the project it edits (a copy of the sample unless the user chose one).
  @State private var editor: EditorModel?
  @State private var editorLocation: ProjectLocation?
  @State private var showsEditProject = false
  @State private var pendingEditLocation: ProjectLocation?
  @State private var resettingSample = false

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
          .disabled(selection == .testFilm || selection == .editor || selection == .media)
        Button("Reload", systemImage: "arrow.clockwise") { Task { await load() } }
          .help("Recompile the project and re-render")
          .keyboardShortcut("r")
          .disabled(selection == .testFilm || selection == .editor || selection == .media)
        Button("Render Settings", systemImage: "slider.horizontal.3") { showsSettings = true }
          .help("Backend, scale, looping and layout bounds")
          .disabled(selection == .testFilm || selection == .editor || selection == .media)
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
    .sheet(isPresented: $showsEditProject) {
      OpenProjectSheet(location: editorLocation ?? ProjectLocation(
        project: EditorWorkspace.sample, entry: ShowcaseDefaults.entry)) { pendingEditLocation = $0 }
    }
    .confirmationDialog(
      "Edit \(pendingEditLocation?.project.lastPathComponent ?? "project") in place?",
      isPresented: Binding(get: { pendingEditLocation != nil }, set: { if !$0 { pendingEditLocation = nil } }),
      titleVisibility: .visible, presenting: pendingEditLocation
    ) { location in
      Button("Edit Source Files") { openEditor(location) }
    } message: { location in
      Text("Canvas and inspector edits are written to the TSX files in \(location.project.path). Undo restores them.")
    }
    .confirmationDialog("Reset the sample project?", isPresented: $resettingSample, titleVisibility: .visible) {
      Button("Reset Sample", role: .destructive) { openSample(reset: true) }
    } message: {
      Text("Your edits to the editor's copy of the sample are discarded.")
    }
    .onChange(of: selection) { _, item in if item == .editor, editor == nil { openSample(reset: false) } }
    .overlay(alignment: .bottom) { ToastOverlay(message: toast) }
    .task {
      if selection == .editor { openSample(reset: false) }
      await load()
    }
    .onChange(of: selection) { _, item in
      if case .composition(let id) = item { player.select(compositionID: id) } else { player.pause() }
    }
  }

  private var sidebar: some View {
    List(selection: $selection) {
      Section("Showcase") {
        Label("Gallery", systemImage: "square.grid.2x2").tag(SidebarItem.gallery)
        Label("Media Composition", systemImage: "rectangle.stack.fill").tag(SidebarItem.media)
        VStack(alignment: .leading, spacing: 2) {
          Label("Test Film", systemImage: "film")
          Text("1920×1080 · \(liveRate(testFilmPlayer))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(SidebarItem.testFilm)
        VStack(alignment: .leading, spacing: 2) {
          Label("Visual Editor", systemImage: "cursorarrow.motionlines")
          Text(editorLocation.map { $0.project.lastPathComponent } ?? "Canvas, timeline and keyframes")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(SidebarItem.editor)
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
    case .media:
      MediaDemoView()
    case .testFilm:
      TestFilmView(player: testFilmPlayer)
    case .editor:
      if let editor {
        MotionEditorView(model: editor)
          .id(editorLocation?.project)
          .navigationTitle("Visual Editor")
          .navigationSubtitle((editorLocation?.project.lastPathComponent ?? "") + " · Canvas & Timeline")
          .toolbar {
            ToolbarItem {
              Menu {
                Button("Edit Project…", systemImage: "folder") { showsEditProject = true }
                Button("Edit Sample", systemImage: "doc.text.image") { openSample(reset: false) }
                Button("Reset Sample…", systemImage: "arrow.counterclockwise", role: .destructive) {
                  resettingSample = true
                }
              } label: {
                Label("Project", systemImage: "folder.badge.gearshape")
              }
              .help("Choose which Remotion project the editor writes to")
            }
          }
      } else {
        ProgressView()
      }
    case .composition(let id):
      MotionPlayerView(player: player, showsLayoutBounds: settings.showsLayoutBounds)
        .padding(20)
        .navigationTitle(id)
        .navigationSubtitle(player.composition?.summary ?? "")
    default:
      GalleryView(player: player, settings: settings) { selection = $0 }
        .navigationTitle("Gallery")
        .navigationSubtitle(location.project.lastPathComponent)
    }
  }

  private func openSample(reset: Bool) {
    do {
      let sample = try EditorWorkspace.prepareSample(reset: reset)
      openEditor(ProjectLocation(project: sample, entry: ShowcaseDefaults.entry))
      if reset { show("Sample project reset") }
    } catch {
      show("Cannot open the sample: \(error)")
    }
  }

  private func openEditor(_ location: ProjectLocation) {
    editor?.player.pause()
    editorLocation = location
    editor = EditorModel(
      project: location.project, entry: location.entry, configuration: .init(scale: 2, backend: .gpu))
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
