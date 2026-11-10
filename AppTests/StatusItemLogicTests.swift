import AppKit
import Testing

@testable import Tower

struct StatusItemClickActionTests {
  @Test(arguments: [false, true])
  func rightClickShowsTheMenu(isPanelVisible: Bool) {
    #expect(statusItemClickAction(eventType: .rightMouseUp, modifierFlags: [], isPanelVisible: isPanelVisible) == .showMenu)
  }

  @Test(arguments: [false, true])
  func controlClickShowsTheMenu(isPanelVisible: Bool) {
    #expect(statusItemClickAction(eventType: .leftMouseUp, modifierFlags: .control, isPanelVisible: isPanelVisible) == .showMenu)
  }

  @Test func leftClickTogglesThePanel() {
    #expect(statusItemClickAction(eventType: .leftMouseUp, modifierFlags: [], isPanelVisible: false) == .showPanel)
    #expect(statusItemClickAction(eventType: .leftMouseUp, modifierFlags: [], isPanelVisible: true) == .closePanel)
  }

  @Test func otherModifiersStillToggleThePanel() {
    #expect(statusItemClickAction(eventType: .leftMouseUp, modifierFlags: .command, isPanelVisible: false) == .showPanel)
  }
}

struct PanelOriginTests {
  private let visibleFrame = NSRect(x: 0, y: 0, width: 1512, height: 944)
  private let panelSize = NSSize(width: 380, height: 300)

  @Test func panelSitsUnderTheIconWithTheGap() {
    let anchor = NSRect(x: 800, y: 950, width: 30, height: 24)
    let origin = panelOrigin(anchor: anchor, panelSize: panelSize, visibleFrame: visibleFrame, gap: 4)
    #expect(origin == NSPoint(x: 800, y: 950 - 4 - 300))
  }

  @Test func panelMovesLeftToStayInsideTheRightEdge() {
    let anchor = NSRect(x: 1400, y: 950, width: 30, height: 24)
    let origin = panelOrigin(anchor: anchor, panelSize: panelSize, visibleFrame: visibleFrame, gap: 4)
    #expect(origin == NSPoint(x: 1512 - 380, y: 646))
  }

  @Test func panelStaysInsideTheLeftEdge() {
    let secondScreen = NSRect(x: 1512, y: 0, width: 1920, height: 1080)
    let anchor = NSRect(x: 1500, y: 1086, width: 30, height: 24)
    let origin = panelOrigin(anchor: anchor, panelSize: panelSize, visibleFrame: secondScreen, gap: 4)
    #expect(origin.x == 1512)
  }
}

@MainActor struct PanelWindowTests {
  @Test func panelCanBecomeKeyAndEscapeCallsOnCancel() {
    let panel = PanelWindow()
    var cancelCount = 0
    panel.onCancel = { cancelCount += 1 }
    panel.cancelOperation(nil)
    #expect(panel.canBecomeKey)
    #expect(cancelCount == 1)
  }
}

@MainActor struct PanelKeyChangeActionTests {
  private func panelWithChild() -> (panel: PanelWindow, child: NSWindow) {
    let panel = PanelWindow()
    let child = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    panel.addChildWindow(child, ordered: .above)
    return (panel, child)
  }

  @Test func panelTakingKeyBackKeepsItOpen() {
    let (panel, _) = panelWithChild()
    #expect(panelKeyChangeAction(newKeyWindow: panel, panel: panel, resignedChildIsVisible: true) == .keepOpen)
  }

  @Test func popoverTakingKeyFromThePanelKeepsItOpen() {
    let (panel, child) = panelWithChild()
    #expect(panelKeyChangeAction(newKeyWindow: child, panel: panel, resignedChildIsVisible: nil) == .keepOpen)
  }

  @Test func closedPopoverWithNoNewKeyWindowGivesKeyBackToThePanel() {
    let (panel, _) = panelWithChild()
    #expect(panelKeyChangeAction(newKeyWindow: nil, panel: panel, resignedChildIsVisible: false) == .focusPanel)
  }

  @Test func openPopoverLosingKeyClosesThePanel() {
    let (panel, _) = panelWithChild()
    #expect(panelKeyChangeAction(newKeyWindow: nil, panel: panel, resignedChildIsVisible: true) == .closePanel)
  }

  @Test func anotherWindowTakingKeyClosesThePanel() {
    let (panel, _) = panelWithChild()
    let settingsWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    #expect(panelKeyChangeAction(newKeyWindow: settingsWindow, panel: panel, resignedChildIsVisible: nil) == .closePanel)
    #expect(panelKeyChangeAction(newKeyWindow: settingsWindow, panel: panel, resignedChildIsVisible: false) == .closePanel)
  }

  @Test func panelLosingKeyToNothingClosesIt() {
    let (panel, _) = panelWithChild()
    #expect(panelKeyChangeAction(newKeyWindow: nil, panel: panel, resignedChildIsVisible: nil) == .closePanel)
  }
}
