import AppKit
import Foundation
import MotionCore
@testable import MotionEditor
import MotionSwiftUI
import SwiftUI
import Testing
@testable import motionswift_showcase

@Test
func openSourceCatalogIncludesAllApprovedMITRepositoriesAndLicenses() throws {
  #expect(OpenSourceCatalog.repositories.count == 4)
  #expect(OpenSourceCatalog.compositions.count == 12)
  #expect(Set(OpenSourceCatalog.compositions.map(\.id)).count == 12)
  #expect(OpenSourceCatalog.compositions.filter(\.unmodified).count == 5)
  for repo in OpenSourceCatalog.repositories {
    #expect(repo.license == "MIT")
    #expect(repo.commit.count == 40)
    #expect(OpenSourceCatalog.licenseText.contains(repo.slug))
    #expect(OpenSourceCatalog.licenseText.contains(repo.copyright))
  }
  for item in OpenSourceCatalog.compositions {
    #expect(OpenSourceCatalog.repository(item.repositoryId) != nil)
    #expect(FileManager.default.fileExists(
      atPath: OpenSourceCatalog.project.appendingPathComponent(item.sourcePath).path))
  }
}

@Test @MainActor
func allOpenSourceCompositionsRenderAnimateAndOpenInVisualEditor() async throws {
  let player = MotionPlayer(configuration: .init(scale: 0.25, backend: .gpu))
  await player.load(OpenSourceCatalog.source)
  if case .failed(let message) = player.status {
    Issue.record("Failed to compile OpenSource bundle: \(message)")
    return
  }
  #expect(player.compositions.count == 12)

  for item in OpenSourceCatalog.compositions {
    player.select(compositionID: item.id)
    #expect(player.composition?.id == item.id)
    let early = try await player.render(frame: 0)
    let preview = try await player.render(frame: item.previewFrame)
    #expect(early.image.width == item.width / 4)
    #expect(early.image.height == item.height / 4)
    #expect(early.image.dataProvider?.data != preview.image.dataProvider?.data,
            "\(item.id) must animate between frame 0 and previewFrame \(item.previewFrame)")
  }

  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("open-source-editor-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let location = try ShowcaseExample.project(OpenSourceCatalog.project, entry: "index.tsx").prepare(root: directory)
  let editor = EditorModel(project: location.project, entry: location.entry,
                           configuration: .init(scale: 0.5, backend: .gpu))
  await editor.open(compositionID: "ProductDemo")
  #expect(editor.status == .idle)
  #expect(editor.player.composition?.id == "ProductDemo")
  #expect(!editor.objectTracks.isEmpty)
  editor.player.seek(to: 265)
  for _ in 0..<50 where editor.player.displayedFrame?.frame != 265 {
    try await Task.sleep(for: .milliseconds(50))
  }
  #expect(editor.player.displayedFrame?.frame == 265)
  editor.select(at: CGPoint(x: 1310, y: 910))
  try await Task.sleep(for: .milliseconds(150))

  if let outputPath = ProcessInfo.processInfo.environment["MOTIONSWIFT_OPEN_SOURCE_SNAPSHOT"] {
    try writeEditorSnapshot(model: editor, to: URL(fileURLWithPath: outputPath))
  }
}

@MainActor
private func writeEditorSnapshot(model: EditorModel, to output: URL) throws {
  let rootView = NavigationStack {
    MotionEditorView(model: model)
      .navigationTitle("Acme Studio Product Demo")
      .navigationSubtitle("Alexwtlf/agentic-product-demo · SwiftUI + Skia Metal")
  }
  .environment(\.colorScheme, .light)
  .frame(width: 1200, height: 780)

  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered, defer: false)
  window.appearance = NSAppearance(named: .aqua)
  let hosting = NSHostingView(rootView: rootView)
  hosting.frame = NSRect(x: 0, y: 0, width: 1200, height: 780)
  window.contentView = hosting
  hosting.layoutSubtreeIfNeeded()
  RunLoop.main.run(until: Date().addingTimeInterval(0.3))
  hosting.layoutSubtreeIfNeeded()

  guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
    throw MotionError("Cannot allocate SwiftUI hosting bitmap")
  }
  hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw MotionError("Cannot encode SwiftUI snapshot PNG")
  }
  try png.write(to: output)
}
