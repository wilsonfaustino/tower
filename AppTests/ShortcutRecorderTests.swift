import AppKit
import Core
import SwiftUI
import Testing

@testable import Tower

@MainActor private func makeDefaults() -> UserDefaults {
  UserDefaults(suiteName: "tower-recorder-\(UUID().uuidString)")!
}

@MainActor private func makeWindow() -> NSWindow {
  NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
}

private let optionCommandK = KeyCombo(keyCode: 40, key: "k", modifiers: [.option, .command])

@MainActor struct ShortcutRecorderTests {
  private let defaults = makeDefaults()
  private let window = makeWindow()

  private func makeRecorder() -> ShortcutRecorder {
    ShortcutRecorder(globalHotKey: GlobalHotKey(defaults: defaults), defaults: defaults)
  }

  @Test func showsTheDefaultsWithTheirCaptions() {
    let recorder = makeRecorder()
    #expect(recorder.recorderText(.openPanel) == "⌃⌘T")
    #expect(recorder.recorderText(.switchPanelView) == "⌃⌘S")
    #expect(recorder.caption(.openPanel) == "Opens or closes the panel from any app.")
    #expect(recorder.caption(.switchPanelView) == "Switches the view while the panel is open.")
    #expect(recorder.hasOnlyDefaults)
  }

  @Test func recordingShowsAPromptAndAHint() {
    let recorder = makeRecorder()
    recorder.start(.openPanel, in: window)
    #expect(recorder.recordingAction == .openPanel)
    #expect(recorder.recorderText(.openPanel) == "Type a shortcut")
    #expect(recorder.caption(.openPanel) == "Press Esc to cancel, or Delete to turn it off.")
    recorder.start(.switchPanelView, in: window)
    #expect(recorder.recordingAction == .switchPanelView)
    #expect(recorder.caption(.switchPanelView) == "Press Esc to cancel.")
    recorder.stop()
    #expect(recorder.recordingAction == nil)
  }

  @Test func recordingDoesNotStartWithoutAWindow() {
    let recorder = makeRecorder()
    recorder.start(.openPanel, in: nil)
    #expect(recorder.recordingAction == nil)
  }

  @Test func aValidComboIsSavedAndRecordingStops() {
    let recorder = makeRecorder()
    recorder.start(.openPanel, in: window)
    recorder.record(optionCommandK)
    #expect(recorder.recordingAction == nil)
    #expect(recorder.recorderText(.openPanel) == "⌥⌘K")
    #expect(ShortcutSettings.load(.openPanel, defaults: defaults) == optionCommandK)
    #expect(!recorder.hasOnlyDefaults)
  }

  @Test func aTakenComboShowsWhyAndKeepsTheShortcut() {
    let recorder = makeRecorder()
    recorder.start(.openPanel, in: window)
    recorder.record(ShortcutAction.switchPanelView.defaultCombo)
    #expect(recorder.caption(.openPanel) == "Switch panel view already uses this shortcut.")
    #expect(recorder.caption(.switchPanelView) == "Switches the view while the panel is open.")
    #expect(recorder.recorderText(.openPanel) == "⌃⌘T")
    recorder.start(.openPanel, in: window)
    #expect(recorder.caption(.openPanel) == "Press Esc to cancel, or Delete to turn it off.")
  }

  @Test func escapeCancelsWithoutAChange() {
    let recorder = makeRecorder()
    recorder.start(.switchPanelView, in: window)
    recorder.record(KeyCombo(keyCode: KeyCode.escape, key: "", modifiers: []))
    #expect(recorder.recordingAction == nil)
    #expect(recorder.hasOnlyDefaults)
  }

  @Test func deleteTurnsOpenPanelOff() {
    let recorder = makeRecorder()
    recorder.start(.openPanel, in: window)
    recorder.record(KeyCombo(keyCode: KeyCode.delete, key: "", modifiers: []))
    #expect(recorder.recorderText(.openPanel) == "Off")
    #expect(ShortcutSettings.load(.openPanel, defaults: defaults) == nil)
  }

  @Test func aKeyPressWithoutRecordingDoesNothing() {
    let recorder = makeRecorder()
    recorder.record(optionCommandK)
    #expect(recorder.hasOnlyDefaults)
  }

  @Test func turnOffAndRestoreDefaults() {
    let recorder = makeRecorder()
    recorder.clear(.openPanel)
    #expect(recorder.savedText(.openPanel) == "Off")
    recorder.restoreDefaults()
    #expect(recorder.savedText(.openPanel) == "⌃⌘T")
    #expect(recorder.hasOnlyDefaults)
  }

  @Test func onlyTheRecordingWindowLosingFocusStopsRecording() {
    let recorder = makeRecorder()
    recorder.start(.openPanel, in: window)
    recorder.windowDidResignKey(makeWindow())
    #expect(recorder.recordingAction == .openPanel)
    recorder.windowDidResignKey(window)
    #expect(recorder.recordingAction == nil)
  }

  @Test func aKeyEventBecomesACombo() throws {
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.option, .command, .capsLock], timestamp: 0,
        windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false,
        keyCode: 40))
    let combo = recordedCombo(from: event)
    #expect(combo.keyCode == 40)
    #expect(combo.modifiers == [.option, .command])
  }

  @Test func theTabRenders() {
    let hostingView = NSHostingView(rootView: SettingsShortcutsTab(globalHotKey: GlobalHotKey(defaults: defaults), defaults: defaults))
    hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 500)
    hostingView.layoutSubtreeIfNeeded()
    #expect(hostingView.fittingSize.height > 0)
  }
}

// F19 with every modifier, so the test hot key cannot clash with a real one.
private let testHotKey = KeyCombo(keyCode: 80, key: "", modifiers: [.control, .option, .shift, .command])

@MainActor struct GlobalHotKeyTests {
  @Test func registersAndReportsAConflictWithAnotherExclusiveHolder() {
    let defaults = makeDefaults()
    ShortcutSettings.save(testHotKey, for: .openPanel, defaults: defaults)
    let holder = GlobalHotKey(defaults: defaults)
    let latecomer = GlobalHotKey(defaults: defaults)
    holder.start()
    latecomer.start()
    #expect(!holder.registrationFailed)
    #expect(latecomer.registrationFailed)
    // The recorder pauses the holder, so the shortcut is free again.
    holder.setPaused(true)
    latecomer.update()
    #expect(!latecomer.registrationFailed)
    latecomer.setPaused(true)
  }

  @Test func aShortcutThatIsOffRegistersNothing() {
    let defaults = makeDefaults()
    ShortcutSettings.save(nil, for: .openPanel, defaults: defaults)
    let hotKey = GlobalHotKey(defaults: defaults)
    hotKey.start()
    #expect(!hotKey.registrationFailed)
  }

  @Test func pressRunsTheAction() {
    let hotKey = GlobalHotKey(defaults: makeDefaults())
    var pressCount = 0
    hotKey.onPress = { pressCount += 1 }
    hotKey.handlePress()
    #expect(pressCount == 1)
  }
}
