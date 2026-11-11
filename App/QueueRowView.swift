import Core
import SwiftUI

struct QueueRowView: View {
  let item: QueueItem
  let isSelected: Bool
  let open: () -> Void
  let showDetails: () -> Void
  let copyLink: () -> Void
  let dismiss: () -> Void
  @State private var isHovered = false

  // PR rows and failed pipeline rows get a context menu; other rows keep their single action.
  var body: some View {
    if item.details != nil {
      row
        .contextMenu {
          Button("Show Details", action: showDetails).keyboardShortcut(.space, modifiers: [])
          Button("Open in Browser", action: open)
          Button("Copy Link", action: copyLink).keyboardShortcut("c")
        }
        .accessibilityAction(named: "Show details", showDetails)
        .accessibilityAction(named: "Copy link", copyLink)
    } else if item.dismissal != nil {
      row
        .contextMenu {
          Button("Open in Browser", action: open)
          Button("Dismiss", action: dismiss).keyboardShortcut(.delete)
        }
        .accessibilityAction(named: "Dismiss", dismiss)
    } else {
      row
    }
  }

  private var row: some View {
    HStack(spacing: Theme.Spacing.s) {
      Image(systemName: item.symbol.rawValue)
        .font(.system(size: Theme.Metrics.symbolSize))
        .foregroundStyle(isSelected ? Theme.selectionText : symbolColor)
        .frame(width: Theme.Metrics.iconColumn)
        // SF Symbol descriptions ("show", "divide") would mislead; the badge text carries the meaning.
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
        titleText
          .font(Theme.Fonts.rowTitle)
          .foregroundStyle(isSelected ? Theme.selectionText : Theme.textPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
        HStack(spacing: 6) {
          Text(item.meta)
            .font(Theme.Fonts.rowMeta)
            .foregroundStyle(isSelected ? Theme.selectionText.opacity(0.85) : Theme.textSecondary)
            .lineLimit(1)
          if let strip = item.strip, !strip.isEmpty {
            StatusStripView(strip: strip, isSelected: isSelected)
          }
        }
      }
      Spacer(minLength: Theme.Spacing.s)
      if let badge = item.badge {
        BadgeView(badge: badge, isSelected: isSelected)
      }
      // Always in the layout so hover does not change the row width or the title truncation.
      Image(systemName: "arrow.up.right")
        .font(.system(size: Theme.Metrics.openArrowSize))
        .foregroundStyle(Theme.textSecondary)
        .opacity(isHovered && !isSelected ? 1 : 0)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, Theme.Metrics.rowInset)
    .frame(minHeight: Theme.Metrics.rowMinHeight)
    .background(rowFill, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .onTapGesture(perform: open)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private var titleText: Text {
    guard let reference = item.reference else { return Text(item.title) }
    let referenceColor = isSelected ? Theme.selectionText.opacity(0.85) : Theme.textSecondary
    return Text("\(Text(reference).foregroundStyle(referenceColor)) \(item.title)")
  }

  private var rowFill: Color {
    if isSelected { return Theme.selectionFill }
    return isHovered ? Theme.surfaceHover : .clear
  }

  // Neutral rows stay gray; only failing, urgent and ready rows take the status color.
  private var symbolColor: Color {
    Theme.statusText(item.badge?.variant ?? .neutral)
  }
}

struct BadgeView: View {
  let badge: Badge
  let isSelected: Bool

  var body: some View {
    Text(badge.text)
      .font(Theme.Fonts.badge)
      .monospacedDigit()
      .foregroundStyle(isSelected ? Theme.selectionText : Theme.statusText(badge.variant))
      .padding(.vertical, 2)
      .padding(.horizontal, 7)
      .background(isSelected ? Theme.selectionText.opacity(0.22) : Theme.badgeFill(badge.variant), in: Capsule())
      .fixedSize()
  }
}

struct StatusStripView: View {
  let strip: StatusStrip
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 7) {
      if let checks = strip.checks {
        checksGlyph(checks)
      }
      if let threads = strip.threads {
        HStack(spacing: Theme.Spacing.xxs) {
          Image(systemName: "bubble.left")
          Text("\(threads.unresolvedCount)\(threads.isLowerBound ? "+" : "")")
        }
        .foregroundStyle(glyphColor(Theme.textSecondary))
      }
      if let approvals = strip.approvals {
        approvalSlots(approvals)
      }
    }
    .font(Theme.Fonts.rowMeta)
    .imageScale(.small)
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(strip.accessibilityPhrase)
  }

  private func checksGlyph(_ checks: StatusStrip.Checks) -> some View {
    switch checks {
    case .passed: Image(systemName: "checkmark.circle").foregroundStyle(glyphColor(Theme.statusText(.ready)))
    case .failed: Image(systemName: "xmark.circle").foregroundStyle(glyphColor(Theme.statusText(.failing)))
    case .running: Image(systemName: "circle.dashed").foregroundStyle(glyphColor(Theme.textSecondary))
    }
  }

  private func approvalSlots(_ approvals: StatusStrip.Approvals) -> some View {
    HStack(spacing: -3) {
      ForEach(0..<approvals.slotCount, id: \.self) { index in
        let isGiven = index < approvals.given
        Image(systemName: isGiven ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(glyphColor(isGiven ? Theme.statusText(.ready) : Theme.textSecondary))
          .background {
            // Draws after the previous slot and erases where they overlap, so the row fill shows through
            // the gap. A ring painted in the panel color would show as a halo on the material and hover fill.
            if index > 0 {
              Image(systemName: "circle.fill").scaleEffect(1.3).blendMode(.destinationOut)
            }
          }
      }
    }
    // Keeps the destination-out erase inside the slots instead of cutting through the row fill.
    .compositingGroup()
  }

  private func glyphColor(_ color: Color) -> Color {
    isSelected ? Theme.selectionText : color
  }
}
