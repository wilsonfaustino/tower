import AppKit

// Borderless panels refuse key status by default, and the row keyboard handlers need it.
final class PanelWindow: NSPanel {
  var onCancel: (() -> Void)?

  init() {
    super.init(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    isFloatingPanel = true
    level = .popUpMenu
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    hidesOnDeactivate = false
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
  }

  override var canBecomeKey: Bool { true }

  override func cancelOperation(_ sender: Any?) {
    onCancel?()
  }
}
