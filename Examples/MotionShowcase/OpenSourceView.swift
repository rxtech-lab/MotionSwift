import AppKit
import MotionCore
import MotionSwiftUI
import SwiftUI

/// Metadata and MIT license notices for the bundled open-source Remotion examples.
enum OpenSourceCatalog {
  struct Manifest: Decodable, Sendable {
    let repositories: [Repository]
    let compositions: [Item]
  }

  struct Repository: Identifiable, Hashable, Decodable, Sendable {
    let id: String
    let name: String
    let slug: String
    let url: String
    let commit: String
    let copyright: String
    let license: String
    let summary: String
  }

  struct Item: Identifiable, Hashable, Decodable, Sendable {
    let id: String
    let title: String
    let repositoryId: String
    let sourcePath: String
    let upstreamPath: String
    let width: Int
    let height: Int
    let fps: Double
    let durationInFrames: Int
    let previewFrame: Int
    let unmodified: Bool
    let highlights: [String]
    let adaptation: String

    var durationSummary: String {
      let seconds = Double(durationInFrames) / fps
      let formattedSeconds = seconds.formatted(.number.precision(.fractionLength(0...1)))
      return "\(width)×\(height) · \(Int(fps)) fps · \(formattedSeconds) s"
    }
  }

  static var project: URL {
    guard let url = Bundle.module.url(forResource: "OpenSource", withExtension: nil) else {
      preconditionFailure("Missing bundled OpenSource resource folder")
    }
    return url
  }

  static var source: MotionSource {
    .portable(project: project, entry: "index.tsx")
  }

  static let manifest: Manifest = {
    let url = project.appendingPathComponent("provenance.json")
    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(Manifest.self, from: data)
    } catch {
      preconditionFailure("Invalid OpenSource/provenance.json: \(error)")
    }
  }()

  static let licenseText: String = {
    let url = project.appendingPathComponent("THIRD-PARTY-LICENSES.txt")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  }()

  static var repositories: [Repository] { manifest.repositories }
  static var compositions: [Item] { manifest.compositions }

  static func repository(_ id: String) -> Repository? {
    repositories.first { $0.id == id }
  }

  static func item(_ id: String) -> Item? {
    compositions.first { $0.id == id }
  }
}

/// Live SwiftUI gallery of 12 MIT-licensed open-source Remotion compositions across 4 repositories.
struct OpenSourceView: View {
  @State private var player = MotionPlayer(configuration: .init(scale: 0.5, backend: .gpu))
  @State private var path: [String] = ProcessInfo.processInfo.environment["MOTIONSWIFT_SHOWCASE_EXAMPLE"]
    .flatMap { OpenSourceCatalog.item($0)?.id }.map { [$0] } ?? []
  @State private var repositoryFilter = "all"
  @State private var showsLicenses = false
  @State private var error: String?

  private var filteredItems: [OpenSourceCatalog.Item] {
    if repositoryFilter == "all" { return OpenSourceCatalog.compositions }
    return OpenSourceCatalog.compositions.filter { $0.repositoryId == repositoryFilter }
  }

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          if let source = player.compiledSource {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 20)], spacing: 22) {
              ForEach(filteredItems) { item in
                OpenSourceCard(source: source, item: item)
              }
            }
          } else if let error {
            Label(error, systemImage: "exclamationmark.triangle")
              .padding()
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
          } else {
            ProgressView("Compiling open-source Remotion examples…")
              .frame(maxWidth: .infinity, minHeight: 240)
          }
        }
        .padding(20)
      }
      .accessibilityIdentifier("open-source-scroll")
      .navigationTitle("Open-Source Examples")
      .navigationSubtitle("12 MIT Remotion compositions · SwiftUI + Metal")
      .toolbar {
        ToolbarItem {
          Picker("Repository", selection: $repositoryFilter) {
            Text("All Projects (\(OpenSourceCatalog.compositions.count))").tag("all")
            ForEach(OpenSourceCatalog.repositories) { repo in
              Text(repo.name).tag(repo.id)
            }
          }
          .help("Filter compositions by upstream GitHub repository")
        }
        ToolbarItem {
          Button("Licenses & Provenance", systemImage: "doc.text.magnifyingglass") {
            showsLicenses = true
          }
          .help("View upstream GitHub repositories, commits and MIT license notices")
          .accessibilityIdentifier("open-source-licenses")
        }
      }
      .navigationDestination(for: String.self) { id in
        OpenSourcePlayerView(player: player, compositionID: id)
      }
      .sheet(isPresented: $showsLicenses) {
        OpenSourceAttributionSheet(selectedItem: nil)
      }
    }
    .task {
      await player.load(OpenSourceCatalog.source)
      if case .failed(let message) = player.status { error = message }
    }
    .onDisappear { player.pause() }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Community Remotion templates running natively in SwiftUI")
        .font(.title2.bold())
      Text("Every tile below is a live MotionCompositionView driven by JavaScriptCore, Yoga and Skia Metal. "
           + "Select any composition to inspect layers, scrub keyframes or export H.264/HEVC/ProRes video.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: 780, alignment: .leading)
    }
  }
}

