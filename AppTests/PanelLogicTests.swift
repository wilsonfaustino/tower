import AppKit
import Core
import Foundation
import SwiftUI
import Testing

@testable import Tower

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

struct AuthBannerMessageTests {
  @Test func withoutDataShowsTheMissingDataMessage() {
    let message = authBannerMessage(
      itemsLabel: "PRs", fetchedAt: nil, now: now, missingDataMessage: "Run gh auth login to show your PRs.",
      otherSources: [("Jira", .ok)])
    #expect(message == "Run gh auth login to show your PRs.")
  }

  @Test(arguments: [(0.0, 1), (59.0, 1), (60.0, 1), (179.0, 2), (600.0, 10)])
  func countsWholeMinutesWithAMinimumOfOne(secondsAgo: TimeInterval, minutes: Int) {
    let message = authBannerMessage(
      itemsLabel: "tickets", fetchedAt: now.addingTimeInterval(-secondsAgo), now: now, missingDataMessage: "",
      otherSources: [])
    #expect(message == "Showing tickets from \(minutes) min ago.")
  }

  @Test func addsTheOtherSourcesThatAreCurrent() {
    let message = authBannerMessage(
      itemsLabel: "pipelines", fetchedAt: now.addingTimeInterval(-300), now: now, missingDataMessage: "",
      otherSources: [("GitHub", .ok), ("Jira", .ok)])
    #expect(message == "Showing pipelines from 5 min ago. GitHub and Jira are current.")
  }
}

struct CurrentSentenceTests {
  @Test func noOkSourceGivesNoSentence() {
    #expect(currentSentence(sources: [("GitHub", .idle), ("Jira", .failed(.network))]) == "")
    #expect(currentSentence(sources: []) == "")
  }

  @Test func oneOkSourceIsCurrent() {
    #expect(currentSentence(sources: [("GitHub", .failed(.network)), ("Jira", .ok)]) == " Jira is current.")
  }

  @Test func twoOkSourcesAreCurrent() {
    #expect(currentSentence(sources: [("GitHub", .ok), ("CircleCI", .ok)]) == " GitHub and CircleCI are current.")
  }
}

private func item(_ id: String) -> QueueItem {
  QueueItem(
    id: id, title: id, meta: "", url: URL(string: "https://example.com/\(id)")!, symbol: .review, badge: nil,
    sortDate: now)
}

private let items = [item("a"), item("b"), item("c")]

struct SelectionMovementTests {
  @Test func noItemsSelectNothing() {
    #expect(nextSelectedItemId(in: [], after: nil, offset: 1) == nil)
  }

  @Test func firstDownPicksTheFirstRow() {
    #expect(nextSelectedItemId(in: items, after: nil, offset: 1) == "a")
  }

  @Test func firstUpPicksTheLastRow() {
    #expect(nextSelectedItemId(in: items, after: nil, offset: -1) == "c")
  }

  @Test func selectionThatLeftTheListStartsOver() {
    #expect(nextSelectedItemId(in: items, after: "gone", offset: 1) == "a")
  }

  @Test func downAndUpMoveOneRow() {
    #expect(nextSelectedItemId(in: items, after: "a", offset: 1) == "b")
    #expect(nextSelectedItemId(in: items, after: "c", offset: -1) == "b")
  }

  @Test func selectionStaysAtTheEnds() {
    #expect(nextSelectedItemId(in: items, after: "c", offset: 1) == "c")
    #expect(nextSelectedItemId(in: items, after: "a", offset: -1) == "a")
  }
}

private func group(_ id: String, children: [QueueItem]) -> QueueItem {
  var groupItem = item(id)
  groupItem.children = children
  return groupItem
}

private let botGroup = group("bot", children: [item("bot-1"), item("bot-2")])
private let tabSections = [
  QueueSection(kind: .review, items: [item("r1")]),
  QueueSection(kind: .tidy, items: [botGroup, item("t1")]),
  QueueSection(kind: .watch, items: [item("w1"), item("w2"), item("w3")]),
  QueueSection(kind: .waiting, items: [item("p1")]),
]

