import AppKit
import MotionCore
import MotionSwiftUI
import SwiftUI
import UniformTypeIdentifiers

struct TestFilmView: View {
  let player: MotionPlayer
  @State private var showsExport = false
  @State private var failure: String?
  @State private var currentBytes: UInt64?
  @State private var peakBytes: UInt64?
  @State private var loading = true

  var body: some View {
    MotionPlayerView(player: player)
      .padding(20)
      .editableExample(.film, compositionID: "Main") { player.pause() }
      .navigationTitle("Test Film")
      .navigationSubtitle("Benchmark project · 1920×1080 · 30 fps · 90 s")
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 20) {
          Label("App RSS \(AppMemory.formatted(currentBytes))", systemImage: "memorychip")
          Text("Preview peak \(AppMemory.formatted(peakBytes))")
          Spacer()
          Text("Metal · 1× preview").foregroundStyle(.secondary)
        }
        .font(.caption.monospacedDigit())
        .padding(12)
        .background(.bar)
        .help("Current showcase process RSS, sampled every 250 ms. "
              + "Includes preview/cache; excludes other processes and separate GPU accounting.")
      }
      .toolbar {
        ToolbarItem {
          Button("Render Test Film", systemImage: "square.and.arrow.up") {
            player.pause()
            showsExport = true
          }
          .disabled(player.bundle == nil || loading)
        }
      }
      .sheet(isPresented: $showsExport) {
        if let bundle = player.bundle, let composition = player.composition {
          FilmExportSheet(bundle: bundle, composition: composition)
        }
      }
      .overlay {
        if loading {
          ProgressView("Loading benchmark Test Film…")
            .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
      }
      .alert("Cannot Load Test Film", isPresented: Binding(
        get: { failure != nil }, set: { if !$0 { failure = nil } })
      ) {
        Button("Retry") { Task { await load() } }
        Button("OK", role: .cancel) { }
      } message: { Text(failure ?? "") }
      .task { await load() }
      .task {
        while !Task.isCancelled {
          currentBytes = AppMemory.residentBytes()
          if let currentBytes { peakBytes = max(peakBytes ?? 0, currentBytes) }
          do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
      }
      .onDisappear { player.pause() }
  }

  private func load() async {
    loading = true
    defer { loading = false }
    do {
      let repository = ShowcaseDefaults.repository
      let project = try await Task.detached { try TestFilmFixture.prepare(repository: repository) }.value
      defer { try? FileManager.default.removeItem(at: project) }
      guard !Task.isCancelled else { return }
      await player.load(ShowcaseDefaults.source(project: project, entry: "src/index.ts"), compositionID: "Main")
      if case .failed(let error) = player.status { failure = error }
    } catch {
      failure = String(describing: error)
    }
  }
}

struct FilmExportSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var job = FilmExport()
  @State private var workers = min(8, ProcessInfo.processInfo.activeProcessorCount)
  let bundle: String
  let composition: Composition

  var body: some View {
    NavigationStack {
      Form {
        Section("Composition export") {
          LabeledContent("Composition", value: composition.summary)
          LabeledContent("Frames", value: "\(composition.durationInFrames)")
          LabeledContent("Pipeline", value: "Metal → IOSurface → VideoToolbox")
          Picker("Workers", selection: $workers) {
            ForEach(1...ProcessInfo.processInfo.activeProcessorCount, id: \.self) { Text("\($0)").tag($0) }
          }
          .disabled(job.isRunning)
          Text("Exports the full H.264 movie with synchronized audio at native resolution.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Section("Memory") {
          LabeledContent("Current app RSS", value: AppMemory.formatted(job.currentBytes))
          LabeledContent("Render peak app RSS", value: AppMemory.formatted(job.peakBytes))
          Text("Sampled every 250 ms, including the app and preview cache. "
               + "Excludes other processes; GPU/media-engine allocations are not separately measured. The render peak resets each run.")
            .font(.caption).foregroundStyle(.secondary)
        }
        if let output = job.output {
          Section("Video") {
            LabeledContent("Saved", value: output.lastPathComponent)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Export Composition")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(job.isRunning ? "Stop" : "Close") {
            if job.isRunning { job.cancel() } else { dismiss() }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Render…") { chooseDestination() }.disabled(job.isRunning)
        }
      }
      .overlay(alignment: .bottom) {
        if job.isRunning || job.status != "Ready to render" {
          VStack(spacing: 8) {
            Text(job.status)
            if job.isRunning {
              ProgressView(value: Double(job.completedFrames), total: Double(max(1, job.totalFrames)))
              Text("\(job.completedFrames) / \(job.totalFrames) frames · \(percent)%")
                .font(.caption.monospacedDigit())
            }
          }
          .padding(16)
          .frame(maxWidth: 360)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
          .padding()
        }
      }
      .alert("Render Failed", isPresented: Binding(
        get: { job.error != nil }, set: { if !$0 { job.error = nil } })
      ) { Button("OK", role: .cancel) { } } message: { Text(job.error ?? "") }
    }
    .frame(minWidth: 560, idealWidth: 600, minHeight: 560, idealHeight: 600, maxHeight: .infinity)
    .interactiveDismissDisabled(job.isRunning)
    .task {
      while !Task.isCancelled {
        job.sampleMemory()
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      }
    }
  }

  private func chooseDestination() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.mpeg4Movie]
    panel.nameFieldStringValue = composition.id + ".mp4"
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    Task { await job.render(bundle: bundle, composition: composition, destination: destination, workers: workers) }
  }

  private var percent: Int {
    Int(Double(job.completedFrames) / Double(max(1, job.totalFrames)) * 100)
  }
}
