import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  let store = QueueStore(notifier: AppDelegate.notifier)
  // Hosted unit tests and demo mode (except notify) get no notifier, so they never post or ask for permission.
  private static let notifier: UserNotificationNotifier? =
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
      && (!DemoLaunch.isActive || DemoLaunch.postsNotifications)
    ? UserNotificationNotifier() : nil
  // Settings opens on the last tab for the app run, so the window builds each time from this value.
  private var settingsTab = SettingsTab.general
  private lazy var settingsWindowController = injectedSettingsWindowController ?? SettingsWindowController { [weak self, store] in
    SettingsTabViewController(store: store, initialTab: self?.settingsTab ?? .general) { self?.settingsTab = $0 }
  }
  private var statusItemController: StatusItemController?
  private let injectedSettingsWindowController: SettingsWindowController?

  override init() {
    injectedSettingsWindowController = nil
    super.init()
  }

  init(settingsWindowController: SettingsWindowController) {
    injectedSettingsWindowController = settingsWindowController
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Hosted unit tests launch the app. Skip the real icon and polling so tests do not hit the network.
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    statusItemController = StatusItemController(
      store: store, refresh: { [store] in Task { await store.refresh() } },
      openSettings: { [weak self] in self?.showSettings() }, quit: { NSApp.terminate(nil) })
    // macOS shows the prompt only once. Later calls return the saved answer.
    if !NotificationSettingsKeys.enabledKinds().isEmpty { Self.notifier?.requestAuthorization() }
    store.start()
  }

  func showSettings() {
    settingsWindowController.show()
  }

  // The icon can hide behind the notch or be hidden by the user, so launching Tower again opens Settings.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    showSettings()
    return false
  }
}
