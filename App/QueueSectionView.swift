import Core
import SwiftUI

struct QueueSectionView: View {
  let section: QueueSection
  let selectedItemId: String?
  let open: (QueueItem) -> Void

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
        QueueRowView(item: item, isSelected: item.id == selectedItemId) { open(item) }
          .id(item.id)
      }
    }
  }
}
