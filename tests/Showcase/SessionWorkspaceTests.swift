import Foundation
import Testing
@testable import motionswift_showcase

@Test
func showcaseEditsSurviveReopeningButResetInANewSession() throws {
  let files = FileManager.default
  let directory = files.temporaryDirectory.appendingPathComponent("session-test-\(UUID())")
  defer { try? files.removeItem(at: directory) }
  let source = directory.appendingPathComponent("Source")
  try files.createDirectory(at: source, withIntermediateDirectories: true)
  let original = "export const config = { duration: 90 };\n"
  try original.write(to: source.appendingPathComponent("index.tsx"), atomically: true, encoding: .utf8)

  let firstSession = EditorWorkspace.makeSessionRoot(in: directory)
  let secondSession = EditorWorkspace.makeSessionRoot(in: directory)
  #expect(firstSession != secondSession)
  #expect(EditorWorkspace.root == EditorWorkspace.root)
  #expect(EditorWorkspace.sample.deletingLastPathComponent() == EditorWorkspace.root)
  let example = ShowcaseExample.project(source, entry: "index.tsx")
  let first = try example.prepare(root: firstSession)
  let edited = "export const config = { duration: 180 };\n"
  try edited.write(to: first.project.appendingPathComponent(first.entry), atomically: true, encoding: .utf8)

  let reopened = try example.prepare(root: firstSession)
  #expect(reopened == first)
  #expect(try String(contentsOf: reopened.project.appendingPathComponent(reopened.entry), encoding: .utf8) == edited)
  let restarted = try example.prepare(root: secondSession)
  #expect(restarted.project != first.project)
  #expect(try String(contentsOf: restarted.project.appendingPathComponent(restarted.entry), encoding: .utf8) == original)
  #expect(try String(contentsOf: source.appendingPathComponent("index.tsx"), encoding: .utf8) == original)
}
