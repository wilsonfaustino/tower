import Core
import SwiftUI

// Board 3 on the design canvas, "PR row popover".
struct PullRequestPopoverView: View {
  let details: PullRequestDetails
  let open: () -> Void
  let copyLink: () -> Void
  // The popover is its own key window, so the panel's key handlers do not see these keys.
  let handleInput: (PanelInput) -> KeyPress.Result
  @State private var isShowingCopied = false
  @FocusState private var isFocused: Bool
  @AccessibilityFocusState private var isTitleAccessibilityFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Metrics.popoverSpacing) {
      Text(details.title)
        .font(Theme.Fonts.popoverTitle)
        .foregroundStyle(Theme.textPrimary)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityFocused($isTitleAccessibilityFocused)
      Text("\(details.reference) · \(details.repository)")
        .font(Theme.Fonts.rowMeta)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
      HStack(alignment: .firstTextBaseline, spacing: Theme.Metrics.popoverSpacing) {
        Text(details.additionsText()).foregroundStyle(Theme.statusText(.ready))
        Text(details.deletionsText()).foregroundStyle(Theme.statusText(.failing))
        Text("lines").font(Theme.Fonts.rowMeta).foregroundStyle(Theme.textSecondary)
      }
      .font(Theme.Fonts.popoverDiff)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(details.diffAccessibilityPhrase)
      HStack(spacing: Theme.Spacing.s) {
        Spacer()
        Button(action: copy) {
          if isShowingCopied {
            Label("Copied", systemImage: "checkmark").labelStyle(.titleAndIcon)
          } else {
            Text("Copy link")
          }
        }
        Button("Open in browser", action: open).keyboardShortcut(.defaultAction)
      }
    }
    .padding(Theme.Metrics.popoverPadding)
    .frame(width: Theme.Metrics.popoverWidth)
    .focusable()
    .focusEffectDisabled()
    .focused($isFocused)
    .onAppear {
      isFocused = true
      isTitleAccessibilityFocused = true
    }
    .onKeyPress(.space) { handleInput(.space) }
    .onKeyPress(.upArrow) { handleInput(.upArrow) }
    .onKeyPress(.downArrow) { handleInput(.downArrow) }
    .onKeyPress(keys: ["c"]) { press in
      guard press.modifiers.contains(.command) else { return .ignored }
      return handleInput(.copy)
    }
    .task(id: isShowingCopied) {
      guard isShowingCopied else { return }
      try? await Task.sleep(for: .seconds(1.5))
      isShowingCopied = false
    }
  }

  private func copy() {
    copyLink()
    isShowingCopied = true
  }
}
