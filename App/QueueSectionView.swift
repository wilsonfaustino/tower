import Core
import SwiftUI

struct QueueSectionView: View {
  let section: QueueSection
  let selectedItemId: String?
  @Binding var popoverItemId: String?
  let open: (QueueItem) -> Void
  let showDetails: (QueueItem) -> Void
  let copyLink: (QueueItem) -> Void
  let dismiss: (QueueItem) -> Void
  let handlePopoverInput: (PanelInput) -> KeyPress.Result
  @AccessibilityFocusState private var accessibilityFocusedItemId: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: Theme.Spacing.s) {
        Text(section.kind.title).font(Theme.Fonts.section)
        Text("\(section.items.count)").font(Theme.Fonts.sectionCount)
      }
      .foregroundStyle(Theme.textSecondary)
      .padding(.horizontal, Theme.Metrics.rowInset)
      .padding(.top, Theme.Spacing.s)
      .padding(.bottom, Theme.Spacing.xs)
      ForEach(section.items) { item in
        QueueRowView(
          item: item, isSelected: item.id == selectedItemId, open: { open(item) }, showDetails: { showDetails(item) },
          copyLink: { copyLink(item) }, dismiss: { dismiss(item) })
          .id(item.id)
          .accessibilityFocused($accessibilityFocusedItemId, equals: item.id)
          // The leading point puts the arrow at the vertical middle of the row, with the popover left of the panel.
          .popover(isPresented: isPopoverPresented(for: item), attachmentAnchor: .point(.leading), arrowEdge: .leading) {
            if let details = item.details {
              PullRequestPopoverView(
                details: details, open: { open(item) }, copyLink: { copyLink(item) }, handleInput: handlePopoverInput)
            }
          }
      }
    }
    // Gives VoiceOver focus back to the row that opened the popover when it closes.
    .onChange(of: popoverItemId) { oldValue, newValue in
      guard newValue == nil, let oldValue, section.items.contains(where: { $0.id == oldValue }) else { return }
      accessibilityFocusedItemId = oldValue
    }
  }

  private func isPopoverPresented(for item: QueueItem) -> Binding<Bool> {
    Binding(
      get: { popoverItemId == item.id },
      set: { isPresented in
        if !isPresented, popoverItemId == item.id { popoverItemId = nil }
      })
  }
}
