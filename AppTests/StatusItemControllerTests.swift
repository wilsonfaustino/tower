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

@MainActor struct StatusItemPanelTests {
  @Test func panelClosesWhenItLosesKeyStatus() {
    withController { controller, _ in
      controller.showPanel()
      #expect(controller.isPanelVisible)
      controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
      #expect(!controller.isPanelVisible)
    }
  }

  @Test func resizeKeepsThePanelOpenAndCloseHidesIt() {
    withController { controller, _ in
      controller.showPanel()
      controller.windowDidResize(Notification(name: NSWindow.didResizeNotification))
      #expect(controller.isPanelVisible)
      controller.closePanel()
      #expect(!controller.isPanelVisible)
    }
  }

  // A click in the list takes key status from the popover, so the panel stays open.
  @Test func popoverKeyLossToThePanelKeepsThePanelOpen() async {
    await withPopover { controller, popover in
      controller.panel.makeKey()
      NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: popover)
      for _ in 0..<10 { await Task.yield() }
      #expect(controller.isPanelVisible)
    }
  }

  @Test func panelKeyLossWithAPopoverToAnotherAppClosesThePanel() async {
    await withPopover { controller, _ in
      await withOtherAppWindow { otherWindow in
        otherWindow.makeKeyAndOrderFront(nil)
        await yieldUntil { !controller.isPanelVisible }
        #expect(!controller.isPanelVisible)
      }
    }
  }

  @Test func buttonFollowsStoreChanges() async {
    let store = QueueStore()
    let controller = StatusItemController(store: store, openSettings: {}, quit: {})
    store.menuBarState = .failing(count: 3)
    // The observation re-arms on the next main actor turn.
    for _ in 0..<10 where controller.statusItem.button?.title != "3" { await Task.yield() }
    #expect(controller.statusItem.button?.title == "3")
    #expect(controller.statusItem.button?.accessibilityLabel() == "Tower, 3 items to fix")
    NSStatusBar.system.removeStatusItem(controller.statusItem)
  }
}

@MainActor private func withPopover(_ body: (StatusItemController, NSWindow) async -> Void) async {
  let controller = StatusItemController(store: QueueStore(), openSettings: {}, quit: {})
  controller.showPanel()
  let popover = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
  popover.isReleasedWhenClosed = false
  controller.panel.addChildWindow(popover, ordered: .above)
  await body(controller, popover)
  controller.closePanel()
  NSStatusBar.system.removeStatusItem(controller.statusItem)
}

// The key loss decision runs on the next main actor turn.
@MainActor private func yieldUntil(_ condition: () -> Bool) async {
  for _ in 0..<10 where !condition() { await Task.yield() }
}

// Stands in for a window of another app taking key status.
@MainActor private func withOtherAppWindow(_ body: (NSWindow) async -> Void) async {
  let otherWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
  otherWindow.isReleasedWhenClosed = false
  await body(otherWindow)
  otherWindow.orderOut(nil)
}
