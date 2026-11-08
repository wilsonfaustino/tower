import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  let store = QueueStore()
  private var statusItemController: StatusItemController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Hosted unit tests launch the app. Skip the real icon and polling so tests do not hit the network.
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    statusItemController = StatusItemController(
      store: store, openSettings: SettingsOpener.open, quit: { NSApp.terminate(nil) })
    store.start()
  }
}

// An agent app is not active while the panel shows, so bring it forward or Settings opens behind other windows.
enum SettingsOpener {
  @MainActor static func open() {
    EnvironmentValues().openSettings()
    NSApp.activate()
    Task { @MainActor in
      let settingsWindow = NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }
      settingsWindow?.makeKeyAndOrderFront(nil)
      settingsWindow?.orderFrontRegardless()
    }
  }
}
