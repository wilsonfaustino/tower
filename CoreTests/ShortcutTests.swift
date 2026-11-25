import Core
import Foundation
import Testing

private func makeDefaults() -> UserDefaults {
  UserDefaults(suiteName: "tower-shortcuts-\(UUID().uuidString)")!
}

private let controlCommandK = KeyCombo(keyCode: 40, key: "K", modifiers: [.control, .command])

struct ShortcutDefaultsTests {
  @Test func openPanelDefaultsToControlCommandT() {
    #expect(ShortcutAction.openPanel.defaultCombo == KeyCombo(keyCode: 17, key: "T", modifiers: [.control, .command]))
  }

  @Test func switchPanelViewDefaultsToControlCommandS() {
    #expect(ShortcutAction.switchPanelView.defaultCombo == KeyCombo(keyCode: 1, key: "S", modifiers: [.control, .command]))
  }

  @Test func onlyOpenPanelCanBeCleared() {
    #expect(ShortcutAction.openPanel.canBeCleared)
    #expect(!ShortcutAction.switchPanelView.canBeCleared)
  }
}

struct ShortcutStorageTests {
  @Test(arguments: ShortcutAction.allCases)
  func missingValueLoadsTheDefault(action: ShortcutAction) {
    #expect(ShortcutSettings.load(action, defaults: makeDefaults()) == action.defaultCombo)
  }

  @Test(arguments: ShortcutAction.allCases)
  func savedComboLoadsBack(action: ShortcutAction) {
    let defaults = makeDefaults()
    ShortcutSettings.save(controlCommandK, for: action, defaults: defaults)
    #expect(ShortcutSettings.load(action, defaults: defaults) == controlCommandK)
  }

  @Test func clearedOpenPanelLoadsAsNoShortcut() {
    let defaults = makeDefaults()
    ShortcutSettings.save(nil, for: .openPanel, defaults: defaults)
    #expect(ShortcutSettings.load(.openPanel, defaults: defaults) == nil)
  }

  @Test func clearingSwitchPanelViewKeepsTheDefault() {
    let defaults = makeDefaults()
    ShortcutSettings.save(nil, for: .switchPanelView, defaults: defaults)
    #expect(ShortcutSettings.load(.switchPanelView, defaults: defaults) == ShortcutAction.switchPanelView.defaultCombo)
  }

  @Test func unreadableValueLoadsTheDefault() {
    let defaults = makeDefaults()
    defaults.set(Data("not json".utf8), forKey: ShortcutSettings.key(.openPanel))
    #expect(ShortcutSettings.load(.openPanel, defaults: defaults) == ShortcutAction.openPanel.defaultCombo)
  }

  @Test func restoringDefaultsUndoesAChangeAndAClear() {
    let defaults = makeDefaults()
    ShortcutSettings.save(nil, for: .openPanel, defaults: defaults)
    ShortcutSettings.save(controlCommandK, for: .switchPanelView, defaults: defaults)
    ShortcutSettings.restoreDefaults(defaults: defaults)
    #expect(ShortcutSettings.load(.openPanel, defaults: defaults) == ShortcutAction.openPanel.defaultCombo)
    #expect(ShortcutSettings.load(.switchPanelView, defaults: defaults) == ShortcutAction.switchPanelView.defaultCombo)
  }
}

struct ShortcutDisplayTests {
  @Test func defaultShowsTheMacSymbols() {
    #expect(ShortcutAction.openPanel.defaultCombo.displayText == "⌃⌘T")
  }

  @Test func modifiersShowInTheStandardOrder() {
    let combo = KeyCombo(keyCode: 40, key: "K", modifiers: [.command, .shift, .option, .control])
    #expect(combo.displayText == "⌃⌥⇧⌘K")
  }

  @Test func specialKeysShowTheirSymbol() {
    #expect(KeyCombo(keyCode: 49, key: " ", modifiers: [.control]).displayText == "⌃Space")
    #expect(KeyCombo(keyCode: 36, key: "\r", modifiers: [.command]).displayText == "⌘↩")
    #expect(KeyCombo(keyCode: 122, key: "", modifiers: [.option]).displayText == "⌥F1")
  }
}

