import Core
import SwiftUI

struct QueueSectionView: View {
  let section: QueueSection
  let selectedItemId: String?
  @Binding var popoverItemId: String?
  let open: (QueueItem) -> Void
  let showDetails: (QueueItem) -> Void
  let copyLink: (QueueItem) -> Void

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
          copyLink: { copyLink(item) })
          .id(item.id)
          // The leading point puts the arrow at the vertical middle of the row, with the popover left of the panel.
          .popover(isPresented: isPopoverPresented(for: item), attachmentAnchor: .point(.leading), arrowEdge: .leading) {
            if let details = item.details {
              PullRequestPopoverView(details: details, open: { open(item) }, copyLink: { copyLink(item) })
            }
          }
      }
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
