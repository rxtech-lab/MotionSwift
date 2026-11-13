import Foundation
import ImageIO
import MotionCore
import MotionEditor
import MotionPortable
import MotionSwiftUI
import Testing
@testable import motionswift_showcase

@Test @MainActor
func showcaseStudiesRenderAndKeepEditableKeyframesAndDeclaredProperties() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("studies-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let example = ShowcaseExample.project(MotionStudy.project, entry: "index.tsx")
  let location = try example.prepare(root: directory)
  let original = try String(contentsOf: location.project.appendingPathComponent(location.entry), encoding: .utf8)
  let model = EditorModel(project: location.project, entry: location.entry, configuration: .init(scale: 0.5, backend: .gpu))
  for study in MotionStudy.designs {
    await model.open(compositionID: study.id)
    #expect(model.status == .idle)
    let first = try await model.player.render(frame: 0)
    let middle = try await model.player.render(frame: 90)
    #expect(first.image.width == 480)
    #expect(first.image.dataProvider?.data != middle.image.dataProvider?.data, "\(study.id) must animate")
    #expect(model.timelineTracks.contains { !$0.keyframes.isEmpty })
    // Keep reviewable contact-sheet source frames outside the source tree.
    if let output = ProcessInfo.processInfo.environment["MOTIONSWIFT_REVIEW_FRAMES"] {
      let url = URL(fileURLWithPath: output).appendingPathComponent(study.id + ".png")
      let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
      CGImageDestinationAddImage(destination, middle.image, nil)
      #expect(CGImageDestinationFinalize(destination))
    }
  }
  await model.open(compositionID: "Ribbon")
  let track = try #require(model.timelineTracks.first { $0.keyframes["left"] != nil })
  await model.setTiming(of: track.src, start: 12, duration: 200)
  #expect(model.canUndo)
  #expect(model.objectTracks.contains { $0.start == 12 && $0.keyframes["left"] != nil })
  await model.undo()
  #expect(try String(contentsOf: location.project.appendingPathComponent(location.entry), encoding: .utf8) == original)
  model.selectTrack(track)
  for _ in 0..<100 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.styles?.label(for: "width") == "Title width")
  #expect(model.detectedStyleProperties.contains { $0.key == "width" && $0.kind == .static })
  await model.setStyle("width", .number(560))
  #expect(model.canUndo)
  await model.undo()
  #expect(try String(contentsOf: location.project.appendingPathComponent(location.entry), encoding: .utf8) == original)
  // A reopened working copy preserves edits and never overwrites the bundled design.
  try "// retained\n".appending(original).write(to: location.project.appendingPathComponent(location.entry),
                                             atomically: true, encoding: .utf8)
  let reopened = try example.prepare(root: directory)
  #expect(try String(contentsOf: reopened.project.appendingPathComponent(reopened.entry), encoding: .utf8).hasPrefix("// retained"))
  #expect(try String(contentsOf: MotionStudy.project.appendingPathComponent("index.tsx"), encoding: .utf8) == original)
}

@Test @MainActor
func showcaseMapEditorRetainsPublicAssetsAcrossEditsAndUndo() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("map-editor-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let source = ShowcaseDefaults.repository.appendingPathComponent("tests/maps")
  let location = try ShowcaseExample.project(source, entry: "src/index.tsx").prepare(root: directory)
  let model = EditorModel(project: location.project, entry: location.entry, configuration: .init(scale: 1))
  await model.open(compositionID: "OpenStreetMapTiles")
  #expect(model.status == .idle)
  let before = try await model.player.render(frame: 0)
  let track = try #require(model.timelineTracks.first { $0.owner == "OpenStreetMapTiles" && $0.label == "AbsoluteFill" })
  await model.setTiming(of: track.src, start: 0, duration: 25)
  #expect(model.status == .idle)
  let after = try await model.player.render(frame: 0)
  #expect(before.image.dataProvider?.data == after.image.dataProvider?.data)
  await model.undo()
  let undone = try await model.player.render(frame: 0)
  #expect(before.image.dataProvider?.data == undone.image.dataProvider?.data)
  model.player.select(compositionID: "MapKitSnapshot")
  #expect(try await model.player.render(frame: 10).image.width == 320)
}