struct ShortcutMatchTests {
  @Test func matchesTheSameKeyAndModifiers() {
    #expect(controlCommandK.matches(keyCode: 40, modifiers: [.control, .command]))
  }

  @Test func extraOrMissingModifiersDoNotMatch() {
    #expect(!controlCommandK.matches(keyCode: 40, modifiers: [.control, .command, .shift]))
    #expect(!controlCommandK.matches(keyCode: 40, modifiers: [.command]))
  }

  @Test func otherKeyDoesNotMatch() {
    #expect(!controlCommandK.matches(keyCode: 41, modifiers: [.control, .command]))
  }
}

struct ShortcutValidationTests {
  private let defaultShortcuts = Dictionary(
    uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, Optional($0.defaultCombo)) })

  @Test func comboWithANewKeyIsValid() {
    #expect(validateShortcut(controlCommandK, for: .openPanel, current: defaultShortcuts) == nil)
  }

  @Test func keepingTheSameComboIsValid() {
    #expect(
      validateShortcut(ShortcutAction.openPanel.defaultCombo, for: .openPanel, current: defaultShortcuts) == nil)
  }

  @Test(arguments: [KeyModifiers(), [.shift]])
  func comboNeedsControlOptionOrCommand(modifiers: KeyModifiers) {
    let combo = KeyCombo(keyCode: 40, key: "K", modifiers: modifiers)
    #expect(validateShortcut(combo, for: .openPanel, current: defaultShortcuts) == .needsModifier)
  }

  @Test(arguments: [
    KeyCombo(keyCode: 18, key: "1", modifiers: [.command]),
    KeyCombo(keyCode: 19, key: "2", modifiers: [.control, .command]),
    KeyCombo(keyCode: 8, key: "C", modifiers: [.command]),
    KeyCombo(keyCode: 6, key: "Z", modifiers: [.command]),
    KeyCombo(keyCode: 51, key: "", modifiers: [.command]),
    KeyCombo(keyCode: 36, key: "\r", modifiers: [.command]),
    KeyCombo(keyCode: 125, key: "", modifiers: [.control]),
    KeyCombo(keyCode: 49, key: " ", modifiers: [.option]),
    KeyCombo(keyCode: 53, key: "", modifiers: [.command]),
  ])
  func panelKeysAreReserved(combo: KeyCombo) {
    #expect(validateShortcut(combo, for: .switchPanelView, current: defaultShortcuts) == .reservedByPanel)
  }

  // The panel undoes only on Cmd-Z alone, so other Z combos stay free.
  @Test func controlCommandZIsFree() {
    let combo = KeyCombo(keyCode: 6, key: "Z", modifiers: [.control, .command])
    #expect(validateShortcut(combo, for: .switchPanelView, current: defaultShortcuts) == nil)
  }

  @Test func comboOfTheOtherActionIsTaken() {
    #expect(
      validateShortcut(ShortcutAction.switchPanelView.defaultCombo, for: .openPanel, current: defaultShortcuts)
        == .usedBy(.switchPanelView))
  }

  @Test func clearedOtherActionFreesItsCombo() {
    var shortcuts = defaultShortcuts
    shortcuts[.openPanel] = .some(nil)
    #expect(
      validateShortcut(ShortcutAction.openPanel.defaultCombo, for: .switchPanelView, current: shortcuts) == nil)
  }

  @Test func rejectionsExplainThemselves() {
    #expect(ShortcutRejection.needsModifier.message == "Use Control, Option or Command with the key.")
    #expect(ShortcutRejection.reservedByPanel.message == "The panel already uses this key.")
    #expect(ShortcutRejection.usedBy(.switchPanelView).message == "Switch panel view already uses this shortcut.")
  }
}

struct PanelLayoutToggleTests {
  @Test func toggledSwitchesBetweenTheTwoViews() {
    #expect(PanelLayout.split.toggled == .consolidated)
    #expect(PanelLayout.consolidated.toggled == .split)
  }
}
