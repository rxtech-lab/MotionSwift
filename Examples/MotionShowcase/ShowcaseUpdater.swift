import Combine
import Foundation
import Sparkle

/// Sparkle owns the native update dialogs, download progress and installation UI.
@MainActor
final class ShowcaseUpdater: ObservableObject {
  @Published private(set) var canCheckForUpdates = false
  private var controller: SPUStandardUpdaterController?
  private var observation: AnyCancellable?

  init() {
    // Bare SwiftPM executables and local packages without a signing key cannot update.
    guard Bundle.main.bundleURL.pathExtension == "app",
      let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
      Data(base64Encoded: key)?.count == 32 else { return }
    let controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    self.controller = controller
    observation = controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.canCheckForUpdates = $0 }
  }

  func checkForUpdates() { controller?.checkForUpdates(nil) }
}
