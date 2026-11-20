import AppKit
import Testing

@testable import Tower

@MainActor struct SettingsTabViewControllerTests {
  @Test func opensOnTheRequestedTabWithOneTabPerArea() {
    let controller = SettingsTabViewController(store: makeSettingsStore(), updateChecker: makeOfflineUpdateChecker(), initialTab: .jira) { _ in }
    #expect(controller.tabViewItems.map(\.label) == ["General", "GitHub", "Jira", "CircleCI", "About"])
    #expect(controller.selectedTabViewItemIndex == SettingsTab.allCases.firstIndex(of: .jira))
    _ = controller.view
    #expect(controller.selectedTabViewItemIndex == SettingsTab.allCases.firstIndex(of: .jira))
  }

  @Test func reportsTheSelectedTab() {
    var selectedTabs: [SettingsTab] = []
    let controller = SettingsTabViewController(store: makeSettingsStore(), updateChecker: makeOfflineUpdateChecker(), initialTab: .general) { selectedTabs.append($0) }
    // The tab view reports a selection only after its view loads, as it does in the Settings window.
    _ = controller.view
    controller.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: .about)!
    #expect(selectedTabs.last == .about)
  }

  @Test func keepsTheWindowTitle() {
    let windowController = SettingsWindowController {
      SettingsTabViewController(store: makeSettingsStore(), updateChecker: makeOfflineUpdateChecker(), initialTab: .circleci) { _ in }
    }
    windowController.show()
    #expect(windowController.window?.title == "Tower Settings")
    windowController.window?.close()
  }
}

// A temporary cache and defaults, so the store never reads the real app data.
@MainActor private func makeSettingsStore() -> QueueStore {
  QueueStore(
    cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("tower-settings-\(UUID().uuidString)"),
    defaults: UserDefaults(suiteName: "tower-settings-\(UUID().uuidString)")!)
}
