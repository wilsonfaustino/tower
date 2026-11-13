import Core
import SwiftUI

struct QueueRowView: View {
  let item: QueueItem
  let isSelected: Bool
  var isExpanded = false
  let open: () -> Void
  let showDetails: () -> Void
  let copyLink: () -> Void
  let dismiss: () -> Void
  @State private var isHovered = false

  // PR rows and failed pipeline rows get a context menu; other rows keep their single action.
  var body: some View {
    if isGroup {
      row
        .contextMenu {
          Button("Open in Browser", action: open)
        }
    } else if item.details != nil {
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

  private var isGroup: Bool { !item.children.isEmpty }

  private var row: some View {
    HStack(spacing: Theme.Spacing.s) {
      if isGroup {
        Image(systemName: "chevron.right")
          .font(.system(size: Theme.Metrics.disclosureSize, weight: .semibold))
          .foregroundStyle(isSelected ? Theme.selectionText : Theme.textSecondary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          .accessibilityHidden(true)
      }
      Image(systemName: item.symbol.rawValue)
        .font(.system(size: Theme.Metrics.symbolSize))
        .foregroundStyle(isSelected ? Theme.selectionText : symbolColor)
        .frame(width: Theme.Metrics.iconColumn)
        // SF Symbol descriptions ("show", "divide") would mislead; the badge text carries the meaning.
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
        Text(item.title)
          .font(Theme.Fonts.rowTitle)
          .foregroundStyle(isSelected ? Theme.selectionText : Theme.textPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
        HStack(spacing: 6) {
          // Stack spacing instead of spaces around the dot, which bidi moves in right-to-left.
          // Priorities: number, author and age keep full width, then the tag, and the team gets what is left.
          HStack(spacing: Theme.Spacing.xs) {
            if let tag = item.tag {
              TagChipView(tag: tag, isSelected: isSelected).layoutPriority(1)
            }
            ForEach(Array(metaParts.enumerated()), id: \.offset) { index, part in
              if index > 0 {
                Text("·").layoutPriority(2).accessibilityHidden(true)
              }
              Text(part.text).truncationMode(.tail).layoutPriority(part.isTeam ? 0 : 2)
            }
          }
          .font(Theme.Fonts.rowMeta)
          .foregroundStyle(isSelected ? Theme.selectionText.opacity(0.85) : Theme.textSecondary)
          .lineLimit(1)
          if let strip = item.strip, !strip.isEmpty {
            StatusStripView(strip: strip, isSelected: isSelected)
          }
        }
      }
      Spacer(minLength: Theme.Spacing.s)
      if let statusText = rowStatusText(for: item) {
        StatusTextView(statusText: statusText, isSelected: isSelected)
      }
      StatusDotView(dot: item.statusDot, isSelected: isSelected)
      // Always in the layout so hover does not change the row width or the title truncation.
      Image(systemName: "arrow.up.right")
        .font(.system(size: Theme.Metrics.openArrowSize))
        .foregroundStyle(Theme.textSecondary)
        .opacity(isHovered && !isSelected && !isGroup ? 1 : 0)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, Theme.Metrics.rowInset)
    .frame(minHeight: Theme.Metrics.rowMinHeight)
    .background(rowFill, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .onTapGesture(perform: open)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rowAccessibilityLabel(for: item))
    .accessibilityValue(isGroup ? (isExpanded ? "expanded" : "collapsed") : "")
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private var metaParts: [(text: String, isTeam: Bool)] {
    [(item.reference, false), (item.metaTail, false), (item.metaTeam, true)].compactMap { text, isTeam in
      guard let text, !text.isEmpty else { return nil }
      return (text, isTeam)
    }
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

// VoiceOver reads the dot meaning, because color alone does not carry it.
func rowAccessibilityLabel(for item: QueueItem) -> String {
  let parts = [
    item.title, item.reference, item.tag, item.metaTail, item.metaTeam, item.strip?.accessibilityPhrase,
    rowStatusText(for: item)?.text,
  ]
  // Skips the phrase when the status text already names the dot, like "Draft · failing".
  let statusText = rowStatusText(for: item)?.text ?? ""
  let statusPhrase = statusText.hasSuffix(item.statusDot.legendLabel) ? nil : "status \(item.statusDot.legendLabel)"
  return (parts + [statusPhrase]).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
}

struct RowStatusText: Equatable {
  let text: String
  // Nil keeps the badge color. Set when the text names the dot, so the words match the dot color.
  let dot: StatusDot?
  let badgeVariant: BadgeVariant
}

// A failing or urgent dot always has words next to it, so color is never the only signal.
// "Draft" with failed checks reads "Draft · failing"; a group with an urgent child reads "needs you".
func rowStatusText(for item: QueueItem) -> RowStatusText? {
  let dot = item.statusDot
  let dotNeedsWords = dot == .failing || dot == .urgent
  guard let badge = item.badge else {
    return dotNeedsWords ? RowStatusText(text: dot.legendLabel, dot: dot, badgeVariant: .neutral) : nil
  }
  let badgeNamesDot = (badge.variant == .failing && dot == .failing) || (badge.variant == .urgent && dot == .urgent)
  guard dotNeedsWords, !badgeNamesDot else {
    return RowStatusText(text: badge.text, dot: nil, badgeVariant: badge.variant)
  }
  return RowStatusText(text: "\(badge.text) · \(dot.legendLabel)", dot: dot, badgeVariant: badge.variant)
}

struct StatusTextView: View {
  let statusText: RowStatusText
  let isSelected: Bool

  var body: some View {
    Text(statusText.text)
      .font(Theme.Fonts.badge)
      .monospacedDigit()
      .foregroundStyle(isSelected ? Theme.selectionText : textColor)
      .fixedSize()
  }

  private var textColor: Color {
    statusText.dot.map(Theme.dotColor) ?? Theme.statusText(statusText.badgeVariant)
  }
}

struct StatusDotView: View {
  let dot: StatusDot
  let isSelected: Bool

  var body: some View {
    let color = isSelected ? Theme.selectionText : Theme.dotColor(dot)
    Group {
      if dot == .pending {
        Circle().strokeBorder(color, lineWidth: Theme.Metrics.pendingRingWidth)
      } else {
        Circle().fill(color)
      }
    }
    .frame(width: Theme.Metrics.statusDotSize, height: Theme.Metrics.statusDotSize)
    .accessibilityHidden(true)
  }
}

struct TagChipView: View {
  let tag: String
  let isSelected: Bool

  var body: some View {
    // Middle truncation, as Finder does for file names, keeps both ends of a long repo name.
    MaxWidthLayout(maxWidth: Theme.Metrics.tagMaxWidth) {
      Text(tag).lineLimit(1).truncationMode(.middle)
    }
    .font(Theme.Fonts.tag)
    .foregroundStyle(isSelected ? Theme.selectionText : Theme.textSecondary)
    .padding(.horizontal, 5)
    .padding(.vertical, 1)
    .background(
      isSelected ? Theme.selectionText.opacity(0.22) : Theme.neutralBadgeFill, in: RoundedRectangle(cornerRadius: 4))
  }
}

// Caps the width proposed to its one subview and takes the subview size. A flexible frame would instead
// grow to the max width whenever there is room, which leaves blank space after a short tag.
struct MaxWidthLayout: Layout {
  let maxWidth: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    subviews.first?.sizeThatFits(cappedProposal(proposal)) ?? .zero
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
  }

  private func cappedProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
    ProposedViewSize(width: min(proposal.width ?? maxWidth, maxWidth), height: proposal.height)
  }
}

struct StatusStripView: View {
  let strip: StatusStrip
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 7) {
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

// Hidden from VoiceOver, because each row label already names its dot.
struct StatusLegendView: View {
  var body: some View {
    HStack(spacing: Theme.Spacing.m) {
      ForEach(StatusDot.allCases, id: \.self) { dot in
        HStack(spacing: Theme.Spacing.xs) {
          StatusDotView(dot: dot, isSelected: false)
          Text(dot.legendLabel)
        }
      }
    }
    .font(Theme.Fonts.legend)
    .foregroundStyle(Theme.textSecondary)
    .frame(maxWidth: .infinity)
    .accessibilityHidden(true)
  }
}
