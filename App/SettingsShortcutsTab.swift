import AppKit
import Core
import SwiftUI

enum ShortcutRecordOutcome: Equatable {
  case cancel, clear, save(KeyCombo), reject(ShortcutRejection)
}

// Esc alone stops recording. Delete alone turns off a shortcut that can be off.
func shortcutRecordOutcome(
  for combo: KeyCombo, action: ShortcutAction, current: [ShortcutAction: KeyCombo?]
) -> ShortcutRecordOutcome {
  if combo.modifiers.isEmpty && combo.keyCode == KeyCode.escape { return .cancel }
  if combo.modifiers.isEmpty && [KeyCode.delete, KeyCode.forwardDelete].contains(combo.keyCode) && action.canBeCleared {
    return .clear
  }
  if let rejection = validateShortcut(combo, for: action, current: current) { return .reject(rejection) }
  return .save(combo)
}

// The fixed panel keys, for reference. They cannot be changed.
private let panelKeyHelp: [(keys: String, text: String)] = [
  ("↑ ↓", "Move the selection"),
  ("⌘↑ ⌘↓", "Select the first or last row"),
  ("↩", "Open the row, or open and close a group"),
  ("⌘↩", "Open the row and keep the panel open"),
  ("← →", "Show Dismiss, or open and close a group"),
  ("Space", "Show PR details"),
  ("⌘1 ⌘2", "Show the Needs you or Waiting tab"),
  ("[ ]", "Filter by the previous or next status"),
  ("0", "Show all statuses"),
  ("⌘C", "Copy the link"),
  ("⌘⌫", "Dismiss the row"),
  ("⌘Z", "Undo the dismissal"),
  ("⌘R", "Refresh"),
  ("⌘,", "Open Settings"),
  ("?", "Show these keys"),
  ("Esc ⌘.", "Close the panel"),
]

private let registrationFailedText = "This shortcut does not work. Another app uses it."

// The combo a key press records. With Command down, a layout like Dvorak-QWERTY gives the character that the panel's
// Cmd keys see. Without it, the plain character, so Shift shows as ⇧ and not as a shifted symbol.
func recordedCombo(from event: NSEvent) -> KeyCombo {
  KeyCombo(
    keyCode: event.keyCode,
    key: event.characters(byApplyingModifiers: event.modifierFlags.contains(.command) ? .command : []) ?? "",
    modifiers: keyModifiers(from: event.modifierFlags))
}

// The Shortcuts tab state: the saved shortcuts, the action that records, and the last rejection.
@MainActor @Observable final class ShortcutRecorder {
  private(set) var shortcuts: [ShortcutAction: KeyCombo?]
  private(set) var recordingAction: ShortcutAction?
  private(set) var rejectedAction: ShortcutAction?
  private(set) var rejection: ShortcutRejection?
  @ObservationIgnored let globalHotKey: GlobalHotKey
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var keyMonitor: Any?
  // The Settings window. The recorder listens only to its keys and stops when it loses focus.
  @ObservationIgnored private weak var recordingWindow: NSWindow?

  init(globalHotKey: GlobalHotKey, defaults: UserDefaults = .standard) {
    self.globalHotKey = globalHotKey
    self.defaults = defaults
    shortcuts = ShortcutSettings.loadAll(defaults: defaults)
  }

  var hasOnlyDefaults: Bool { ShortcutAction.allCases.allSatisfy { shortcuts[$0] == $0.defaultCombo } }

  func recorderText(_ action: ShortcutAction) -> String {
    recordingAction == action ? "Type a shortcut" : savedText(action)
  }

  func savedText(_ action: ShortcutAction) -> String {
    (shortcuts[action] ?? nil)?.displayText ?? "Off"
  }

  // One caption line per row, so the tab keeps its height. The Settings window does not shrink cleanly.
  func caption(_ action: ShortcutAction) -> String {
    if recordingAction == action {
      return action.canBeCleared ? "Press Esc to cancel, or Delete to turn it off." : "Press Esc to cancel."
    }
    if rejectedAction == action, let rejection { return rejection.message }
    if action == .openPanel && globalHotKey.registrationFailed { return registrationFailedText }
    switch action {
    case .openPanel: return "Opens or closes the panel from any app."
    case .switchPanelView: return "Switches the view while the panel is open."
    }
  }