private struct OpenSourceCard: View {
  let source: MotionSource
  let item: OpenSourceCatalog.Item

  private var repository: OpenSourceCatalog.Repository? {
    OpenSourceCatalog.repository(item.repositoryId)
  }

  var body: some View {
    NavigationLink(value: item.id) {
      VStack(alignment: .leading, spacing: 10) {
        MotionCompositionView(
          source: source, compositionID: item.id,
          configuration: .init(scale: 0.5, backend: .gpu))
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .allowsHitTesting(false)
        HStack(spacing: 6) {
          Text(repository?.slug ?? item.repositoryId)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer()
          Text(item.unmodified ? "Unmodified TSX" : "Subset-adapted")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
              (item.unmodified ? Color.green : Color.blue).opacity(0.15),
              in: Capsule())
            .foregroundStyle(item.unmodified ? .green : .blue)
        }
        HStack {
          Text(item.title).font(.headline)
          Spacer()
          Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
        }
        Text(item.durationSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(12)
      .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("open-source-\(item.id)")
    .help("Open \(item.title) in the visual editor")
  }
}

/// Opens an open-source composition in a durable editable working copy with provenance sheet access.
struct OpenSourcePlayerView: View {
  let player: MotionPlayer
  let compositionID: String
  @State private var showsAttribution = false

  private var item: OpenSourceCatalog.Item? {
    OpenSourceCatalog.item(compositionID)
  }

  var body: some View {
    ExampleEditorSheet(
      example: .project(OpenSourceCatalog.project, entry: "index.tsx"),
      compositionID: compositionID, isSheet: false,
      title: item?.title ?? compositionID,
      subtitle: (OpenSourceCatalog.repository(item?.repositoryId ?? "")?.slug ?? "MIT")
        + " · Working copy · Select layers to inspect or edit")
      .toolbar {
        ToolbarItem {
          Button("Provenance & License", systemImage: "doc.text.magnifyingglass") {
            showsAttribution = true
          }
          .help("Upstream repository, commit SHA, adaptation notes and MIT license")
        }
      }
      .sheet(isPresented: $showsAttribution) {
        OpenSourceAttributionSheet(selectedItem: item)
      }
      .onAppear { player.pause() }
  }
}

/// Full-height attribution and MIT license sheet for one composition or all bundled repositories.
struct OpenSourceAttributionSheet: View {
  @Environment(\.dismiss) private var dismiss
  let selectedItem: OpenSourceCatalog.Item?
  @State private var toast: String?

  var body: some View {
    NavigationStack {
      Form {
        if let selectedItem {
          compositionSection(selectedItem)
        }
        Section("Upstream MIT Repositories") {
          ForEach(displayedRepositories) { repo in
            repositoryRow(repo)
          }
        }
        Section("MIT License Notices") {
          Text(OpenSourceCatalog.licenseText)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .formStyle(.grouped)
      .navigationTitle(selectedItem?.title ?? "Licenses & Provenance")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .overlay(alignment: .bottom) { ToastOverlay(message: toast) }
    // Full-height content keeps the sheet's navigation title from being clipped on macOS.
    .frame(minWidth: 580, idealWidth: 640, minHeight: 500, idealHeight: 580, maxHeight: .infinity)
  }

  private var displayedRepositories: [OpenSourceCatalog.Repository] {
    if let selectedItem, let repo = OpenSourceCatalog.repository(selectedItem.repositoryId) {
      return [repo]
    }
    return OpenSourceCatalog.repositories
  }

  @ViewBuilder
  private func compositionSection(_ item: OpenSourceCatalog.Item) -> some View {
    Section("Composition") {
      LabeledContent("ID", value: item.id)
      LabeledContent("Format", value: item.durationSummary)
      LabeledContent("Bundled file", value: item.sourcePath)
      LabeledContent("Upstream path", value: item.upstreamPath)
      LabeledContent("Source status", value: item.unmodified ? "100% unmodified TSX" : "Subset-adapted TSX")
      LabeledContent("Notes", value: item.adaptation)
      ForEach(item.highlights, id: \.self) { highlight in
        Label(highlight, systemImage: "checkmark.circle")
      }
    }
  }

  @ViewBuilder
  private func repositoryRow(_ repo: OpenSourceCatalog.Repository) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        if let url = URL(string: repo.url) {
          Link(repo.slug, destination: url).font(.headline)
        } else {
          Text(repo.slug).font(.headline)
        }
        Spacer()
        Text(repo.license)
          .font(.caption.monospaced())
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(.quaternary, in: Capsule())
      }
      Text(repo.copyright).font(.caption).foregroundStyle(.secondary)
      Text(repo.summary).font(.callout)
      HStack(spacing: 8) {
        Text("Commit \(repo.commit.prefix(12))")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        Button("Copy SHA") { copyCommit(repo.commit) }
          .controlSize(.small)
      }
    }
    .padding(.vertical, 4)
  }

  private func copyCommit(_ commit: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(commit, forType: .string)
    withAnimation { toast = "Copied commit \(commit.prefix(8))" }
    Task {
      try? await Task.sleep(for: .seconds(2))
      withAnimation { toast = nil }
    }
  }
}