struct TabItemCountTests {
  @Test func aGroupCountsAsItsChildren() {
    #expect(tabItemCount(in: tabSections, tab: .needsYou) == 4)
  }

  @Test func watchRowsAreNotInATab() {
    #expect(tabItemCount(in: tabSections, tab: .waiting) == 1)
  }

  @Test func noSectionsCountZero() {
    #expect(tabItemCount(in: [], tab: .needsYou) == 0)
  }
}

struct SelectableRowsTests {
  @Test func collapsedGroupsHideTheirChildrenAndWatchRowsFollowTheTab() {
    let rows = selectableRows(in: tabSections, layout: .split, tab: .needsYou, expandedItemIds: [])
    #expect(rows.map(\.id) == ["r1", "bot", "t1", "w1", "w2"])
  }

  @Test func expandedChildrenFollowTheirGroup() {
    let rows = selectableRows(in: tabSections, layout: .split, tab: .needsYou, expandedItemIds: ["bot"])
    #expect(rows.map(\.id) == ["r1", "bot", "bot-1", "bot-2", "t1", "w1", "w2"])
  }

  @Test func waitingTabAlsoEndsWithThePinnedWatchRows() {
    let rows = selectableRows(in: tabSections, layout: .split, tab: .waiting, expandedItemIds: [])
    #expect(rows.map(\.id) == ["p1", "w1", "w2"])
  }

  @Test func consolidatedGoesThroughEveryRowInUrgencyOrderWithAllWatchRows() {
    for tab in PanelTab.allCases {
      let rows = selectableRows(in: tabSections, layout: .consolidated, tab: tab, expandedItemIds: [])
      #expect(rows.map(\.id) == ["r1", "bot", "t1", "w1", "w2", "w3", "p1"])
    }
  }

  @Test func consolidatedExpandedChildrenFollowTheirGroup() {
    let rows = selectableRows(in: tabSections, layout: .consolidated, tab: .needsYou, expandedItemIds: ["bot"])
    #expect(rows.map(\.id) == ["r1", "bot", "bot-1", "bot-2", "t1", "w1", "w2", "w3", "p1"])
  }

  @Test func pinnedWatchRowsStopAtTheLimit() {
    #expect(pinnedWatchRows(in: tabSections).map(\.id) == ["w1", "w2"])
    #expect(pinnedWatchRows(in: []).isEmpty)
  }
}

struct DisclosureOutcomeTests {
  @Test func rightExpandsACollapsedGroup() {
    let outcome = disclosureOutcome(for: .right, selectedItemId: "bot", in: tabSections, expandedItemIds: [])
    #expect(outcome == .expand("bot"))
  }

  @Test func leftCollapsesAnExpandedGroup() {
    let outcome = disclosureOutcome(for: .left, selectedItemId: "bot", in: tabSections, expandedItemIds: ["bot"])
    #expect(outcome == .collapse("bot"))
  }

  @Test func repeatedDirectionOnAGroupIsIgnored() {
    #expect(disclosureOutcome(for: .right, selectedItemId: "bot", in: tabSections, expandedItemIds: ["bot"]) == .ignore)
    #expect(disclosureOutcome(for: .left, selectedItemId: "bot", in: tabSections, expandedItemIds: []) == .ignore)
  }

  @Test func leftOnAChildSelectsItsGroup() {
    let outcome = disclosureOutcome(for: .left, selectedItemId: "bot-2", in: tabSections, expandedItemIds: ["bot"])
    #expect(outcome == .selectGroup("bot"))
  }

  @Test func rightOnAChildIsIgnored() {
    #expect(disclosureOutcome(for: .right, selectedItemId: "bot-2", in: tabSections, expandedItemIds: ["bot"]) == .ignore)
  }

  @Test(arguments: [DisclosureDirection.left, .right])
  func plainRowsAndNoSelectionAreIgnored(direction: DisclosureDirection) {
    #expect(disclosureOutcome(for: direction, selectedItemId: "r1", in: tabSections, expandedItemIds: []) == .ignore)
    #expect(disclosureOutcome(for: direction, selectedItemId: nil, in: tabSections, expandedItemIds: []) == .ignore)
  }
}

