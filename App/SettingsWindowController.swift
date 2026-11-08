import AppKit

// Tower owns its Settings window, because SwiftUI opens the Settings scene only from a view inside a scene.
@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
  private let makeContent: () -> NSViewController
  private(set) var window: NSWindow?

  init(makeContent: @escaping () -> NSViewController) {
    self.makeContent = makeContent
  }

  // An agent app is not active while the panel shows, so bring it forward or Settings opens behind other windows.
  func show() {
    let settingsWindow = window ?? makeWindow()
    window = settingsWindow
    if settingsWindow.contentViewController == nil {
      settingsWindow.contentViewController = makeContent()
      settingsWindow.center()
    }
    NSApp.activate()
    settingsWindow.makeKeyAndOrderFront(nil)
    settingsWindow.orderFrontRegardless()
  }

  private func makeWindow() -> NSWindow {
    let settingsWindow = NSWindow(
      contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
    settingsWindow.title = "Tower Settings"
    settingsWindow.isReleasedWhenClosed = false
    settingsWindow.delegate = self
    return settingsWindow
  }

  // Dropping the view on close runs its onDisappear, which saves the tokens, and the next open reads fresh values.
  func windowWillClose(_ notification: Notification) {
    window?.contentViewController = nil
  }
}
