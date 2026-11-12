import MotionEditor
import MotionPortable
import MotionSwiftUI
import SwiftUI

/// MotionStudio: the MotionSwift visual editor for iPhone, iPad and Mac.
///
/// Projects compile on device with the portable compiler (Sucrase in JavaScriptCore) against the
/// precompiled vendor graph, so no Node or JIT is needed. Projects that import other npm packages
/// sync their module graph from a Mac (`motionswift serve-graph`) or the cloud.
@main
struct MotionStudioApp: App {
  @State private var store = ProjectStore()

  var body: some Scene {
    WindowGroup {
      StudioRootView(store: store)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 560)
        #endif
    }
  }
}

enum SidebarItem: Hashable {
  case project(ProjectStore.Project)
  case graph(ProjectStore.SyncedGraph)
}

struct StudioRootView: View {
  let store: ProjectStore
  @State private var selection: SidebarItem?
  @State private var editors: [URL: EditorModel] = [:]
  @State private var sheet: Sheet?
  @State private var importing = false
  @State private var resettingSample = false
  @State private var deletingGraph: ProjectStore.SyncedGraph?
  @State private var toast: String?
  @State private var failure: String?

  enum Sheet: Identifiable {
    case sync, budget(ProjectStore.Project)
    var id: String {
      switch self {
      case .sync: "sync"
      case .budget(let project): "budget-\(project.directory.path)"
      }
    }
  }

