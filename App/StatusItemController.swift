import AppKit
import Core
import Observation
import SwiftUI

// Owns the menu bar icon. Left-click toggles the panel, right-click or Control-click shows the context menu.
@MainActor final class StatusItemController: NSObject, NSWindowDelegate, NSMenuDelegate {
  let statusItem: NSStatusItem
  let contextMenu: NSMenu
  private let store: QueueStore
  private let updateChecker: UpdateChecker
  private let refresh: () -> Void
  private let openSettings: () -> Void
  private let quit: () -> Void
  let panel = PanelWindow()
  private var outsideClickMonitor: Any?
  private(set) var isCheckingForUpdates = false
  private lazy var refreshItem = menuItem(
    "Refresh", symbol: .refresh, action: #selector(chooseRefresh), keyEquivalent: "r")

  init(
    store: QueueStore, updateChecker: UpdateChecker, refresh: @escaping () -> Void,
    openSettings: @escaping () -> Void, quit: @escaping () -> Void
  ) {
    self.store = store
    self.updateChecker = updateChecker
    self.refresh = refresh
    self.openSettings = openSettings
    self.quit = quit
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    contextMenu = NSMenu()
    super.init()
    statusItem.autosaveName = "TowerStatusItem"
    configureContextMenu()
    configureButton()
    panel.delegate = self
    panel.onCancel = { [weak self] in self?.closePanel() }
    NotificationCenter.default.addObserver(
      self, selector: #selector(childWindowDidResignKey), name: NSWindow.didResignKeyNotification, object: nil)
    trackMenuBarState()
  }

  func apply(_ state: MenuBarState) {
    guard let button = statusItem.button else { return }
    button.image = NSImage(named: state.imageName)
    button.image?.isTemplate = true
    if let countText = state.countText {
      button.attributedTitle = NSAttributedString(
        string: countText, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)])
      button.imagePosition = .imageLeading
    } else {
      button.title = ""
      button.imagePosition = .imageOnly
    }
    button.setAccessibilityLabel(state.accessibilityLabel)
  }

  @objc func chooseRefresh() {
    refresh()
  }

  @objc func chooseSettings() {
    closePanel()
    openSettings()
  }

  // A newer version opens the panel, where the notice and Update button sit.
  @objc func chooseCheckForUpdates() {
    Task { await checkForUpdates() }
  }

  // A second choice while a check runs does nothing, so one check shows one alert.
  func checkForUpdates() async {
    guard !isCheckingForUpdates else { return }
    isCheckingForUpdates = true
    defer { isCheckingForUpdates = false }
    switch await updateChecker.checkNow() {
    case .newer:
      if !panel.isVisible { showPanel() }
    case .upToDate(let currentVersion):
      showAlert(message: "Tower is up to date.", information: "Version \(currentVersion) is the newest version.")
    case .failed:
      showAlert(message: "Could not check for updates.", information: "Try again later.")
    }
  }

  private func showAlert(message: String, information: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = information
    NSApp.activate()
    alert.runModal()
  }

  @objc func chooseQuit() {
    quit()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    updateRefreshItem(isRefreshing: store.isRefreshing)
  }

  func updateRefreshItem(isRefreshing: Bool) {
    refreshItem.title = isRefreshing ? "Refreshing…" : "Refresh"
    refreshItem.isEnabled = !isRefreshing
  }

