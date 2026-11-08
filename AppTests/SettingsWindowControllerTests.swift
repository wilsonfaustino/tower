import AppKit
import Testing

@testable import Tower

@MainActor struct SettingsWindowControllerTests {
  @Test func showOpensOneSettingsWindowAndReusesIt() {
    let controller = SettingsWindowController {
      let viewController = NSViewController()
      viewController.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
      return viewController
    }
    controller.show()
    let firstWindow = controller.window
    #expect(firstWindow?.isVisible == true)
    #expect(firstWindow?.title == "Tower Settings")
    controller.show()
    #expect(controller.window === firstWindow)
    firstWindow?.close()
    #expect(firstWindow?.isVisible == false)
  }
}