  private static let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      NavigationStack { detail }
    }
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .sync: SyncSheet(store: store) { graph in
        selection = .graph(graph)
        show("Synced \(graph.name)")
      }
      case .budget(let project): BudgetSheet(project: project)
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .json]) { result in
      do {
        let graph = try store.importGraph(from: result.get())
        selection = .graph(graph)
        show("Imported \(graph.name)")
      } catch {
        failure = String(describing: error)
      }
    }
    .confirmationDialog("Reset the sample project?", isPresented: $resettingSample, titleVisibility: .visible) {
      Button("Reset Sample", role: .destructive) { resetSample() }
    } message: {
      Text("Your edits to the sample's TSX files are discarded.")
    }
    .confirmationDialog(
      "Delete \(deletingGraph?.name ?? "graph")?",
      isPresented: Binding(get: { deletingGraph != nil }, set: { if !$0 { deletingGraph = nil } }),
      titleVisibility: .visible, presenting: deletingGraph
    ) { graph in
      Button("Delete", role: .destructive) { delete(graph) }
    }
    .alert("Something went wrong", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(failure ?? "")
    }
    .onChange(of: selection, initial: true) { _, item in makeEditor(for: item) }
    .overlay(alignment: .bottom) { ToastOverlay(message: toast) }
    .sensoryFeedback(.success, trigger: toast) { _, new in new != nil }
    .task {
      do {
        try store.prepare(resetSample: Self.uiTesting)
        if selection == nil, let sample = store.projects.first { selection = .project(sample) }
      } catch {
        failure = String(describing: error)
      }
    }
  }

  private var sidebar: some View {
    List(selection: $selection) {
      Section("Projects") {
        ForEach(store.projects) { project in
          Label(project.name, systemImage: "doc.text.image")
            .tag(SidebarItem.project(project))
            .contextMenu {
              Button("Preview Budget…", systemImage: "gauge.with.dots.needle.33percent") { sheet = .budget(project) }
              if project.name == "Sample" {
                Button("Reset Sample…", systemImage: "arrow.counterclockwise", role: .destructive) {
                  resettingSample = true
                }
              }
            }
        }
      }
      Section("Synced Graphs") {
        if store.graphs.isEmpty {
          Text("Sync from a Mac or import a .msgraph file").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(store.graphs) { graph in
          Label(graph.name, systemImage: "point.3.connected.trianglepath.dotted")
            .tag(SidebarItem.graph(graph))
            .contextMenu {
              Button("Delete…", systemImage: "trash", role: .destructive) { deletingGraph = graph }
            }
            .swipeActions {
              Button("Delete", systemImage: "trash", role: .destructive) { deletingGraph = graph }
            }
        }
      }
    }
    .navigationTitle("MotionStudio")
    .toolbar {
      ToolbarItem {
        Menu {
          Button("Sync from Mac or Cloud…", systemImage: "arrow.triangle.2.circlepath") { sheet = .sync }
          Button("Import Graph File…", systemImage: "square.and.arrow.down") { importing = true }
          if let project = budgetProject {
            Button("Preview Budget…", systemImage: "gauge.with.dots.needle.33percent") { sheet = .budget(project) }
          }
        } label: {
          Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("studio-menu")
      }
    }
  }

  /// The selected project, else the first one (compact layouts clear the selection on back).
  private var budgetProject: ProjectStore.Project? {
    if case .project(let project) = selection { return project }
    return store.projects.first
  }

  @ViewBuilder private var detail: some View {
    switch selection {
    case .project(let project):
      if let editor = editors[project.directory] {
        MotionEditorView(model: editor)
          .id(project.directory)
          .navigationTitle(project.name)
          #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
          #endif
      } else {
        ProgressView()
      }
    case .graph(let graph):
      GraphPreview(store: store, graph: graph)
        .id(graph.file)
        .navigationTitle(graph.name)
    case nil:
      ContentUnavailableView("Select a Project", systemImage: "sidebar.leading",
        description: Text("Edit TSX projects visually, or preview graphs synced from a Mac."))
    }
  }

  private func makeEditor(for item: SidebarItem?) {
    guard case .project(let project) = item, editors[project.directory] == nil else { return }
    #if os(iOS)
    // Interpreted JavaScriptCore on devices: keep preview frames small (budget sheet measures this).
    let configuration = MotionPlayer.Configuration(scale: 1, backend: .gpu, cacheBytes: 128 << 20)
    #else
    let configuration = MotionPlayer.Configuration(scale: 2, backend: .gpu)
    #endif
    editors[project.directory] = EditorModel(
      project: project.directory, entry: ProjectStore.entry, configuration: configuration)
  }

  private func resetSample() {
    do {
      try store.resetSample()
      editors = [:]
      makeEditor(for: selection)
      show("Sample project reset")
    } catch {
      failure = String(describing: error)
    }
  }

  private func delete(_ graph: ProjectStore.SyncedGraph) {
    do {
      try store.delete(graph)
      if selection == .graph(graph) { selection = nil }
      show("Deleted \(graph.name)")
    } catch {
      failure = String(describing: error)
    }
  }

  private func show(_ message: String) {
    withAnimation { toast = message }
    Task {
      try? await Task.sleep(for: .seconds(2))
      withAnimation { if toast == message { toast = nil } }
    }
  }
}

/// Synced graphs carry compiled modules only, so they preview and play but cannot be edited.
struct GraphPreview: View {
  let store: ProjectStore
  let graph: ProjectStore.SyncedGraph
  @State private var player = MotionPlayer(configuration: .init(scale: 1, backend: .gpu))
  @State private var details: ModuleGraph?

  var body: some View {
    VStack(spacing: 12) {
      MotionPlayerView(player: player)
      if let details {
        let packages = details.packages.isEmpty ? "none" : details.packages.joined(separator: ", ")
        Text("\(details.modules.count) modules · packages: \(packages) · \(details.producer)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .toolbar {
      if player.compositions.count > 1 {
        Menu {
          ForEach(player.compositions, id: \.id) { composition in
            Button(composition.id) { player.select(compositionID: composition.id) }
          }
        } label: {
          Label(player.composition?.id ?? "Composition", systemImage: "rectangle.stack")
        }
      }
    }
    .task {
      do {
        let graph = try store.load(graph)
        details = graph
        await player.load(.graph(graph))
      } catch {
        await player.load(.bundle("throw Error(\(String(reflecting: String(describing: error))))"))
      }
    }
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