  private func configureContextMenu() {
    // The Refresh item sets its own enabled state.
    contextMenu.autoenablesItems = false
    contextMenu.delegate = self
    contextMenu.items = [
      refreshItem,
      .separator(),
      menuItem("Settings…", symbol: .settings, action: #selector(chooseSettings), keyEquivalent: ","),
      menuItem(
        "Check for Updates…", symbol: .checkForUpdates, action: #selector(chooseCheckForUpdates), keyEquivalent: "u"),
      .separator(),
      menuItem("Quit Tower", symbol: .quit, action: #selector(chooseQuit), keyEquivalent: "q"),
    ]
  }

  private func menuItem(_ title: String, symbol: MenuSymbol, action: Selector, keyEquivalent: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = self
    item.image = NSImage(named: symbol.rawValue)
    item.image?.isTemplate = true
    return item
  }

  private func configureButton() {
    guard let button = statusItem.button else { return }
    button.target = self
    button.action = #selector(handleButtonClick)
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  // Re-arms on every change, so the button follows the store for the life of the app.
  private func trackMenuBarState() {
    let state = withObservationTracking { store.menuBarState } onChange: { [weak self] in
      Task { @MainActor in self?.trackMenuBarState() }
    }
    apply(state)
  }

  @objc private func handleButtonClick() {
    guard let event = NSApp.currentEvent else { return }
    switch statusItemClickAction(eventType: event.type, modifierFlags: event.modifierFlags, isPanelVisible: panel.isVisible) {
    case .showMenu: showContextMenu()
    case .closePanel: closePanel()
    case .showPanel: showPanel()
    }
  }

  // Assigning the menu only while it shows keeps left-click free for the panel.
  private func showContextMenu() {
    closePanel()
    statusItem.menu = contextMenu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  var isPanelVisible: Bool { panel.isVisible }

  func toggleFromHotKey() {
    switch hotKeyAction(isPanelVisible: panel.isVisible) {
    case .showPanel: showPanel(selectsFirstRow: true)
    case .closePanel: closePanel()
    case .showMenu: break
    }
  }

  func showPanel(selectsFirstRow: Bool = false) {
    let hostingController = NSHostingController(
      rootView: PanelView(
        store: store, updateChecker: updateChecker, close: { [weak self] in self?.closePanel() },
        openSettings: openSettings, selectsFirstRow: selectsFirstRow)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel)))
    hostingController.sizingOptions = .preferredContentSize
    panel.contentViewController = hostingController
    positionPanel()
    panel.makeKeyAndOrderFront(nil)
    statusItem.button?.highlight(true)
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.closePanel() }
    }
  }

  func closePanel() {
    guard panel.isVisible else { return }
    panel.orderOut(nil)
    panel.contentViewController = nil
    statusItem.button?.highlight(false)
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    outsideClickMonitor = nil
  }

  // A status item hidden behind the notch or by the user has no screen, so the panel goes to the main screen.
  private func positionPanel() {
    let anchor: NSRect
    let visibleFrame: NSRect
    if let buttonWindow = statusItem.button?.window, let screen = buttonWindow.screen {
      anchor = buttonWindow.frame
      visibleFrame = screen.visibleFrame
    } else if let screen = NSScreen.main {
      anchor = fallbackPanelAnchor(visibleFrame: screen.visibleFrame)
      visibleFrame = screen.visibleFrame
    } else {
      return
    }
    panel.setFrameOrigin(
      panelOrigin(anchor: anchor, panelSize: panel.frame.size, visibleFrame: visibleFrame, gap: Theme.Metrics.panelGap))
  }

  func windowDidResize(_ notification: Notification) {
    positionPanel()
    panel.invalidateShadow()
  }

  // Covers a click in another Tower window and Cmd-Tab to another app.
  func windowDidResignKey(_ notification: Notification) {
    handleKeyLoss(resignedChild: nil)
  }

  // A row popover is a child window of the panel, so its key loss does not reach windowDidResignKey.
  @objc private func childWindowDidResignKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window.parent === panel else { return }
    handleKeyLoss(resignedChild: window)
  }

  private func handleKeyLoss(resignedChild: NSWindow?) {
    guard resignedChild != nil || panel.childWindows?.isEmpty == false else {
      closePanel()
      return
    }
    // Inside the resign notification the new key window is not set yet, so decide on the next main actor turn.
    Task { @MainActor [weak self] in
      guard let self, panel.isVisible else { return }
      switch panelKeyChangeAction(
        newKeyWindow: NSApp.keyWindow, panel: panel, resignedChildIsVisible: resignedChild?.isVisible)
      {
      case .keepOpen: break
      case .focusPanel: panel.makeKey()
      case .closePanel: closePanel()
      }
    }
  }
}

enum StatusItemClickAction {
  case showMenu
  case closePanel
  case showPanel
}

func statusItemClickAction(
  eventType: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags, isPanelVisible: Bool
) -> StatusItemClickAction {
  if eventType == .rightMouseUp || modifierFlags.contains(.control) { return .showMenu }
  return isPanelVisible ? .closePanel : .showPanel
}

// Top-left of the panel sits under the icon, kept inside the screen.
func panelOrigin(anchor: NSRect, panelSize: NSSize, visibleFrame: NSRect, gap: CGFloat) -> NSPoint {
  let originX = min(max(anchor.minX, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
  let originY = anchor.minY - gap - panelSize.height
  return NSPoint(x: originX, y: originY)
}

// The top right corner of the screen, where the status items sit.
func fallbackPanelAnchor(visibleFrame: NSRect) -> NSRect {
  NSRect(x: visibleFrame.maxX, y: visibleFrame.maxY, width: 0, height: 0)
}

enum PanelKeyChangeAction {
  case keepOpen
  case focusPanel
  case closePanel
}

// Runs after key status settles. resignedChildIsVisible is nil when the panel itself resigned key,
// otherwise it tells whether the child window (a row popover) is still on screen.
func panelKeyChangeAction(newKeyWindow: NSWindow?, panel: NSWindow, resignedChildIsVisible: Bool?)
  -> PanelKeyChangeAction
{
  if let newKeyWindow, newKeyWindow === panel || newKeyWindow.parent === panel { return .keepOpen }
  if newKeyWindow == nil && resignedChildIsVisible == false { return .focusPanel }
  return .closePanel
}
