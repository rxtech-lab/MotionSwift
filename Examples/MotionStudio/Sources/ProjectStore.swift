import Foundation
import MotionCore
import MotionPortable
import Observation

/// The app's workspace: editable TSX projects and synced module graphs.
///
/// iOS/iPadOS keep it in Documents (visible in Files through file sharing); macOS uses
/// Application Support. The bundled sample project is copied on first launch so edits persist.
@MainActor
@Observable
final class ProjectStore {
  struct Project: Hashable, Identifiable {
    let name: String
    let directory: URL
    var id: URL { directory }
  }

  struct SyncedGraph: Hashable, Identifiable {
    let name: String
    let file: URL
    var id: URL { file }
  }

  nonisolated static let entry = "src/index.ts"

  private(set) var projects: [Project] = []
  private(set) var graphs: [SyncedGraph] = []
  let root: URL

  init(root: URL = ProjectStore.defaultRoot) {
    self.root = root
  }

  static var defaultRoot: URL {
    #if os(macOS)
    URL.applicationSupportDirectory.appendingPathComponent("MotionStudio", isDirectory: true)
    #else
    URL.documentsDirectory
    #endif
  }

  private var projectsDirectory: URL { root.appendingPathComponent("Projects", isDirectory: true) }
  private var graphsDirectory: URL { root.appendingPathComponent("Graphs", isDirectory: true) }

  /// Creates the workspace and installs the sample project when missing (or always, for UI tests).
  func prepare(resetSample: Bool = false) throws {
    let files = FileManager.default
    try files.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
    try files.createDirectory(at: graphsDirectory, withIntermediateDirectories: true)
    let sample = projectsDirectory.appendingPathComponent("Sample", isDirectory: true)
    if resetSample || !files.fileExists(atPath: sample.path) { try installSample(at: sample) }
    refresh()
  }

  func resetSample() throws {
    try installSample(at: projectsDirectory.appendingPathComponent("Sample", isDirectory: true))
    refresh()
  }

  private func installSample(at destination: URL) throws {
    guard let bundled = Bundle.main.url(forResource: "SampleProject", withExtension: nil) else {
      throw MotionError("The app bundle has no SampleProject resource")
    }
    let files = FileManager.default
    if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
    try files.copyItem(at: bundled, to: destination)
  }

  func refresh() {
    let files = FileManager.default
    let directories = (try? files.contentsOfDirectory(
      at: projectsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    projects = directories
      .filter { files.fileExists(atPath: $0.appendingPathComponent(Self.entry).path) }
      .map { Project(name: $0.lastPathComponent, directory: $0) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let graphFiles = (try? files.contentsOfDirectory(
      at: graphsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    graphs = graphFiles
      .filter { $0.pathExtension == ModuleGraph.fileExtension }
      .map { SyncedGraph(name: $0.deletingPathExtension().lastPathComponent, file: $0) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// Validates and stores a graph; returns its entry in the sidebar.
  @discardableResult
  func save(_ graph: ModuleGraph, named name: String) throws -> SyncedGraph {
    try graph.validate()
    let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
    let file = graphsDirectory.appendingPathComponent(safe.isEmpty ? "Graph" : safe)
      .appendingPathExtension(ModuleGraph.fileExtension)
    try graph.encoded().write(to: file, options: .atomic)
    refresh()
    return SyncedGraph(name: file.deletingPathExtension().lastPathComponent, file: file)
  }

  func importGraph(from url: URL) throws -> SyncedGraph {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    let graph = try ModuleGraph(data: Data(contentsOf: url))
    return try save(graph, named: url.deletingPathExtension().lastPathComponent)
  }

  func delete(_ graph: SyncedGraph) throws {
    try FileManager.default.removeItem(at: graph.file)
    refresh()
  }

  func load(_ graph: SyncedGraph) throws -> ModuleGraph {
    try ModuleGraph(data: Data(contentsOf: graph.file))
  }

  /// The graph server from Info.plist: localhost in Debug, the production domain in Release.
  static var defaultServer: String {
    (Bundle.main.object(forInfoDictionaryKey: "MotionSwiftGraphServer") as? String) ?? "http://localhost:4317"
  }
}
