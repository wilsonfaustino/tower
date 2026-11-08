import AppKit
import Testing

@testable import Tower

// The injected controller shows a plain view, so tests never build SettingsView, which reads the Keychain.
@MainActor private func makeSettingsWindowController() -> SettingsWindowController {
  SettingsWindowController {
    let viewController = NSViewController()
    viewController.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    return viewController
  }
}

@MainActor struct AppDelegateReopenTests {
  @Test(arguments: [false, true])
  func reopenShowsSettingsAndReturnsFalse(hasVisibleWindows: Bool) {
    let settingsWindowController = makeSettingsWindowController()
    let delegate = AppDelegate(settingsWindowController: settingsWindowController)
    let handled = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: hasVisibleWindows)
    #expect(settingsWindowController.window?.isVisible == true)
    #expect(handled == false)
    settingsWindowController.window?.close()
  }

  @Test func launchUnderTestsAddsNoStatusItemAndDoesNotPoll() {
    let delegate = AppDelegate(settingsWindowController: makeSettingsWindowController())
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    #expect(delegate.store.githubStatus == .idle)
    #expect(!delegate.store.isRefreshing)
  }
}
