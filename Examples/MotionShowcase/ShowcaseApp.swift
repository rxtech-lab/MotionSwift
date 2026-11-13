import AppKit
import MotionSwiftUI
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
    // Finder launches with a minimal PATH. Export's audio mixer uses our bundled FFmpeg.
    if let helpers = Bundle.main.privateFrameworksURL?.deletingLastPathComponent()
      .appendingPathComponent("Helpers"), FileManager.default.fileExists(atPath: helpers.path) {
      setenv("PATH", "\(helpers.path):/usr/bin:/bin:/usr/sbin:/sbin", 1)
    }
    // `swift run` launches a bare executable; promote it to a regular foreground app.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    // Activation registers a bare SwiftPM executable with the Dock and replaces its icon.
    // Apply our fallback on the next main-loop turn, after that registration finishes.
    DispatchQueue.main.async {
      guard Bundle.main.bundleURL.pathExtension != "app",
        let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns", subdirectory: "Media"),
        let icon = NSImage(contentsOf: url) else { return }
      NSApp.applicationIconImage = icon
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum ShowcaseDefaults {
  /// The MotionSwift checkout: `MOTIONSWIFT_HOME`, else the checkout this file was built from.
  static var repository: URL {
    if let home = ProcessInfo.processInfo.environment["MOTIONSWIFT_HOME"] {
      return URL(fileURLWithPath: home)
    }
    if let resources = Bundle.main.resourceURL?.appendingPathComponent("ShowcaseProjects"),
      FileManager.default.fileExists(atPath: resources.path) { return resources }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  static var project: URL { repository.appendingPathComponent("tests/compositions") }
  static let entry = "src/index.ts"

  /// Distributed apps compile in JavaScriptCore; no unsigned extracted toolchains are needed.
  static func source(project: URL, entry: String) -> MotionSource {
    if Bundle.main.bundleURL.pathExtension == "app" {
      return .portable(project: project, entry: entry)
    }
    return .project(repository: repository, project: project, entry: entry)
  }
}