struct SlideOutcomeTests {
  @Test func leftShowsDismissOnADismissibleRow() {
    #expect(slideOutcome(for: .left, layoutDirection: .leftToRight, selectedItemIsDismissible: true, isSlid: false) == .show)
  }

  @Test func leftOnARowThatCannotBeDismissedKeepsTodaysKeys() {
    #expect(
      slideOutcome(for: .left, layoutDirection: .leftToRight, selectedItemIsDismissible: false, isSlid: false)
        == .passThrough)
  }

  @Test(arguments: [SlideKey.right, .returnKey, .escape, .upArrow, .downArrow, .space])
  func otherKeysKeepTodaysKeysWhileNothingIsSlid(key: SlideKey) {
    #expect(
      slideOutcome(for: key, layoutDirection: .leftToRight, selectedItemIsDismissible: true, isSlid: false)
        == .passThrough)
  }

  @Test func returnDismissesTheSlidRow() {
    #expect(
      slideOutcome(for: .returnKey, layoutDirection: .leftToRight, selectedItemIsDismissible: true, isSlid: true)
        == .dismiss)
  }

  @Test(arguments: [SlideKey.right, .escape, .upArrow, .downArrow, .space])
  func keysThatCancelCloseTheSlideOnTheFirstPress(key: SlideKey) {
    #expect(
      slideOutcome(for: key, layoutDirection: .leftToRight, selectedItemIsDismissible: true, isSlid: true) == .close)
  }

  @Test func leftAgainKeepsTheSlide() {
    #expect(
      slideOutcome(for: .left, layoutDirection: .leftToRight, selectedItemIsDismissible: true, isSlid: true) == .stay)
  }

  @Test func rightToLeftMirrorsTheArrows() {
    #expect(slideOutcome(for: .right, layoutDirection: .rightToLeft, selectedItemIsDismissible: true, isSlid: false) == .show)
    #expect(
      slideOutcome(for: .left, layoutDirection: .rightToLeft, selectedItemIsDismissible: true, isSlid: false)
        == .passThrough)
    #expect(slideOutcome(for: .left, layoutDirection: .rightToLeft, selectedItemIsDismissible: true, isSlid: true) == .close)
    #expect(slideOutcome(for: .right, layoutDirection: .rightToLeft, selectedItemIsDismissible: true, isSlid: true) == .stay)
  }

  @Test func upFromTheFirstChildStillReachesTheGroup() {
    let rows = selectableRows(in: tabSections, layout: .split, tab: .needsYou, expandedItemIds: ["bot"])
    #expect(nextSelectedItemId(in: rows, after: "bot-1", offset: -1) == "bot")
  }
}

struct SwipeOutcomeTests {
  // Natural scrolling is on by default: the scroll delta follows the fingers.
  private func outcome(
    horizontalDelta: CGFloat, verticalDelta: CGFloat = 0, isDirectionInvertedFromDevice: Bool = true,
    layoutDirection: LayoutDirection = .leftToRight, isDismissible: Bool = true, isSlid: Bool = false
  ) -> SlideOutcome {
    swipeOutcome(
      horizontalDelta: horizontalDelta, verticalDelta: verticalDelta,
      isDirectionInvertedFromDevice: isDirectionInvertedFromDevice, layoutDirection: layoutDirection,
      isDismissible: isDismissible, isSlid: isSlid)
  }

  @Test func swipeLeftShowsDismiss() {
    #expect(outcome(horizontalDelta: -swipeThreshold) == .show)
  }

  @Test func swipeLeftWithNaturalScrollingOffFollowsTheFingers() {
    #expect(outcome(horizontalDelta: swipeThreshold, isDirectionInvertedFromDevice: false) == .show)
  }

  @Test func shortOrMostlyVerticalSwipesDoNothing() {
    #expect(outcome(horizontalDelta: -(swipeThreshold - 1)) == .passThrough)
    #expect(outcome(horizontalDelta: -swipeThreshold, verticalDelta: swipeThreshold + 1) == .passThrough)
  }

