import AppKit
import Carbon.HIToolbox
import Core
import Observation

// The Open panel shortcut works like a click on the status item: it opens a closed panel and closes an open one.
func hotKeyAction(isPanelVisible: Bool) -> StatusItemClickAction {
  isPanelVisible ? .closePanel : .showPanel
}

// Caps Lock and the Fn flag that arrow and function keys carry are not part of a shortcut.
func keyModifiers(from flags: NSEvent.ModifierFlags) -> KeyModifiers {
  var modifiers: KeyModifiers = []
  if flags.contains(.control) { modifiers.insert(.control) }
  if flags.contains(.option) { modifiers.insert(.option) }
  if flags.contains(.shift) { modifiers.insert(.shift) }
  if flags.contains(.command) { modifiers.insert(.command) }
  return modifiers
}

func carbonModifiers(for modifiers: KeyModifiers) -> UInt32 {
  var carbonFlags = 0
  if modifiers.contains(.control) { carbonFlags |= controlKey }
  if modifiers.contains(.option) { carbonFlags |= optionKey }
  if modifiers.contains(.shift) { carbonFlags |= shiftKey }
  if modifiers.contains(.command) { carbonFlags |= cmdKey }
  return UInt32(carbonFlags)
}

// Registers the Open panel shortcut with the system through the Carbon hot key API, which needs no Accessibility
// permission. Settings calls `update()` after a change and pauses it while the recorder listens for keys.
@MainActor @Observable final class GlobalHotKey {
  // True when the system refused the saved shortcut, for example because another app holds it.
  private(set) var registrationFailed = false
  @ObservationIgnored var onPress: (() -> Void)?
  @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
  @ObservationIgnored private var handlerRef: EventHandlerRef?
  @ObservationIgnored private var isPaused = false
  @ObservationIgnored private let defaults: UserDefaults
  // "TOWR" as a four-character code. Carbon needs an ID for each hot key; Tower registers only one.
  private static let signature: OSType = 0x544F_5752

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func start() {
    guard handlerRef == nil else { return }
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetEventDispatcherTarget(), hotKeyHandler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    update()
  }

  func update() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    hotKeyRef = nil
    guard handlerRef != nil, !isPaused, let combo = ShortcutSettings.load(.openPanel, defaults: defaults) else {
      registrationFailed = false
      return
    }
    let hotKeyId = EventHotKeyID(signature: Self.signature, id: 1)
    // Exclusive, so a shortcut that another app already holds fails here and Settings can say so.
    let status = RegisterEventHotKey(
      UInt32(combo.keyCode), carbonModifiers(for: combo.modifiers), hotKeyId, GetEventDispatcherTarget(),
      OptionBits(kEventHotKeyExclusive), &hotKeyRef)
    registrationFailed = status != noErr
  }

  // While paused, the recorder gets the current shortcut as a plain key press.
  func setPaused(_ paused: Bool) {
    isPaused = paused
    update()
  }

  fileprivate func handlePress() {
    onPress?()
  }
}

// Carbon calls this on the main thread with the GlobalHotKey passed to InstallEventHandler.
private let hotKeyHandler: EventHandlerUPP = { _, _, userData in
  guard let userData else { return OSStatus(eventNotHandledErr) }
  let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
  MainActor.assumeIsolated { hotKey.handlePress() }
  return noErr
}
