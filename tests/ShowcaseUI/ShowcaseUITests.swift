import XCTest

/// Exercises the release payload at an explicit URL, outside the source checkout.
@MainActor final class ShowcaseUITests: XCTestCase {
  private var app: XCUIApplication!
  private var workspace: URL!

  override func setUp() async throws {
    continueAfterFailure = false
    let path = try XCTUnwrap(ProcessInfo.processInfo.environment["SHOWCASE_UI_APP"])
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    app = XCUIApplication(url: URL(fileURLWithPath: path))
    workspace = FileManager.default.temporaryDirectory.appendingPathComponent("showcase-ui-\(UUID())")
    app.launchEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                             "MOTIONSWIFT_SHOWCASE_WORKSPACE": workspace.path]
    app.launch()
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
  }

  override func tearDown() async throws {
    if let app {
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.lifetime = .keepAlways
      add(attachment)
      app.terminate()
    }
    if let workspace { try? FileManager.default.removeItem(at: workspace) }
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func rendered(_ id: String) {
    let preview = element("preview-\(id)")
    XCTAssertTrue(preview.waitForExistence(timeout: 60), "Missing \(id) preview")
    assertRendered(preview)
  }

  private func assertRendered(_ preview: XCUIElement) {
    let ready = NSPredicate(format: "label CONTAINS 'Rendered frame '")
    let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: preview)], timeout: 60)
    XCTAssertEqual(result, .completed, "\(preview.identifier): \(preview.label)")
  }

  private func sidebar(_ title: String) {
    let item = app.outlines.staticTexts[title].firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 30), "Missing sidebar item \(title)")
    item.click()
  }

  private func editorRendered(_ id: String) {
    let canvas = element("editor-canvas")
    XCTAssertTrue(canvas.waitForExistence(timeout: 60))
    let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", id), object: canvas)
    XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 60), .completed)
    assertRendered(canvas)
  }

  func testEveryGalleryCompositionRendersIncludingExternalSVG() {
    // Scroll the real lazy gallery. A title or a successful compile alone is insufficient.
    let ids = ["Solid", "Boxes", "Motion", "Flex", "Layers", "Timed", "BorderOrder", "FlexOrigin",
               "SeriesTiming", "NestedOrder", "Gradients", "Shadows", "Filters", "Blending", "ClipMask",
               "Backdrop", "Transform3D", "InlineSVG", "ExternalSVG", "FadeTransition", "SlideTransition", "WipeTransition"]
    let gallery = element("gallery-scroll")
    XCTAssertTrue(gallery.waitForExistence(timeout: 30))
    for id in ids {
      let preview = element("preview-\(id)")
      for _ in 0..<45 {
        if preview.exists && preview.isHittable { break }
        gallery.scroll(byDeltaX: 0, deltaY: -240)
      }
      rendered(id)
    }
  }

  func testSettingsAndOpenProjectSheets() {
    let settings = app.buttons["Render Settings"].firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 30))
    settings.click()
    let apply = app.buttons["Apply"].firstMatch
    XCTAssertTrue(apply.waitForExistence(timeout: 10))
    apply.click()
    XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
    app.buttons["Open Project"].firstMatch.click()
    let entry = app.textFields["Entry file"].firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 10))
    app.buttons["Cancel"].firstMatch.click()
    XCTAssertTrue(entry.waitForNonExistence(timeout: 10))
  }

  func testMediaPlaybackAndNestedNavigation() {
    sidebar("Media Composition")
    rendered("MasterComposition")
    app.buttons["Next frame"].click()
    XCTAssertTrue(element("preview-MasterComposition").label.contains("frame 1"))
    app.buttons["Play"].click()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    app.buttons["Pause"].click()
    let nested = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'nested composition'")).firstMatch
    XCTAssertTrue(nested.waitForExistence(timeout: 5))
    nested.doubleClick()
    XCTAssertTrue(app.buttons["Back to parent composition"].waitForExistence(timeout: 10))
    app.buttons["Back to parent composition"].click()
    rendered("MasterComposition")
  }

  func testStudyEditorAndMapsRender() {
    let study = app.buttons["study-Ribbon"]
    XCTAssertTrue(study.waitForExistence(timeout: 30))
    study.click()
    XCTAssertTrue(element("editor-canvas").waitForExistence(timeout: 60))
    editorRendered("Ribbon")
    XCTAssertTrue(element("editor-timeline").exists)
    sidebar("Maps")
    editorRendered("IslandRailway")
    sidebar("Test Film")
    editorRendered("Main")
    sidebar("Visual Editor")
    editorRendered("Cards")
  }

  func testAll3DGalleryPreviewsRender() {
    sidebar("3D Scenes")
    for id in ["CrystalOrbit", "NeonCity", "ProbeFleet", "GeometryLab"] {
      let preview = element("preview-\(id)")
      for _ in 0..<15 {
        if preview.exists && preview.isHittable { break }
        app.scrollViews["scenes3d-scroll"].scroll(byDeltaX: 0, deltaY: -240)
      }
      rendered(id)
    }
  }
}