  @Test func swipeOnARowThatCannotBeDismissedDoesNothing() {
    #expect(outcome(horizontalDelta: -swipeThreshold, isDismissible: false) == .passThrough)
  }

  @Test func swipeRightClosesTheSlide() {
    #expect(outcome(horizontalDelta: swipeThreshold, isSlid: true) == .close)
    #expect(outcome(horizontalDelta: swipeThreshold) == .passThrough)
    #expect(outcome(horizontalDelta: -swipeThreshold, isSlid: true) == .stay)
  }

  @Test func rightToLeftMirrorsTheSwipe() {
    #expect(outcome(horizontalDelta: swipeThreshold, layoutDirection: .rightToLeft) == .show)
    #expect(outcome(horizontalDelta: -swipeThreshold, layoutDirection: .rightToLeft, isSlid: true) == .close)
  }
}

struct RowAccessibilityLabelTests {
  @Test func namesEveryPartAndTheStatusDot() {
    let pullRequest = QueueItem(
      id: "pr", title: "Fix login", tag: "app", meta: "ana · 2h", metaTeam: "web", url: URL(string: "https://e.com")!,
      symbol: .review, badge: Badge(text: "Review", variant: .urgent), sortDate: now, reference: "#12")
    #expect(rowAccessibilityLabel(for: pullRequest) == "Fix login, #12, app, ana · 2h, web, Review, status needs you")
  }

  @Test func namesTheIssueTypeOfATidyRow() {
    let ticket = QueueItem(
      id: "jira:DEMO-1", title: "Fix login", tag: "DEMO-1", meta: "In Progress · 2d", url: URL(string: "https://e.com")!,
      symbol: .bug, badge: Badge(text: "No PR", variant: .neutral), sortDate: now)
    #expect(rowAccessibilityLabel(for: ticket) == "Fix login, DEMO-1, Bug, In Progress · 2d, No PR, status pending")
  }

  @Test func skipsMissingParts() {
    #expect(rowAccessibilityLabel(for: item("a")) == "a, status pending")
  }
}

struct PanelInputTests {
  // (input, selected item has details, popover is open, expected action)
  static let rules: [(PanelInput, Bool, Bool, PanelAction)] = [
    (.click, true, false, .openAndClosePanel),
    (.click, false, false, .openAndClosePanel),
    (.click, true, true, .openAndClosePanel),
    (.click, false, true, .openAndClosePanel),
    (.commandClick, true, false, .openInBackground),
    (.commandClick, false, false, .openInBackground),
    (.commandClick, true, true, .openInBackground),
    (.commandClick, false, true, .openInBackground),
    (.returnKey, true, false, .openAndClosePanel),
    (.returnKey, false, false, .openAndClosePanel),
    (.returnKey, true, true, .openAndClosePanel),
    (.returnKey, false, true, .openAndClosePanel),
    (.space, true, false, .showPopover),
    (.space, false, false, .ignore),
    (.space, true, true, .closePopover),
    (.space, false, true, .closePopover),
    (.escape, true, false, .closePanel),
    (.escape, false, false, .closePanel),
    (.escape, true, true, .closePopover),
    (.escape, false, true, .closePopover),
    (.upArrow, true, false, .closePopoverAndMoveSelection(offset: -1)),
    (.upArrow, false, false, .closePopoverAndMoveSelection(offset: -1)),
    (.upArrow, true, true, .closePopoverAndMoveSelection(offset: -1)),
    (.upArrow, false, true, .closePopoverAndMoveSelection(offset: -1)),
    (.downArrow, true, false, .closePopoverAndMoveSelection(offset: 1)),
    (.downArrow, false, false, .closePopoverAndMoveSelection(offset: 1)),
    (.downArrow, true, true, .closePopoverAndMoveSelection(offset: 1)),
    (.downArrow, false, true, .closePopoverAndMoveSelection(offset: 1)),
    (.copy, true, false, .copyLink),
    (.copy, false, false, .ignore),
    (.copy, true, true, .copyLink),
    (.copy, false, true, .ignore),
    (.rightClick, true, false, .showContextMenu),
    (.rightClick, false, false, .ignore),
    (.rightClick, true, true, .showContextMenu),
    (.rightClick, false, true, .ignore),
  ]

