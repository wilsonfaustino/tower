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
    if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
      showContextMenu()
    } else if panel.isVisible {
      closePanel()
    } else {
      showPanel()
    }
  }

  // Assigning the menu only while it shows keeps left-click free for the panel.
  private func showContextMenu() {
    closePanel()
    statusItem.menu = contextMenu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  private func showPanel() {
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

  // Top-left of the panel sits under the icon, kept inside the screen.
  private func positionPanel() {
    guard let buttonWindow = statusItem.button?.window, let screen = buttonWindow.screen else { return }
    let anchor = buttonWindow.frame
    let size = panel.frame.size
    let visibleFrame = screen.visibleFrame
    let originX = min(max(anchor.minX, visibleFrame.minX), visibleFrame.maxX - size.width)
    let originY = anchor.minY - Theme.Metrics.panelGap - size.height
    panel.setFrameOrigin(NSPoint(x: originX, y: originY))
  }

  func windowDidResize(_ notification: Notification) {
    positionPanel()
    panel.invalidateShadow()
  }

  func windowDidResignKey(_ notification: Notification) {
    closePanel()
  }
}
