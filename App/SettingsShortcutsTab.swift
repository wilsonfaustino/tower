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
  ("↩", "Open the row, or open and close a group"),
  ("⌘↩", "Open the row and keep the panel open"),
  ("← →", "Show Dismiss, or open and close a group"),
  ("Space", "Show PR details"),
  ("⌘1 ⌘2", "Show the Needs you or Waiting tab"),
  ("⌘C", "Copy the link"),
  ("⌘⌫", "Dismiss the row"),
  ("⌘Z", "Undo the dismissal"),
  ("⌘,", "Open Settings"),
  ("Esc ⌘.", "Close the panel"),
]

private let registrationFailedText = "This shortcut does not work. Another app uses it."

struct SettingsShortcutsTab: View {
  let globalHotKey: GlobalHotKey
  @State private var shortcuts = ShortcutSettings.loadAll()
  @State private var recordingAction: ShortcutAction?
  @State private var rejectedAction: ShortcutAction?
  @State private var rejection: ShortcutRejection?
  @State private var keyMonitor: Any?
  // The Settings window. The recorder listens only to its keys and stops when it loses focus.
  @State private var recordingWindow: NSWindow?

  var body: some View {
    SettingsTabLayout {
      ForEach(ShortcutAction.allCases, id: \.self) { action in
        shortcutRow(action)
      }
      SettingsRow(label: "") {
        Button("Restore Defaults", action: restoreDefaults)
          .disabled(ShortcutAction.allCases.allSatisfy { shortcuts[$0] == $0.defaultCombo })
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
    .onDisappear(perform: stopRecording)
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
      if let recordingWindow, notification.object as? NSWindow === recordingWindow { stopRecording() }
    }
  }

  private func shortcutRow(_ action: ShortcutAction) -> some View {
    SettingsRow(label: action.title) {
      HStack(spacing: Theme.Spacing.s) {
        Button {
          recordingAction == action ? stopRecording() : startRecording(action)
        } label: {
          Text(recorderText(action)).frame(minWidth: 120)
        }
        .accessibilityLabel("\(action.title) shortcut")
        .accessibilityValue(recordingAction == action ? "Recording" : savedText(action))
        .accessibilityHint("Records a new shortcut")
        if action.canBeCleared, shortcuts[action] ?? nil != nil {
          Button("Turn Off") { clear(action) }
        }
        // Stays in sight while the caption shows a rejection, without changing the tab height.
        if action == .openPanel && globalHotKey.registrationFailed {
          Image(SettingsSymbol.failed.rawValue)
            .foregroundStyle(Theme.statusText(.failing))
            .help(registrationFailedText)
            .accessibilityLabel(registrationFailedText)
        }
      }
      SettingsCaption(text: caption(action))
    }
  }

  private func recorderText(_ action: ShortcutAction) -> String {
    recordingAction == action ? "Type a shortcut" : savedText(action)
  }

  private func savedText(_ action: ShortcutAction) -> String {
    (shortcuts[action] ?? nil)?.displayText ?? "Off"
  }

  // One caption line per row, so the tab keeps its height. The Settings window does not shrink cleanly.
  private func caption(_ action: ShortcutAction) -> String {
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
  private func startRecording(_ action: ShortcutAction) {
    stopRecording()
    // Without a key window the recorder could not tell its keys apart or notice focus loss, so it does not start.
    guard let settingsWindow = NSApp.keyWindow else { return }
    rejectedAction = nil
    rejection = nil
    recordingAction = action
    recordingWindow = settingsWindow
    globalHotKey.setPaused(true)
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak settingsWindow] event in
      let combo = KeyCombo(
        keyCode: event.keyCode,
        // With Command down, a layout like Dvorak-QWERTY gives the character that the panel's Cmd keys see.
        // Without it, the plain character, so Shift shows as ⇧ and not as a shifted symbol.
        key: event.characters(byApplyingModifiers: event.modifierFlags.contains(.command) ? .command : []) ?? "",
        modifiers: keyModifiers(from: event.modifierFlags))
      let isRecordingWindow = MainActor.assumeIsolated { event.window != nil && event.window === settingsWindow }
      guard isRecordingWindow else { return event }
      MainActor.assumeIsolated { record(combo, for: action) }
      return nil
    }
  }

  private func record(_ combo: KeyCombo, for action: ShortcutAction) {
    switch shortcutRecordOutcome(for: combo, action: action, current: shortcuts) {
    case .cancel: break
    case .clear: ShortcutSettings.save(nil, for: action)
    case .save(let newCombo): ShortcutSettings.save(newCombo, for: action)
    case .reject(let newRejection):
      rejectedAction = action
      rejection = newRejection
    }
    shortcuts = ShortcutSettings.loadAll()
    stopRecording()
  }

  private func stopRecording() {
    guard let keyMonitor else { return }
    NSEvent.removeMonitor(keyMonitor)
    self.keyMonitor = nil
    recordingAction = nil
    recordingWindow = nil
    globalHotKey.setPaused(false)
  }

  private func clear(_ action: ShortcutAction) {
    stopRecording()
    ShortcutSettings.save(nil, for: action)
    shortcuts = ShortcutSettings.loadAll()
    rejectedAction = nil
    globalHotKey.update()
  }

  private func restoreDefaults() {
    stopRecording()
    ShortcutSettings.restoreDefaults()
    shortcuts = ShortcutSettings.loadAll()
    rejectedAction = nil
    globalHotKey.update()
  }
}