  @Test(arguments: rules)
  func inputGivesTheRuleAction(
    input: PanelInput, selectedItemHasDetails: Bool, isPopoverOpen: Bool, expectedAction: PanelAction
  ) {
    let action = panelAction(for: input, selectedItemHasDetails: selectedItemHasDetails, isPopoverOpen: isPopoverOpen)
    #expect(action == expectedAction)
  }

  // (input, selected item is dismissible, popover is open, expected action), on rows without PR details.
  static let dismissibleRules: [(PanelInput, Bool, Bool, PanelAction)] = [
    (.dismiss, true, false, .dismiss),
    (.dismiss, false, false, .ignore),
    (.dismiss, false, true, .ignore),
    (.rightClick, true, false, .showContextMenu),
    (.rightClick, false, false, .ignore),
    (.space, true, false, .ignore),
    (.copy, true, false, .ignore),
    (.returnKey, true, false, .openAndClosePanel),
  ]

  @Test(arguments: dismissibleRules)
  func dismissibleRowInputGivesTheRuleAction(
    input: PanelInput, selectedItemIsDismissible: Bool, isPopoverOpen: Bool, expectedAction: PanelAction
  ) {
    let action = panelAction(
      for: input, selectedItemHasDetails: false, isPopoverOpen: isPopoverOpen,
      selectedItemIsDismissible: selectedItemIsDismissible)
    #expect(action == expectedAction)
  }

  @Test func dismissActsOnAReviewRequestRowWithDetails() {
    #expect(
      panelAction(for: .dismiss, selectedItemHasDetails: true, isPopoverOpen: true, selectedItemIsDismissible: true)
        == .dismiss)
    #expect(
      panelAction(for: .rightClick, selectedItemHasDetails: true, isPopoverOpen: false, selectedItemIsDismissible: true)
        == .showContextMenu)
  }

  @Test func dismissIgnoresAPullRequestRow() {
    #expect(panelAction(for: .dismiss, selectedItemHasDetails: true, isPopoverOpen: false) == .ignore)
  }
}

struct PanelKeyOutcomeTests {
  @Test func moveClosesThePopoverAndMovesTheSelection() {
    let outcome = panelKeyOutcome(
      for: .closePopoverAndMoveSelection(offset: -1), selectedItemId: "a", popoverItemId: "a")
    #expect(outcome == PanelKeyOutcome(popoverItemId: nil, selectionOffset: -1))
  }

  @Test func showPopoverOpensItOnTheSelectedRow() {
    let outcome = panelKeyOutcome(for: .showPopover, selectedItemId: "a", popoverItemId: nil)
    #expect(outcome == PanelKeyOutcome(popoverItemId: "a"))
  }

  @Test func closePopoverClosesIt() {
    let outcome = panelKeyOutcome(for: .closePopover, selectedItemId: "a", popoverItemId: "a")
    #expect(outcome == PanelKeyOutcome(popoverItemId: nil))
  }

  @Test func copyLinkKeepsThePopover() {
    let outcome = panelKeyOutcome(for: .copyLink, selectedItemId: "a", popoverItemId: "a")
    #expect(outcome == PanelKeyOutcome(popoverItemId: "a", copiesSelectedLink: true))
  }

  @Test func undoActsOnlyWhenADismissalCanBeUndone() {
    #expect(panelAction(for: .undo, selectedItemHasDetails: false, isPopoverOpen: false, canUndo: true) == .undo)
    #expect(panelAction(for: .undo, selectedItemHasDetails: true, isPopoverOpen: true, canUndo: true) == .undo)
    #expect(panelAction(for: .undo, selectedItemHasDetails: false, isPopoverOpen: false, canUndo: false) == .ignore)
  }

  @Test func undoKeepsThePopover() {
    let outcome = panelKeyOutcome(for: .undo, selectedItemId: "a", popoverItemId: "a")
    #expect(outcome == PanelKeyOutcome(popoverItemId: "a", undoesLastDismissal: true))
  }

