import AppKit
import SwiftUI

/// MotionSwift showcase: previews Remotion-style TSX compositions natively with `MotionSwiftUI`.
///
/// Run from the checkout after `make bootstrap`:
/// `swift run motionswift-showcase`
@main
struct ShowcaseApp: App {
  @NSApplicationDelegateAdaptor private var delegate: ShowcaseAppDelegate

  var body: some Scene {
    WindowGroup("MotionSwift Showcase") {
      ContentView()
        .frame(minWidth: 860, minHeight: 540)
    }
    .windowToolbarStyle(.unified)
  }
}

final class ShowcaseAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // `swift run` launches a bare executable; promote it to a regular foreground app.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum ShowcaseDefaults {
  /// The MotionSwift checkout: `MOTIONSWIFT_HOME`, else the checkout this file was built from.
  static var repository: URL {
    if let home = ProcessInfo.processInfo.environment["MOTIONSWIFT_HOME"] {
      return URL(fileURLWithPath: home)
    }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  static var project: URL { repository.appendingPathComponent("tests/compositions") }
  static let entry = "src/index.ts"
}
