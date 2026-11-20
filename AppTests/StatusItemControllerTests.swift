import AppKit
import Core
import Testing

@testable import Tower

@MainActor final class ActionRecorder {
  var refreshCount = 0
  var settingsCount = 0
  var quitCount = 0
}

// Waits until the refresh is cancelled, so the store stays refreshing while the test looks at the menu.
private struct PendingTokenProvider: GitHubTokenProvider {
  func token() async throws(SourceFailure) -> String {
    try? await Task.sleep(for: .seconds(60))
    throw .network
  }
}

private struct UnusedTransport: HTTPTransport {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.cancelled) }
}

@MainActor private func withController(_ body: (StatusItemController, ActionRecorder) -> Void) {
  let recorder = ActionRecorder()
  let controller = StatusItemController(
    store: QueueStore(), updateChecker: makeOfflineUpdateChecker(), refresh: { recorder.refreshCount += 1 }, openSettings: { recorder.settingsCount += 1 },
    quit: { recorder.quitCount += 1 })
  body(controller, recorder)
  NSStatusBar.system.removeStatusItem(controller.statusItem)
}

@MainActor struct StatusItemContextMenuTests {
  @Test func menuHasRefreshThenSettingsAndUpdatesThenQuit() {
    withController { controller, _ in
      let items = controller.contextMenu.items
      #expect(items.count == 6)
      #expect(items[0].title == "Refresh")
      #expect(items[0].keyEquivalent == "r")
      #expect(items[1].isSeparatorItem)
      #expect(items[2].title == "Settings…")
      #expect(items[2].keyEquivalent == ",")
      #expect(items[3].title == "Check for Updates…")
      #expect(items[3].keyEquivalent == "u")
      #expect(items[4].isSeparatorItem)
      #expect(items[5].title == "Quit Tower")
      #expect(items[5].keyEquivalent == "q")
    }
  }

  @Test func everyMenuItemHasATemplateIcon() {
    withController { controller, _ in
      for item in controller.contextMenu.items where !item.isSeparatorItem {
        #expect(item.image != nil, "\(item.title) has no icon")
        #expect(item.image?.isTemplate == true, "\(item.title) icon is not a template")
      }
    }
  }

  @Test func refreshItemShowsLoadingWhileRefreshing() {
    withController { controller, _ in
      controller.updateRefreshItem(isRefreshing: true)
      #expect(controller.contextMenu.items[0].title == "Refreshing…")
      #expect(!controller.contextMenu.items[0].isEnabled)
      controller.updateRefreshItem(isRefreshing: false)
      #expect(controller.contextMenu.items[0].title == "Refresh")
      #expect(controller.contextMenu.items[0].isEnabled)
    }
  }

  @Test func openingTheMenuReadsTheStoreRefreshState() async throws {
    let store = QueueStore(
      tokenProvider: PendingTokenProvider(), transport: UnusedTransport(),
      cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("tower-menu-\(UUID().uuidString)"),
      loadJiraSettings: { nil }, loadCircleCISettings: { nil }, loadGitHubOrganizations: { [] },
      defaults: UserDefaults(suiteName: "tower-menu-\(UUID().uuidString)")!)
    let controller = StatusItemController(store: store, updateChecker: makeOfflineUpdateChecker(), refresh: {}, openSettings: {}, quit: {})
    defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
    let menu = controller.contextMenu
    let refreshItem = menu.items[0]

    let refreshTask = Task { await store.refresh() }
    defer { refreshTask.cancel() }
    for _ in 0..<200 where !store.isRefreshing { try await Task.sleep(for: .milliseconds(10)) }
    try #require(store.isRefreshing)
    menu.delegate?.menuNeedsUpdate?(menu)
    #expect(refreshItem.title == "Refreshing…")
    #expect(!refreshItem.isEnabled)

    refreshTask.cancel()
    await refreshTask.value
    menu.delegate?.menuNeedsUpdate?(menu)
    #expect(refreshItem.title == "Refresh")
    #expect(refreshItem.isEnabled)
  }

  @Test func refreshItemCallsRefreshOnce() {
    withController { controller, recorder in
      controller.contextMenu.performActionForItem(at: 0)
      #expect(recorder.refreshCount == 1)
      #expect(recorder.settingsCount == 0)
      #expect(recorder.quitCount == 0)
    }
  }

  @Test func settingsItemCallsOpenSettingsOnce() {
    withController { controller, recorder in
      controller.contextMenu.performActionForItem(at: 2)
      #expect(recorder.settingsCount == 1)
      #expect(recorder.refreshCount == 0)
      #expect(recorder.quitCount == 0)
    }
  }

  @Test func quitItemCallsQuitOnce() {
    withController { controller, recorder in
      controller.contextMenu.performActionForItem(at: 5)
      #expect(recorder.quitCount == 1)
      #expect(recorder.refreshCount == 0)
      #expect(recorder.settingsCount == 0)
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
    let controller = StatusItemController(store: store, updateChecker: makeOfflineUpdateChecker(), refresh: {}, openSettings: {}, quit: {})
    store.menuBarState = .failing(count: 3)
    // The observation re-arms on the next main actor turn.
    for _ in 0..<10 where controller.statusItem.button?.title != "3" { await Task.yield() }
    #expect(controller.statusItem.button?.title == "3")
    #expect(controller.statusItem.button?.accessibilityLabel() == "Tower, 3 items to fix")
    NSStatusBar.system.removeStatusItem(controller.statusItem)
  }
}

@MainActor struct CheckForUpdatesTests {
  @Test func newerVersionOpensThePanelWithTheNotice() async {
    let updateChecker = makeOfflineUpdateChecker { _ in "0.5.0" }
    let controller = StatusItemController(
      store: QueueStore(), updateChecker: updateChecker, refresh: {}, openSettings: {}, quit: {})
    defer {
      controller.closePanel()
      NSStatusBar.system.removeStatusItem(controller.statusItem)
    }
    await controller.checkForUpdates()
    #expect(controller.isPanelVisible)
    #expect(updateChecker.availableVersion == "0.5.0")
  }

  @Test func secondChoiceWhileCheckingIsIgnored() async {
    let fetchCount = LockedCounter()
    let (releaseGate, openGate) = AsyncStream<Void>.makeStream()
    let updateChecker = makeOfflineUpdateChecker { _ in
      fetchCount.increment()
      for await _ in releaseGate {}
      return "0.5.0"
    }
    let controller = StatusItemController(
      store: QueueStore(), updateChecker: updateChecker, refresh: {}, openSettings: {}, quit: {})
    defer {
      controller.closePanel()
      NSStatusBar.system.removeStatusItem(controller.statusItem)
    }
    let firstChoice = Task { await controller.checkForUpdates() }
    while fetchCount.value < 1 { await Task.yield() }
    #expect(controller.isCheckingForUpdates)
    // Returns at once: one check shows one result.
    await controller.checkForUpdates()
    openGate.finish()
    await firstChoice.value
    #expect(!controller.isCheckingForUpdates)
    #expect(fetchCount.value == 1)
  }
}

@MainActor private func withPopover(_ body: (StatusItemController, NSWindow) async -> Void) async {
  let controller = StatusItemController(store: QueueStore(), updateChecker: makeOfflineUpdateChecker(), refresh: {}, openSettings: {}, quit: {})
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
