import SwiftUI

@main
struct TowerApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  var body: some Scene {
    Settings {
      SettingsView(store: appDelegate.store)
    }
  }
}
