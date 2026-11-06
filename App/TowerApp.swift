import Core
import SwiftUI

@main
struct TowerApp: App {
  @State private var store = QueueStore()

  var body: some Scene {
    MenuBarExtra {
      PanelView(store: store)
    } label: {
      MenuBarLabel(state: store.menuBarState)
        .task { store.start() }
    }
    .menuBarExtraStyle(.window)
    Settings {
      SettingsView(store: store)
    }
  }
}

private struct MenuBarLabel: View {
  let state: MenuBarState

  var body: some View {
    HStack(spacing: 2) {
      Image(state.imageName)
      if let countText = state.countText {
        Text(countText).monospacedDigit()
      }
    }
  }
}
