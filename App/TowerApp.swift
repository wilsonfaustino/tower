import SwiftUI

@main
struct TowerApp: App {
  var body: some Scene {
    MenuBarExtra {
      Text("Tower")
        .padding()
    } label: {
      Image("MenuBarCab")
    }
    .menuBarExtraStyle(.window)
  }
}