  @Test func dismissClosesThePopover() {
    let outcome = panelKeyOutcome(for: .dismiss, selectedItemId: "a", popoverItemId: "a")
    #expect(outcome == PanelKeyOutcome(popoverItemId: nil, dismissesSelectedItem: true))
  }

  @Test func dismissDismissesTheSelectedRow() {
    let outcome = panelKeyOutcome(for: .dismiss, selectedItemId: "a", popoverItemId: nil)
    #expect(outcome == PanelKeyOutcome(popoverItemId: nil, dismissesSelectedItem: true))
  }

  @Test(arguments: [PanelAction.closePanel, .ignore, .openAndClosePanel, .openInBackground, .showContextMenu])
  func otherActionsAreNotHandled(action: PanelAction) {
    let outcome = panelKeyOutcome(for: action, selectedItemId: "a", popoverItemId: nil)
    #expect(outcome == PanelKeyOutcome(popoverItemId: nil, isHandled: false))
  }
}

@MainActor struct WriteLinkTests {
  @Test func writesTheURLAsPlainText() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("TowerTests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("old", forType: .string)
    writeLink(try #require(URL(string: "https://github.com/acme/app/pull/7")), to: pasteboard)
    #expect(pasteboard.string(forType: .string) == "https://github.com/acme/app/pull/7")
  }
}

@Suite struct ReviewFixTests {
  private func row(
    id: String, symbol: RowSymbol = .pullRequest, badge: Badge? = nil, checks: StatusStrip.Checks? = nil,
    children: [QueueItem] = []
  ) -> QueueItem {
    QueueItem(
      id: id, title: id, meta: "1h", url: URL(string: "https://example.com/\(id)")!, symbol: symbol, badge: badge,
      sortDate: .distantPast, strip: StatusStrip(checks: checks, threads: nil, approvals: nil), children: children)
  }

  @Test func failingDraftNamesTheDot() {
    let draft = row(id: "d", badge: Badge(text: "Draft", variant: .neutral), checks: .failed)
    #expect(rowStatusText(for: draft)?.text == "Draft · failing")
    #expect(!rowAccessibilityLabel(for: draft).contains("status failing"))
  }

  @Test func groupWithUrgentChildSaysNeedsYou() {
    let group = row(id: "g", children: [row(id: "c", badge: Badge(text: "Changes requested", variant: .urgent))])
    #expect(rowStatusText(for: group)?.text == "needs you")
  }

  @Test func matchingBadgeKeepsItsText() {
    let approved = row(id: "a", badge: Badge(text: "Approved", variant: .ready))
    #expect(rowStatusText(for: approved)?.text == "Approved")
    #expect(rowStatusText(for: row(id: "p", checks: .running)) == nil)
  }

  @Test func symbolColorFollowsChecks() {
    #expect(rowSymbolVariant(for: row(id: "p", checks: .passed)) == .ready)
    #expect(rowSymbolVariant(for: row(id: "f", checks: .failed)) == .failing)
    #expect(rowSymbolVariant(for: row(id: "r", checks: .running)) == .urgent)
    #expect(rowSymbolVariant(for: row(id: "n")) == .neutral)
    #expect(rowSymbolVariant(for: row(id: "a", symbol: .merge, badge: Badge(text: "Approved", variant: .ready))) == .ready)
    #expect(rowSymbolVariant(for: row(id: "c", badge: Badge(text: "Changes requested", variant: .urgent), checks: .passed)) == .ready)
  }

  @Test func runningChecksAreYellowEvenOnAnApprovedRow() {
    let approved = row(id: "a", symbol: .merge, badge: Badge(text: "Approved", variant: .ready), checks: .running)
    #expect(rowSymbolVariant(for: approved) == .urgent)
  }

  @Test(arguments: [StatusStrip.Checks.passed, .failed, .running, nil])
  func draftSymbolStaysGray(checks: StatusStrip.Checks?) {
    let draft = row(id: "d", symbol: .draftPullRequest, badge: Badge(text: "Draft", variant: .neutral), checks: checks)
    #expect(rowSymbolVariant(for: draft) == .neutral)
  }

