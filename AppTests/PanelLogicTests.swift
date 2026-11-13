import AppKit
import Core
import Foundation
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
    let rows = selectableRows(in: tabSections, tab: .needsYou, expandedItemIds: [])
    #expect(rows.map(\.id) == ["r1", "bot", "t1", "w1", "w2"])
  }

  @Test func expandedChildrenFollowTheirGroup() {
    let rows = selectableRows(in: tabSections, tab: .needsYou, expandedItemIds: ["bot"])
    #expect(rows.map(\.id) == ["r1", "bot", "bot-1", "bot-2", "t1", "w1", "w2"])
  }

  @Test func waitingTabAlsoEndsWithThePinnedWatchRows() {
    let rows = selectableRows(in: tabSections, tab: .waiting, expandedItemIds: [])
    #expect(rows.map(\.id) == ["p1", "w1", "w2"])
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

struct RowAccessibilityLabelTests {
  @Test func namesEveryPartAndTheStatusDot() {
    let pullRequest = QueueItem(
      id: "pr", title: "Fix login", tag: "app", meta: "ana · 2h", metaTeam: "web", url: URL(string: "https://e.com")!,
      symbol: .review, badge: Badge(text: "Review", variant: .urgent), sortDate: now, reference: "#12")
    #expect(rowAccessibilityLabel(for: pullRequest) == "Fix login, #12, app, ana · 2h, web, Review, status needs you")
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
  private func row(id: String, badge: Badge? = nil, checks: StatusStrip.Checks? = nil, children: [QueueItem] = []) -> QueueItem {
    QueueItem(
      id: id, title: id, meta: "1h", url: URL(string: "https://example.com/\(id)")!, symbol: .waiting, badge: badge,
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

  @Test func onHoldPipelineIsPinnedFirst() {
    let running = (1...2).map { row(id: "run\($0)", badge: Badge(text: "Running", variant: .neutral)) }
    let onHold = row(id: "hold", badge: Badge(text: "Needs approval", variant: .urgent))
    let sections = [QueueSection(kind: .watch, items: running + [onHold])]
    #expect(pinnedWatchRows(in: sections).map(\.id) == ["hold", "run1"])
  }

  @Test func sectionCountIncludesGroupChildren() {
    let group = row(id: "g", children: [row(id: "c1"), row(id: "c2"), row(id: "c3")])
    #expect(rowCount(of: QueueSection(kind: .waiting, items: [group, row(id: "solo")])) == 4)
  }
}