@Test @MainActor
func allAdditionalStudiesOpenRenderEditAndUndo() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("additional-studies-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  #expect(Set(MotionStudy.all.map(\.id)).count == MotionStudy.all.count)
  #expect(MotionStudy.maps.count == 3)
  #expect(MotionStudy.all.count == 8)
  for study in MotionStudy.maps + [MotionStudy.film] {
    let location = try study.example.prepare(root: directory)
    let model = EditorModel(project: location.project, entry: location.entry, configuration: .init(scale: 0.5, backend: .gpu))
    await model.open(compositionID: study.compositionID)
    #expect(model.status == .idle, "\(study.id): \(model.status)")
    #expect(model.player.composition?.id == study.compositionID)
    let before = try await model.player.render(frame: 10)
    #expect(before.image.width > 0)
    let track = try #require(model.timelineTracks.first { $0.reason == nil }, "\(study.id) needs an editable layer")
    let file = try #require(SourceStamp(track.src)?.file)
    let url = location.project.appendingPathComponent(file)
    let original = try String(contentsOf: url, encoding: .utf8)
    await model.setTiming(of: track.src, start: 2, duration: 20)
    #expect(model.status == .idle, "\(study.id): \(model.status)")
    #expect(model.canUndo, "\(study.id) timing must write back")
    #expect(try String(contentsOf: url, encoding: .utf8) != original)
    _ = try await model.player.render(frame: 10)
    await model.undo()
    #expect(try String(contentsOf: url, encoding: .utf8) == original)
    let undone = try await model.player.render(frame: 10)
    #expect(before.image.dataProvider?.data == undone.image.dataProvider?.data, "\(study.id) undo must restore rendering")
  }
}

@Test
func studyCardsCanPrepareSharedProjectsConcurrently() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("study-staging-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let example = ShowcaseExample.project(MotionStudy.project, entry: "index.tsx")
  let locations = try await withThrowingTaskGroup(of: URL.self) { group in
    for _ in 0..<4 { group.addTask { try example.prepare(root: directory).project } }
    var result: [URL] = []
    for try await project in group { result.append(project) }
    return result
  }
  #expect(Set(locations).count == 1)
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
}

@Test @MainActor
func testFilmHasIndependentObjectLayersAndVisualEdits() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("film-layers-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let location = try ShowcaseExample.film.prepare(root: directory)
  let model = EditorModel(project: location.project, entry: location.entry, configuration: .init(scale: 0.25, backend: .gpu))
  await model.open(compositionID: "Main")
  #expect(model.status == .idle)
  let layers = model.objectTracks.filter { $0.label == "EditableLayer" || $0.owner == "editableObject" }
  #expect(layers.count == 179)
  #expect(layers.allSatisfy { $0.reason == nil })
  let title = try #require(layers.first { $0.label == "title" })
  model.player.seek(to: 90)
  for _ in 0..<200 where model.player.displayedFrame?.frame != 90 { try await Task.sleep(for: .milliseconds(10)) }
  model.observeTimelineFrame()
  #expect(model.timelineTracks.contains { $0.src == title.src })
  model.selectTrack(title)
  for _ in 0..<200 where model.styles == nil { try await Task.sleep(for: .milliseconds(10)) }
  #expect(model.selectedRect != nil)
  let before = try await model.player.render(frame: 90)
  #expect(model.beginGesture(.move(dx: 0, dy: 0)))
  model.updateGesture(.move(dx: 100, dy: 40), snapThreshold: 0)
  await model.endGesture(named: "Move title")
  #expect(model.canUndo)
  let moved = try await model.player.render(frame: 90)
  #expect(before.image.dataProvider?.data != moved.image.dataProvider?.data)
  await model.undo()
  #expect(try await model.player.render(frame: 90).image.dataProvider?.data == before.image.dataProvider?.data)
  #expect(model.beginGesture(.resize(handle: .bottomTrailing, dx: 0, dy: 0, keepsAspectRatio: false)))
  model.updateGesture(.resize(handle: .bottomTrailing, dx: 140, dy: 40, keepsAspectRatio: false), snapThreshold: 0)
  await model.endGesture(named: "Resize title")
  #expect(try await model.player.render(frame: 90).image.dataProvider?.data != before.image.dataProvider?.data)
  await model.undo()
  await model.setStyle("content", .string("可编辑的电影标题"))
  #expect(model.status == .idle)
  #expect(try await model.player.render(frame: 90).image.dataProvider?.data != before.image.dataProvider?.data)
  await model.undo()
  await model.setStyle("color", .string("#ff0000"))
  #expect(try await model.player.render(frame: 90).image.dataProvider?.data != before.image.dataProvider?.data)
  await model.undo()
  #expect(try await model.player.render(frame: 90).image.dataProvider?.data == before.image.dataProvider?.data)
  let fixture = try TestFilmFixture.prepare(repository: ShowcaseDefaults.repository)
  defer { try? FileManager.default.removeItem(at: fixture) }
  let reference = MotionPlayer(configuration: .init(scale: 0.25, backend: .gpu))
  await reference.load(.portable(project: fixture, entry: "src/index.ts"), compositionID: "Main")
  for frame in [0, 90, 300, 660, 1050, 1424, 2574, 2699] {
    let rendered = try await model.player.render(frame: frame)
    #expect(rendered.image.width == 480)
    if let output = ProcessInfo.processInfo.environment["MOTIONSWIFT_REVIEW_FRAMES"] {
      let original = try await reference.render(frame: frame)
      for (label, image) in [("editable", rendered.image), ("original", original.image)] {
        let url = URL(fileURLWithPath: output).appendingPathComponent("film-\(label)-\(frame).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
      }
    }
  }
}
