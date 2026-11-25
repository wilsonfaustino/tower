import AppKit
import Carbon.HIToolbox
import Core
import Testing

@testable import Tower

struct KeyModifierConversionTests {
  @Test func eventFlagsBecomeKeyModifiersWithoutCapsLockOrFunction() {
    let flags: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .capsLock, .function]
    #expect(keyModifiers(from: flags) == [.control, .option, .shift, .command])
  }

  @Test func keyModifiersBecomeCarbonModifiers() {
    #expect(carbonModifiers(for: [.control, .command]) == UInt32(controlKey | cmdKey))
    #expect(carbonModifiers(for: [.option, .shift]) == UInt32(optionKey | shiftKey))
    #expect(carbonModifiers(for: []) == 0)
  }
}

struct ShortcutRecordOutcomeTests {
  private let defaultShortcuts = Dictionary(
    uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, Optional($0.defaultCombo)) })
  private let escape = KeyCombo(keyCode: KeyCode.escape, key: "", modifiers: [])
  private let delete = KeyCombo(keyCode: KeyCode.delete, key: "", modifiers: [])

  @Test(arguments: ShortcutAction.allCases)
  func escapeAloneCancels(action: ShortcutAction) {
    #expect(shortcutRecordOutcome(for: escape, action: action, current: defaultShortcuts) == .cancel)
  }

  @Test func deleteAloneTurnsOffOpenPanel() {
    #expect(shortcutRecordOutcome(for: delete, action: .openPanel, current: defaultShortcuts) == .clear)
  }

  @Test func deleteAloneIsRejectedForSwitchPanelView() {
    #expect(
      shortcutRecordOutcome(for: delete, action: .switchPanelView, current: defaultShortcuts) == .reject(.needsModifier))
  }

  @Test func validComboIsSaved() {
    let combo = KeyCombo(keyCode: 40, key: "k", modifiers: [.option, .command])
    #expect(shortcutRecordOutcome(for: combo, action: .openPanel, current: defaultShortcuts) == .save(combo))
  }

  @Test func takenComboIsRejected() {
    #expect(
      shortcutRecordOutcome(for: ShortcutAction.openPanel.defaultCombo, action: .switchPanelView, current: defaultShortcuts)
        == .reject(.usedBy(.openPanel)))
  }
}
