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
  var isSlid = false
  let hover: (Bool) -> Void
  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // PR rows and failed pipeline rows get a context menu; other rows keep their single action.
  // Review request rows and failed pipeline rows also get Dismiss.
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
          // Review requests are dismissible; the owner's own PRs are not.
          if item.dismissal != nil {
            Divider()
            Button("Dismiss", action: dismiss).keyboardShortcut(.delete)
          }
        }
        .accessibilityAction(named: "Show details", showDetails)
        .accessibilityAction(named: "Copy link", copyLink)
        .accessibilityActions {
          if item.dismissal != nil {
            Button("Dismiss", action: dismiss)
          }
        }
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

  // The slid row moves toward the leading edge and shows Dismiss behind it, like Mail.
  // SwiftUI mirrors the offset in right-to-left, so the row slides right there.
  private var row: some View {
    rowContent
      .offset(x: isSlid ? -Theme.Metrics.dismissActionWidth : 0)
      .background(alignment: .trailing) {
        if isSlid {
          dismissAction
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
      // On the row frame, not the moving content, so the pointer over Dismiss still counts as this row.
      .onHover { isHovering in
        isHovered = isHovering
        hover(isHovering)
      }
      .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSlid)
  }

  private var dismissAction: some View {
    Button(action: dismiss) {
      HStack(spacing: Theme.Spacing.xs) {
        Image(PanelSymbol.trash.rawValue).accessibilityHidden(true)
        Text("Dismiss")
      }
      .font(Theme.Fonts.badge)
      .foregroundStyle(.white)
      .frame(width: Theme.Metrics.dismissActionWidth)
      .frame(maxHeight: .infinity)
      .background(Theme.dismissFill)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var rowContent: some View {
    HStack(spacing: Theme.Spacing.s) {
      if isGroup {
        Image(PanelSymbol.disclosure.rawValue)
          .font(.system(size: Theme.Metrics.disclosureSize, weight: .semibold))
          .foregroundStyle(isSelected ? Theme.selectionText : Theme.textSecondary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          // Custom symbols do not mirror by themselves. Flipping after the rotation keeps the expanded caret pointing down.
          .flipsForRightToLeftLayoutDirection(true)
          .accessibilityHidden(true)
      }
      Image(item.symbol.rawValue)
        .font(.system(size: Theme.Metrics.symbolSize))
        .foregroundStyle(isSelected ? Theme.selectionText : symbolColor)
        .frame(width: Theme.Metrics.iconColumn)
        // The row label carries the meaning (badge text, Jira issue type), so VoiceOver skips the glyph.
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
      Image(PanelSymbol.openArrow.rawValue)
        .font(.system(size: Theme.Metrics.openArrowSize))
        .flipsForRightToLeftLayoutDirection(true)
        .foregroundStyle(Theme.textSecondary)
        .opacity(isHovered && !isSelected && !isGroup ? 1 : 0)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, Theme.Metrics.rowInset)
    .frame(minHeight: Theme.Metrics.rowMinHeight)
    .background(rowFill, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
    .contentShape(Rectangle())
    .onTapGesture(perform: open)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rowAccessibilityLabel(for: item))
    .accessibilityValue(disclosureValue)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private var disclosureValue: String {
    guard isGroup else { return "" }
    return isExpanded ? "expanded" : "collapsed"
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

  private var symbolColor: Color {
    Theme.statusText(rowSymbolVariant(for: item))
  }
}

// Checks color the symbol of an authored PR, except a draft, which stays gray; other rows take their badge color.
func rowSymbolVariant(for item: QueueItem) -> BadgeVariant {
  if item.symbol == .draftPullRequest { return .neutral }
  switch item.strip?.checks {
  case .passed: return .ready
  case .failed: return .failing
  case .running: return .urgent
  case nil: return item.badge?.variant ?? .neutral
  }
}

// VoiceOver reads the dot meaning, because color alone does not carry it.
func rowAccessibilityLabel(for item: QueueItem) -> String {
  let parts = [
    item.title, item.reference, item.tag, item.symbol.issueTypeSpokenName, item.metaTail, item.metaTeam,
    item.strip?.accessibilityPhrase,
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

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
    subviews.first?.sizeThatFits(cappedProposal(proposal)) ?? .zero
  }

  func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
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
          Image(PanelSymbol.threads.rawValue)
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
        Image(isGiven ? PanelSymbol.approvalGiven.rawValue : PanelSymbol.approvalMissing.rawValue)
          .foregroundStyle(glyphColor(isGiven ? Theme.statusText(.ready) : Theme.textSecondary))
          .background {
            // Draws after the previous slot and erases where they overlap, so the row fill shows through
            // the gap. A ring painted in the panel color would show as a halo on the material and hover fill.
            if index > 0 {
              Image(PanelSymbol.approvalErase.rawValue).scaleEffect(1.3).blendMode(.destinationOut)
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