  // The hot key pauses, so the current Open panel shortcut reaches the recorder instead of the panel.
  // Without a window the recorder could not tell its keys apart or notice focus loss, so it does not start.
  func start(_ action: ShortcutAction, in window: NSWindow?) {
    stop()
    guard let window else { return }
    rejectedAction = nil
    rejection = nil
    recordingAction = action
    recordingWindow = window
    globalHotKey.setPaused(true)
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
      let combo = recordedCombo(from: event)
      let isRecordingWindow = MainActor.assumeIsolated { event.window != nil && event.window === window }
      guard isRecordingWindow, let self else { return event }
      MainActor.assumeIsolated { self.record(combo) }
      return nil
    }
  }

  func record(_ combo: KeyCombo) {
    guard let action = recordingAction else { return }
    switch shortcutRecordOutcome(for: combo, action: action, current: shortcuts) {
    case .cancel: break
    case .clear: ShortcutSettings.save(nil, for: action, defaults: defaults)
    case .save(let newCombo): ShortcutSettings.save(newCombo, for: action, defaults: defaults)
    case .reject(let newRejection):
      rejectedAction = action
      rejection = newRejection
    }
    shortcuts = ShortcutSettings.loadAll(defaults: defaults)
    stop()
  }

  func stop() {
    guard recordingAction != nil else { return }
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
    recordingAction = nil
    recordingWindow = nil
    globalHotKey.setPaused(false)
  }

  func windowDidResignKey(_ window: NSWindow?) {
    if let recordingWindow, window === recordingWindow { stop() }
  }

  func clear(_ action: ShortcutAction) {
    stop()
    ShortcutSettings.save(nil, for: action, defaults: defaults)
    shortcuts = ShortcutSettings.loadAll(defaults: defaults)
    rejectedAction = nil
    globalHotKey.update()
  }

  func restoreDefaults() {
    stop()
    ShortcutSettings.restoreDefaults(defaults: defaults)
    shortcuts = ShortcutSettings.loadAll(defaults: defaults)
    rejectedAction = nil
    globalHotKey.update()
  }
}

struct SettingsShortcutsTab: View {
  @State private var recorder: ShortcutRecorder

  init(globalHotKey: GlobalHotKey, defaults: UserDefaults = .standard) {
    _recorder = State(initialValue: ShortcutRecorder(globalHotKey: globalHotKey, defaults: defaults))
  }

  var body: some View {
    SettingsTabLayout {
      ForEach(ShortcutAction.allCases, id: \.self) { action in
        shortcutRow(action)
      }
      SettingsRow(label: "") {
        Button("Restore Defaults", action: recorder.restoreDefaults)
          .disabled(recorder.hasOnlyDefaults)
      }
      SettingsDivider()
      SettingsRow(label: "In the panel") {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.xs) {
          ForEach(panelKeyHelp, id: \.keys) { entry in
            GridRow {
              Text(entry.keys)
              Text(entry.text).foregroundStyle(Theme.textSecondary)
            }
          }
        }
        SettingsCaption(text: "These keys cannot be changed.")
      }
    }
    .onDisappear(perform: recorder.stop)
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
      recorder.windowDidResignKey(notification.object as? NSWindow)
    }
  }

  private func shortcutRow(_ action: ShortcutAction) -> some View {
    SettingsRow(label: action.title) {
      HStack(spacing: Theme.Spacing.s) {
        Button {
          recorder.recordingAction == action ? recorder.stop() : recorder.start(action, in: NSApp.keyWindow)
        } label: {
          Text(recorder.recorderText(action)).frame(minWidth: 120)
        }
        .accessibilityLabel("\(action.title) shortcut")
        .accessibilityValue(recorder.recordingAction == action ? "Recording" : recorder.savedText(action))
        .accessibilityHint("Records a new shortcut")
        if action.canBeCleared, recorder.shortcuts[action] ?? nil != nil {
          Button("Turn Off") { recorder.clear(action) }
        }
        // Stays in sight while the caption shows a rejection, without changing the tab height.
        if action == .openPanel && recorder.globalHotKey.registrationFailed {
          Image(SettingsSymbol.failed.rawValue)
            .foregroundStyle(Theme.statusText(.failing))
            .help(registrationFailedText)
            .accessibilityLabel(registrationFailedText)
        }
      }
      SettingsCaption(text: recorder.caption(action))
    }
  }
}
