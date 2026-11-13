import Core
import SwiftUI

struct QueueSectionView: View {
  let section: QueueSection
  let selectedItemId: String?
  var expandedItemIds: Set<String> = []
  // The pinned Watch section shows only the first rows, then a "+N more" line.
  var visibleItemLimit = Int.max
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
        Text("\(rowCount(of: section))").font(Theme.Fonts.sectionCount)
      }
      .foregroundStyle(Theme.textSecondary)
      .padding(.horizontal, Theme.Metrics.rowInset)
      .padding(.top, Theme.Spacing.s)
      .padding(.bottom, Theme.Spacing.xs)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(section.items.prefix(visibleItemLimit)) { item in
          rowView(for: item)
          if expandedItemIds.contains(item.id) {
            ForEach(item.children) { child in
              rowView(for: child).padding(.leading, Theme.Metrics.childIndent)
            }
          }
        }
        if section.items.count > visibleItemLimit {
          Text("+\(section.items.count - visibleItemLimit) more")
            .font(Theme.Fonts.rowMeta)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Metrics.rowInset)
            .padding(.vertical, Theme.Spacing.xs)
        }
      }
      .padding(Theme.Spacing.xxs)
      .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
      .overlay(RoundedRectangle(cornerRadius: Theme.Radius.banner).strokeBorder(Theme.cardStroke, lineWidth: 1))
    }
    // Gives VoiceOver focus back to the row that opened the popover when it closes.
    .onChange(of: popoverItemId) { oldValue, newValue in
      guard newValue == nil, let oldValue,
        section.items.contains(where: { $0.id == oldValue || $0.children.contains { $0.id == oldValue } })
      else { return }
      accessibilityFocusedItemId = oldValue
    }
  }

  private func rowView(for item: QueueItem) -> some View {
    QueueRowView(
      item: item, isSelected: item.id == selectedItemId, isExpanded: expandedItemIds.contains(item.id),
      open: { open(item) }, showDetails: { showDetails(item) }, copyLink: { copyLink(item) },
      dismiss: { dismiss(item) })
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

  private func isPopoverPresented(for item: QueueItem) -> Binding<Bool> {
    Binding(
      get: { popoverItemId == item.id },
      set: { isPresented in
        if !isPresented, popoverItemId == item.id { popoverItemId = nil }
      })
  }
}
