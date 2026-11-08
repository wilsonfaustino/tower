import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  let store = QueueStore()
  private lazy var settingsWindowController = SettingsWindowController { [store] in
    let hostingController = NSHostingController(rootView: SettingsView(store: store))
    hostingController.sizingOptions = .preferredContentSize
    return hostingController
  }
  private var statusItemController: StatusItemController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Hosted unit tests launch the app. Skip the real icon and polling so tests do not hit the network.
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    statusItemController = StatusItemController(
      store: store, openSettings: { [weak self] in self?.showSettings() }, quit: { NSApp.terminate(nil) })
    store.start()
  }

  func showSettings() {
    settingsWindowController.show()
  }
}
