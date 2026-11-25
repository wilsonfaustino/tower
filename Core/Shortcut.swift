import Foundation

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let control = KeyModifiers(rawValue: 1 << 0)
  public static let option = KeyModifiers(rawValue: 1 << 1)
  public static let shift = KeyModifiers(rawValue: 1 << 2)
  public static let command = KeyModifiers(rawValue: 1 << 3)
}

// Virtual key codes (kVK_* in Carbon), so Core needs no Carbon import. They name physical keys, not characters.
public enum KeyCode {
  public static let s: UInt16 = 1
  public static let t: UInt16 = 17
  public static let returnKey: UInt16 = 36
  public static let tab: UInt16 = 48
  public static let space: UInt16 = 49
  public static let delete: UInt16 = 51
  public static let escape: UInt16 = 53
  public static let keypadEnter: UInt16 = 76
  public static let forwardDelete: UInt16 = 117
  public static let leftArrow: UInt16 = 123
  public static let rightArrow: UInt16 = 124
  public static let downArrow: UInt16 = 125
  public static let upArrow: UInt16 = 126
}

// One key with its modifiers. `key` is the character the key typed with Command when recorded. Settings shows it,
// and validation checks it against the panel keys that match by character.
public struct KeyCombo: Codable, Hashable, Sendable {
  public var keyCode: UInt16
  public var key: String
  public var modifiers: KeyModifiers

  public init(keyCode: UInt16, key: String, modifiers: KeyModifiers) {
    self.keyCode = keyCode
    self.key = key
    self.modifiers = modifiers
  }

  // The macOS menu order: Control, Option, Shift, Command.
  public var displayText: String {
    let symbols: [(KeyModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
    return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
  }

  public func matches(keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
    self.keyCode == keyCode && self.modifiers == modifiers
  }

  private var keyLabel: String {
    if let label = specialKeyLabels[keyCode] { return label }
    // A dead key can type no character, so the label falls back to the key code.
    return key.isEmpty ? "Key \(keyCode)" : key.uppercased()
  }
}

private let specialKeyLabels: [UInt16: String] = [
  KeyCode.returnKey: "↩", KeyCode.tab: "⇥", KeyCode.space: "Space", KeyCode.delete: "⌫", KeyCode.escape: "Esc",
  KeyCode.keypadEnter: "⌤", KeyCode.forwardDelete: "⌦", KeyCode.leftArrow: "←", KeyCode.rightArrow: "→",
  KeyCode.downArrow: "↓", KeyCode.upArrow: "↑",
  // Function keys F1 to F12.
  122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
  103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
  // Help, Home, Page Up, End, Page Down.
  114: "Help", 115: "↖", 116: "⇞", 119: "↘", 121: "⇟",
]

public enum ShortcutAction: String, CaseIterable, Sendable {
  case openPanel, switchPanelView

  public var title: String {
    switch self {
    case .openPanel: "Open panel"
    case .switchPanelView: "Switch panel view"
    }
  }

  public var defaultCombo: KeyCombo {
    switch self {
    case .openPanel: KeyCombo(keyCode: KeyCode.t, key: "T", modifiers: [.control, .command])
    case .switchPanelView: KeyCombo(keyCode: KeyCode.s, key: "S", modifiers: [.control, .command])
    }
  }

  // Only the global shortcut can be off. The panel shortcut acts only while the panel has focus.
  public var canBeCleared: Bool { self == .openPanel }
}

public enum ShortcutSettings {
  // Stored as JSON data. This string marks a shortcut the user turned off; a missing value means the default.
  private static let clearedValue = "cleared"

  public static func key(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }

  public static func load(_ action: ShortcutAction, defaults: UserDefaults = .standard) -> KeyCombo? {
    let storedValue = defaults.object(forKey: key(action))
    if action.canBeCleared, storedValue as? String == clearedValue { return nil }
    guard let data = storedValue as? Data, let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
      return action.defaultCombo
    }
    return combo
  }

  public static func loadAll(defaults: UserDefaults = .standard) -> [ShortcutAction: KeyCombo?] {
    Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, load($0, defaults: defaults)) })
  }

  // Nil turns the shortcut off, or restores the default for an action that cannot be off.
  public static func save(_ combo: KeyCombo?, for action: ShortcutAction, defaults: UserDefaults = .standard) {
    guard let combo else {
      if action.canBeCleared {
        defaults.set(clearedValue, forKey: key(action))
      } else {
        defaults.removeObject(forKey: key(action))
      }
      return
    }
    defaults.set(try? JSONEncoder().encode(combo), forKey: key(action))
  }

  public static func restoreDefaults(defaults: UserDefaults = .standard) {
    for action in ShortcutAction.allCases { defaults.removeObject(forKey: key(action)) }
  }
}

public enum ShortcutRejection: Equatable, Sendable {
  case needsModifier, reservedByTower, usedBy(ShortcutAction)

  public var message: String {
    switch self {
    case .needsModifier: "Use Control, Option or Command with the key."
    case .reservedByTower: "Tower already uses this key."
    case .usedBy(let action): "\(action.title) already uses this shortcut."
    }
  }
}

// The panel handles these keys with any modifiers, so a shortcut on them would break a panel action.
private let panelKeysWithAnyModifiers: Set<UInt16> = [
  KeyCode.upArrow, KeyCode.downArrow, KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.returnKey, KeyCode.space,
  KeyCode.escape, KeyCode.delete,
]
// Tower matches these by the character the key types in the current layout, so the check uses the same character.
// Whenever Command is down: Cmd-1 and Cmd-2 tabs, Cmd-C copy.
private let charactersWithCommand: Set<String> = ["1", "2", "c"]
// Only with Command alone: Cmd-Z undoes, Cmd-period closes the panel, Cmd-comma opens Settings.
private let charactersWithCommandAlone: Set<String> = ["z", ".", ","]

// Nil means the combo is valid for the action.
public func validateShortcut(
  _ combo: KeyCombo, for action: ShortcutAction, current: [ShortcutAction: KeyCombo?]
) -> ShortcutRejection? {
  guard !combo.modifiers.isDisjoint(with: [.control, .option, .command]) else { return .needsModifier }
  let character = combo.key.lowercased()
  if panelKeysWithAnyModifiers.contains(combo.keyCode)
    || (charactersWithCommand.contains(character) && combo.modifiers.contains(.command))
    || (charactersWithCommandAlone.contains(character) && combo.modifiers == .command)
  {
    return .reservedByTower
  }
  for otherAction in ShortcutAction.allCases where otherAction != action {
    if let otherCombo = current[otherAction] ?? nil, otherCombo.matches(keyCode: combo.keyCode, modifiers: combo.modifiers) {
      return .usedBy(otherAction)
    }
  }
  return nil
}
