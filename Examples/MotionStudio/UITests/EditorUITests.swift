import XCTest

/// Drives the editor like a user on iPhone/iPad: tap to select, drag to move, resize from a handle,
/// undo, and measure the preview budget. `-uiTesting` resets the sample project on launch.
final class EditorUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
  }

  private var canvas: XCUIElement { app.descendants(matching: .any)["editor-canvas"] }
  private var notice: XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved' OR label BEGINSWITH 'Undid'")).firstMatch
  }

  private func openSampleEditor() {
    if !canvas.waitForExistence(timeout: 5) {
      // Compact width starts in the sidebar.
      app.buttons["Sample"].firstMatch.tap()
    }
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    // Let the first frame render.
    sleep(2)
  }

  /// Composition (640×360) coordinates inside the canvas, which letterboxes the picture.
  private func point(_ x: Double, _ y: Double) -> XCUICoordinate {
    let frame = canvas.frame
    let width = min(frame.width, frame.height * 640 / 360)
    let height = width * 360 / 640
    let origin = CGPoint(x: frame.midX - width / 2, y: frame.midY - height / 2)
    return app.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: origin.x + x / 640 * width, dy: origin.y + y / 360 * height))
  }

  func testSelectDragUndo() {
    openSampleEditor()
    // The first card spans (48, 48)–(268, 188).
    point(150, 110).tap()
    XCTAssertTrue(app.descendants(matching: .any)["resize-bottomTrailing"].waitForExistence(timeout: 5))
    point(150, 110).press(forDuration: 0.1, thenDragTo: point(210, 150))
    XCTAssertTrue(notice.waitForExistence(timeout: 15))
    XCTAssertTrue(notice.label.contains("Saved Move"), notice.label)
    attach("after-drag")

    let undo = app.buttons["Undo"].firstMatch
    XCTAssertTrue(undo.waitForExistence(timeout: 5) && undo.isEnabled)
    undo.tap()
    let redo = app.buttons["Redo"].firstMatch
    let undone = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: redo)
    wait(for: [undone], timeout: 15)
    attach("after-undo")
  }

  func testResizeFromHandle() {
    openSampleEditor()
    point(150, 110).tap()
    let handle = app.descendants(matching: .any)["resize-bottomTrailing"]
    XCTAssertTrue(handle.waitForExistence(timeout: 5))
    handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(forDuration: 0.1, thenDragTo: point(330, 230))
    XCTAssertTrue(notice.waitForExistence(timeout: 15))
    XCTAssertTrue(notice.label.contains("Saved Resize"), notice.label)
    attach("after-resize")
  }

  func testMeasurePreviewBudget() {
    openSampleEditor()
    let menu = app.buttons["studio-menu"].firstMatch
    if !menu.exists {
      // Compact width: the menu lives on the sidebar screen.
      app.navigationBars.buttons.firstMatch.tap()
    }
    XCTAssertTrue(menu.waitForExistence(timeout: 5))
    menu.tap()
    app.buttons["Preview Budget…"].firstMatch.tap()
    let measure = app.buttons["Measure"].firstMatch
    measure.tap()
    let status = app.staticTexts["budget-status"].firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 180))
    XCTAssertEqual(status.label, "Measured 3 compositions")
    attach("preview-budget")
  }

  private func attach(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