  @Test func repoGroupSymbolIsGrayEvenWithAnUrgentBadge() {
    let group = QueueItem(
      id: "g", title: "app-web", meta: "3 PRs · 1h", url: URL(string: "https://example.com/g")!, symbol: .pullRequest,
      badge: Badge(text: "1 changes requested", variant: .urgent), sortDate: .distantPast,
      children: [row(id: "c1", checks: .passed)])
    #expect(rowSymbolVariant(for: group) == .neutral)
  }

  @Test func onHoldPipelineIsPinnedFirst() {
    let running = (1...2).map { row(id: "run\($0)", badge: Badge(text: "Running", variant: .neutral)) }
    let onHold = row(id: "hold", badge: Badge(text: "Needs approval", variant: .urgent))
    let sections = [QueueSection(kind: .watch, items: running + [onHold])]
    #expect(pinnedWatchRows(in: sections).map(\.id) == ["hold", "run1"])
  }

  @Test func pinnedAreaShowsTheRowsTheArrowKeysSelect() throws {
    let running = (1...3).map { row(id: "run\($0)", badge: Badge(text: "Running", variant: .neutral)) }
    let onHold = row(id: "hold", badge: Badge(text: "Needs approval", variant: .urgent))
    let sections = [QueueSection(kind: .watch, items: running + [onHold])]
    let pinnedSection = try #require(pinnedWatchSection(in: sections))
    #expect(pinnedSection.items.map(\.id) == ["hold", "run1", "run2", "run3"])
    #expect(pinnedSection.items.prefix(pinnedWatchRowLimit).map(\.id) == pinnedWatchRows(in: sections).map(\.id))
    #expect(pinnedWatchSection(in: []) == nil)
  }

  @Test func sectionCountIncludesGroupChildren() {
    let group = row(id: "g", children: [row(id: "c1"), row(id: "c2"), row(id: "c3")])
    #expect(rowCount(of: QueueSection(kind: .waiting, items: [group, row(id: "solo")])) == 4)
  }
}

@Suite struct PanelShortcutTests {
  @Test func digitShortcutsPickTabsInOrder() {
    #expect(panelTab(forShortcut: "1") == .needsYou)
    #expect(panelTab(forShortcut: "2") == .waiting)
    #expect(panelTab(forShortcut: "3") == nil)
    #expect(panelTab(forShortcut: "0") == nil)
    #expect(panelTab(forShortcut: "a") == nil)
  }

  @Test func toggledExpansionAddsThenRemoves() {
    let expanded = toggledExpansion(of: "g", in: ["other"])
    #expect(expanded == ["other", "g"])
    #expect(toggledExpansion(of: "g", in: expanded) == ["other"])
  }
}

private func dotted(_ id: String, _ variant: BadgeVariant) -> QueueItem {
  var dottedItem = item(id)
  dottedItem.badge = Badge(text: id, variant: variant)
  return dottedItem
}

private let failingRow = dotted("f1", .failing)
private let urgentRow = dotted("u1", .urgent)
private let readyRow = dotted("ok1", .ready)
private let pendingRow = item("p1")
private let urgentGroup = group("bot", children: [dotted("bot-1", .urgent), item("bot-2")])
private let filterSections = [
  QueueSection(kind: .fix, items: [failingRow]),
  QueueSection(kind: .review, items: [urgentGroup, pendingRow]),
  QueueSection(kind: .watch, items: [dotted("w1", .urgent), item("w2")]),
  QueueSection(kind: .waiting, items: [readyRow]),
]

struct StatusFilterTests {
  @Test func legendStatusesFollowTheFixedOrder() {
    let sections = [QueueSection(kind: .review, items: [pendingRow, readyRow, urgentRow, failingRow])]
    #expect(legendStatuses(in: sections) == [.failing, .urgent, .ready, .pending])
  }

  @Test func aGroupAddsOnlyItsHeaderDot() {
    let sections = [QueueSection(kind: .review, items: [urgentGroup])]
    #expect(legendStatuses(in: sections) == [.urgent])
  }

