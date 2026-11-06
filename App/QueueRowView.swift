import Core
import SwiftUI

struct QueueRowView: View {
  let item: QueueItem
  let isSelected: Bool
  let open: () -> Void
  @State private var isHovered = false

  var body: some View {
    HStack(spacing: Theme.Spacing.s) {
      Image(systemName: item.symbol.rawValue)
        .font(.system(size: Theme.Metrics.symbolSize))
        .foregroundStyle(isSelected ? Color.white : symbolColor)
        .frame(width: Theme.Metrics.iconColumn)
      VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
        Text(item.title)
          .font(Theme.Fonts.rowTitle)
          .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
        Text(item.meta)
          .font(Theme.Fonts.rowMeta)
          .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Theme.textSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: Theme.Spacing.s)
      if let badge = item.badge {
        BadgeView(badge: badge, isSelected: isSelected)
      }
      if isHovered && !isSelected {
        Image(systemName: "arrow.up.right")
          .font(.system(size: Theme.Metrics.openArrowSize))
          .foregroundStyle(Theme.textSecondary)
      }
    }
    .padding(.horizontal, Theme.Metrics.rowInset)
    .frame(minHeight: Theme.Metrics.rowMinHeight)
    .background(rowFill, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .onTapGesture(perform: open)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }

  private var rowFill: Color {
    if isSelected { return Color.accentColor }
    return isHovered ? Theme.surfaceHover : .clear
  }

  // Neutral rows stay gray; only failing, urgent and ready rows take the status color.
  private var symbolColor: Color {
    guard let variant = item.badge?.variant, variant != .neutral else { return Theme.textSecondary }
    return Theme.statusText(variant)
  }
}

struct BadgeView: View {
  let badge: Badge
  let isSelected: Bool

  var body: some View {
    Text(badge.text)
      .font(Theme.Fonts.badge)
      .monospacedDigit()
      .foregroundStyle(isSelected ? Color.white : Theme.statusText(badge.variant))
      .padding(.vertical, 2)
      .padding(.horizontal, 7)
      .background(isSelected ? Color.white.opacity(0.22) : Theme.badgeFill(badge.variant), in: Capsule())
  }
}
