import CryptoKit
import MotionCore
import MotionEditor
import MotionPortable
import SwiftUI

/// Each example keeps its own durable working copy, independent of regression fixtures.
enum ShowcaseExample: Hashable, Sendable {
  case project(URL, entry: String)
  case media
  case film

  func prepare(root: URL = EditorWorkspace.root.appendingPathComponent("Examples", isDirectory: true)) throws -> ProjectLocation {
    switch self {
    case .project(let source, let entry):
      let digest = SHA256.hash(data: Data(source.standardizedFileURL.path.utf8))
        .prefix(8).map { String(format: "%02x", $0) }.joined()
      return try stage(name: "\(source.lastPathComponent)-\(digest)", entry: entry, root: root) { destination in
        for (file, code) in try PortableCompiler.sources(in: source) {
          let target = destination.appendingPathComponent(file)
          try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
          try code.write(to: target, atomically: true, encoding: .utf8)
        }
        let assets = source.appendingPathComponent("public")
        if FileManager.default.fileExists(atPath: assets.path) {
          try FileManager.default.copyItem(at: assets, to: destination.appendingPathComponent("public"))
        }
      }
    case .media:
      return try stage(name: "Media", entry: "index.tsx", root: root) { destination in
        for (file, code) in try MediaDemo.files() {
          try code.write(to: destination.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
      }
    case .film:
      return try stage(name: "TestFilm-Layers-v1", entry: "src/index.ts", root: root) { destination in
        let source = try TestFilmFixture.prepare(repository: ShowcaseDefaults.repository)
        defer { try? FileManager.default.removeItem(at: source) }
        for item in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
          try FileManager.default.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
        }
        try EditableFilmProject.install(in: destination)
      }
    }
  }

  private func stage(name: String, entry: String, root: URL, populate: (URL) throws -> Void) throws -> ProjectLocation {
    let files = FileManager.default
    let destination = root.appendingPathComponent(name, isDirectory: true)
    if !files.fileExists(atPath: destination.appendingPathComponent(entry).path) {
      try files.createDirectory(at: root, withIntermediateDirectories: true)
      let staging = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try files.createDirectory(at: staging, withIntermediateDirectories: true)
      do {
        try populate(staging)
        guard files.fileExists(atPath: staging.appendingPathComponent(entry).path) else {
          throw MotionError("Example entry is missing: \(entry)")
        }
        do {
          try files.moveItem(at: staging, to: destination)
        } catch {
          // Multiple gallery cards can prepare the same project concurrently. Keep the first
          // complete working copy, including any edits, and discard only our temporary copy.
          guard files.fileExists(atPath: destination.appendingPathComponent(entry).path) else { throw error }
          try? files.removeItem(at: staging)
        }
      } catch {
        try? files.removeItem(at: staging)
        throw error
      }
    }
    return ProjectLocation(project: destination, entry: entry)
  }
}

/// Dedicated full-height editing surface shared by every showcase destination.
struct ExampleEditorSheet: View {
  let example: ShowcaseExample
  let compositionID: String?
  var isSheet = true
  @Environment(\.dismiss) private var dismiss
  @State private var model: EditorModel?
  @State private var failure: String?
  @State private var showsExport = false

  @ViewBuilder private var presentation: some View {
    if isSheet {
      NavigationStack { editorContent }
    } else {
      editorContent
    }
  }

  private var editorContent: some View {
      Group {
        if let model {
          MotionEditorView(model: model)
        } else {
          ProgressView("Preparing editable copy…")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(compositionID ?? "Edit Example")
      .navigationSubtitle("Working copy · Select an element for properties · Drag clips to move or trim")
      .toolbar {
        if isSheet {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { model?.player.pause(); dismiss() }
              .disabled(model?.status == .saving)
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("Export Edit", systemImage: "square.and.arrow.up") {
            model?.player.pause()
            showsExport = true
          }
          .disabled(model?.player.bundle == nil || model?.status != .idle)
        }
      }
  }

  var body: some View {
    presentation
    .frame(minWidth: isSheet ? 1040 : nil, idealWidth: isSheet ? 1260 : nil, maxWidth: .infinity,
           minHeight: isSheet ? 700 : nil, idealHeight: isSheet ? 820 : nil, maxHeight: .infinity)
    .sheet(isPresented: $showsExport) {
      if let bundle = model?.player.bundle, let composition = model?.player.composition {
        FilmExportSheet(bundle: bundle, composition: composition)
      }
    }
    .alert("Cannot Prepare Example", isPresented: Binding(
      get: { failure != nil }, set: { if !$0 { failure = nil } })) {
      Button("Close") { dismiss() }
    } message: { Text(failure ?? "") }
    .task {
      do {
        let location = try await Task.detached { try example.prepare() }.value
        guard !Task.isCancelled else { return }
        let editor = EditorModel(project: location.project, entry: location.entry,
                                 configuration: .init(scale: 1, backend: .gpu))
        // Open before mounting MotionEditorView so its automatic load cannot race this selection.
        await editor.open(compositionID: compositionID)
        model = editor
      } catch { failure = String(describing: error) }
    }
    .onDisappear { model?.player.pause() }
  }
}

struct ExampleEditing: ViewModifier {
  let example: ShowcaseExample
  let compositionID: String?
  let pause: () -> Void
  @State private var editing = false

  func body(content: Content) -> some View {
    content
      .toolbar {
        Button("Edit Timeline", systemImage: "timeline.selection") {
          pause()
          editing = true
        }
        .help("Edit a saved working copy with timeline, keyframes and element properties")
        .accessibilityIdentifier("edit-example")
      }
      .sheet(isPresented: $editing) { ExampleEditorSheet(example: example, compositionID: compositionID) }
  }
}

extension View {
  func editableExample(_ example: ShowcaseExample, compositionID: String?, pause: @escaping () -> Void) -> some View {
    modifier(ExampleEditing(example: example, compositionID: compositionID, pause: pause))
  }
}
