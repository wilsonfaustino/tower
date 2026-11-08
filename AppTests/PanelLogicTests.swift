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
