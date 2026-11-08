import SwiftUI

@main
struct TowerApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  // A SwiftUI app needs one scene. Cmd-, goes to the Settings window that Tower owns, so this one never shows.
  var body: some Scene {
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { appDelegate.showSettings() }
          .keyboardShortcut(",")
      }
    }
  }
}
