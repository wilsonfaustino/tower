import AppKit
import Testing

@testable import Tower

@MainActor struct AppDelegateReopenTests {
  @Test(arguments: [false, true])
  func reopenOpensSettingsOnceAndReturnsFalse(hasVisibleWindows: Bool) {
    var settingsCount = 0
    let delegate = AppDelegate(openSettings: { settingsCount += 1 })
    let handled = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: hasVisibleWindows)
    #expect(settingsCount == 1)
    #expect(handled == false)
  }
}
