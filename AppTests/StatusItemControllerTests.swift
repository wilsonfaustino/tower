import AppKit
import Core
import Testing

@testable import Tower

@MainActor final class ActionRecorder {
  var settingsCount = 0
  var quitCount = 0
}

@MainActor private func withController(_ body: (StatusItemController, ActionRecorder) -> Void) {
  let recorder = ActionRecorder()
  let controller = StatusItemController(
    store: QueueStore(), openSettings: { recorder.settingsCount += 1 }, quit: { recorder.quitCount += 1 })
  body(controller, recorder)
  NSStatusBar.system.removeStatusItem(controller.statusItem)
}

@MainActor struct StatusItemContextMenuTests {
  @Test func menuHasSettingsThenQuit() {
    withController { controller, _ in
      let items = controller.contextMenu.items
      #expect(items.count == 3)
      #expect(items[0].title == "Settings…")
      #expect(items[0].keyEquivalent == ",")
      #expect(items[1].isSeparatorItem)
      #expect(items[2].title == "Quit Tower")
      #expect(items[2].keyEquivalent == "q")
    }
  }

  @Test func quitItemCallsQuitOnce() {
    withController { controller, recorder in
      controller.contextMenu.performActionForItem(at: 2)
      #expect(recorder.quitCount == 1)
      #expect(recorder.settingsCount == 0)
    }
  }

  @Test func settingsItemCallsOpenSettingsOnce() {
    withController { controller, recorder in
      controller.contextMenu.performActionForItem(at: 0)
      #expect(recorder.settingsCount == 1)
      #expect(recorder.quitCount == 0)
    }
  }
}

@MainActor struct StatusItemButtonTests {
  @Test(arguments: [MenuBarState.normal, .urgent(count: 2), .failing(count: 1)])
  func buttonFollowsMenuBarState(state: MenuBarState) throws {
    withController { controller, _ in
      controller.apply(state)
      let button = controller.statusItem.button
      #expect(button?.image?.name() == state.imageName)
      #expect(button?.image?.isTemplate == true)
      #expect(button?.title == (state.countText ?? ""))
      #expect(button?.accessibilityLabel() == state.accessibilityLabel)
    }
  }
}