  @Test func noRowsGiveNoStatuses() {
    #expect(legendStatuses(in: []).isEmpty)
  }

  @Test func oneStatusGivesNoFilter() {
    #expect(effectiveStatusFilter(.pending, legendStatuses: [.pending]) == nil)
  }

  @Test func aChosenStatusFiltersWhileItIsInTheLegend() {
    #expect(effectiveStatusFilter(.urgent, legendStatuses: [.urgent, .pending]) == .urgent)
    #expect(effectiveStatusFilter(nil, legendStatuses: [.urgent, .pending]) == nil)
  }

  @Test func aStatusThatLeftTheLegendGivesNoFilter() {
    #expect(effectiveStatusFilter(.failing, legendStatuses: [.urgent, .pending]) == nil)
  }

  // The panel keeps the effective filter after each legend change, so a status that leaves and comes back
  // does not filter again until the owner chooses it.
  @Test func aStatusThatComesBackStaysUnchosen() {
    var chosenStatus: StatusDot? = .failing
    chosenStatus = effectiveStatusFilter(chosenStatus, legendStatuses: [.urgent, .pending])
    chosenStatus = effectiveStatusFilter(chosenStatus, legendStatuses: [.failing, .pending])
    #expect(chosenStatus == nil)
  }

  @Test func noFilterKeepsTheSections() {
    #expect(filteredSections(filterSections, status: nil) == filterSections)
  }

  @Test func theFilterKeepsMatchingRowsAndDropsEmptySections() {
    let sections = filteredSections(filterSections, status: .pending)
    #expect(sections.map(\.kind) == [.review, .watch])
    #expect(sections.flatMap(\.items).map(\.id) == ["p1", "w2"])
  }

  @Test func aMatchingGroupKeepsAllItsChildren() {
    let sections = filteredSections(filterSections, status: .urgent)
    #expect(sections.flatMap(\.items).map(\.id) == ["bot", "w1"])
    #expect(sections.first?.items.first?.children.map(\.id) == ["bot-1", "bot-2"])
  }

  @Test func aGroupDoesNotMatchByItsChildren() {
    #expect(filteredSections(filterSections, status: .pending).flatMap(\.items).allSatisfy { $0.id != "bot" })
  }

  @Test func aFilteredSectionHeaderKeepsTheFullCount() {
    let filteredReview = filteredSections(filterSections, status: .pending)[0]
    #expect(sectionHeaderCount(of: filteredReview, in: filterSections) == 3)
  }

  @Test func splitFiltersTheListButNotThePinnedWatchRows() {
    let rows = selectableRows(
      in: filterSections, layout: .split, tab: .needsYou, expandedItemIds: ["bot"], statusFilter: .pending)
    #expect(rows.map(\.id) == ["p1", "w1", "w2"])
  }

  @Test func aSplitTabWithOnlyPinnedWatchRowsHasNoLegend() {
    let sections = [QueueSection(kind: .watch, items: [dotted("w1", .urgent), item("w2")])]
    #expect(legendStatuses(in: displayedSections(sections, layout: .split, tab: .needsYou)).isEmpty)
  }

  // A refresh can move the selected row out of the filter while the filter stays on.
  @Test func aSelectedRowThatLeavesTheFilterIsNotListed() {
    var refreshed = filterSections
    refreshed[3].items.append(dotted("ok2", .ready))
    refreshed[3].items[0].badge = Badge(text: "failed", variant: .failing)
    let rows = selectableRows(
      in: refreshed, layout: .split, tab: .waiting, expandedItemIds: [], statusFilter: .ready)
    #expect(rows.map(\.id) == ["ok2", "w1", "w2"])
    #expect(!isSelectionListed("ok1", in: rows))
    #expect(isSelectionListed("ok2", in: rows))
    #expect(isSelectionListed(nil, in: rows))
  }

  @Test func consolidatedFiltersTheWatchRows() {
    let rows = selectableRows(
      in: filterSections, layout: .consolidated, tab: .needsYou, expandedItemIds: [], statusFilter: .urgent)
    #expect(rows.map(\.id) == ["bot", "w1"])
  }
}
