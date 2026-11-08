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
  private var openSettingsOverride: (() -> Void)?

  override init() {
    super.init()
  }

  init(openSettings: @escaping () -> Void) {
    openSettingsOverride = openSettings
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Hosted unit tests launch the app. Skip the real icon and polling so tests do not hit the network.
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    statusItemController = StatusItemController(
      store: store, openSettings: { [weak self] in self?.showSettings() }, quit: { NSApp.terminate(nil) })
    store.start()
  }

  func showSettings() {
    if let openSettingsOverride {
      openSettingsOverride()
    } else {
      settingsWindowController.show()
    }
  }

  // The icon can hide behind the notch or be hidden by the user, so launching Tower again opens Settings.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    showSettings()
    return false
  }
}
