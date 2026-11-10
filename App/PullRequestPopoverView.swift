import Core
import SwiftUI

// Board 3 on the design canvas, "PR row popover".
struct PullRequestPopoverView: View {
  let details: PullRequestDetails
  let open: () -> Void
  let copyLink: () -> Void
  @State private var isShowingCopied = false

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Metrics.popoverSpacing) {
      Text(details.title)
        .font(Theme.Fonts.popoverTitle)
        .foregroundStyle(Theme.textPrimary)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Label("Copied", systemImage: "checkmark")
          } else {
            Text("Copy link")
          }
        }
        Button("Open in browser", action: open).keyboardShortcut(.defaultAction)
      }
    }
    .padding(Theme.Metrics.popoverPadding)
    .frame(width: Theme.Metrics.popoverWidth)
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
