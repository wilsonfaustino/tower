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
