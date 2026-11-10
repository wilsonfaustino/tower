import AppKit
import Core
import Observation
import SwiftUI

// Owns the menu bar icon. Left-click toggles the panel, right-click or Control-click shows the context menu.
@MainActor final class StatusItemController: NSObject, NSWindowDelegate {
  let statusItem: NSStatusItem
  let contextMenu: NSMenu
  private let store: QueueStore
  private let openSettings: () -> Void
  private let quit: () -> Void
  private let panel = PanelWindow()
  private var outsideClickMonitor: Any?

  init(store: QueueStore, openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
    self.store = store
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

  @objc func chooseSettings() {
    closePanel()
    openSettings()
  }

  @objc func chooseQuit() {
    quit()
  }

  private func configureContextMenu() {
    let settingsItem = NSMenuItem(title: "Settings…", action: #selector(chooseSettings), keyEquivalent: ",")
    settingsItem.target = self
    let quitItem = NSMenuItem(title: "Quit Tower", action: #selector(chooseQuit), keyEquivalent: "q")
    quitItem.target = self
    contextMenu.items = [settingsItem, .separator(), quitItem]
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

  func showPanel() {
    let hostingController = NSHostingController(
      rootView: PanelView(store: store, close: { [weak self] in self?.closePanel() }, openSettings: openSettings)
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

  private func positionPanel() {
    guard let buttonWindow = statusItem.button?.window, let screen = buttonWindow.screen else { return }
    panel.setFrameOrigin(
      panelOrigin(
        anchor: buttonWindow.frame, panelSize: panel.frame.size, visibleFrame: screen.visibleFrame,
        gap: Theme.Metrics.panelGap))
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
