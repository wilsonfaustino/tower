import Core
import Foundation
import Testing

private let now = isoDate("2027-01-15T12:00:00Z")

private func content(
  github: SourceStatus, jira: SourceStatus = .failed(.notConfigured),
  githubHasData: Bool = false, jiraHasData: Bool = false, hasItems: Bool = false
) -> PanelContent {
  panelContent(
    sources: [
      PanelSource(status: github, hasData: githubHasData, fetchedAt: nil, staleLabel: "PRs"),
      PanelSource(status: jira, hasData: jiraHasData, fetchedAt: nil, staleLabel: "Tickets"),
    ],
    hasItems: hasItems)
}

struct PanelContentTests {
  @Test func unexpectedFailureWithoutCacheShowsTheMessage() {
    #expect(content(github: .failed(.unexpected("HTTP 502"))) == .failed("HTTP 502"))
  }

  @Test func networkFailureWithoutCacheShowsOffline() {
    #expect(content(github: .failed(.network)) == .offline)
  }

  @Test func firstFetchShowsLoading() {
    #expect(content(github: .idle) == .loading)
  }

  @Test func offlineSourceWithoutDataBlocksClearSkies() {
    #expect(content(github: .failed(.network), jira: .ok, jiraHasData: true) == .offline)
  }

  @Test func allSourcesCurrentAndEmptyIsClearSkies() {
    #expect(content(github: .ok, jira: .ok, githubHasData: true, jiraHasData: true) == .empty)
  }

  @Test func staleCacheWithNoItemsIsClearSkies() {
    #expect(content(github: .failed(.network), githubHasData: true) == .empty)
  }

  @Test func itemsShowTheQueue() {
    #expect(content(github: .failed(.unexpected("x")), githubHasData: true, hasItems: true) == .queue)
  }

  @Test func authFailureWithoutCacheShowsOnlyTheBanner() {
    #expect(content(github: .failed(.authentication)) == .bannerOnly)
  }
}

struct PanelSubtitleTests {
  private func subtitle(github: SourceStatus, jira: SourceStatus = .failed(.notConfigured), githubMinutesAgo: Double? = 2) -> String {
    panelSubtitle(
      sources: [
        PanelSource(
          status: github, hasData: false, fetchedAt: githubMinutesAgo.map { now.addingTimeInterval(-$0 * 60) },
          staleLabel: "PRs"),
        PanelSource(status: jira, hasData: false, fetchedAt: nil, staleLabel: "Tickets"),
      ],
      now: now)
  }

  @Test func currentSourcesShowUpdatedAge() {
    #expect(subtitle(github: .ok) == "Updated 2m ago")
    #expect(subtitle(github: .ok, githubMinutesAgo: 0.2) == "Updated just now")
  }

  @Test func oneSourceOfflineShowsOffline() {
    #expect(subtitle(github: .failed(.network), jira: .ok) == "Offline")
  }

  @Test func unexpectedFailureShowsUpdateFailed() {
    #expect(subtitle(github: .failed(.unexpected("HTTP 502"))) == "Update failed")
  }

  @Test func githubAuthFailureShowsPRAge() {
    #expect(subtitle(github: .failed(.authentication), githubMinutesAgo: 18) == "PRs from 18m ago")
  }

  @Test func noFetchYetShowsUpdating() {
    #expect(subtitle(github: .idle, githubMinutesAgo: nil) == "Updating")
  }
}

struct ThreeSourcePanelStateTests {
  private func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

  @Test func thirdSourceOfflineWithoutDataBlocksClearSkies() {
    let sources = [
      PanelSource(status: .ok, hasData: true, fetchedAt: minutesAgo(1), staleLabel: "PRs"),
      PanelSource(status: .ok, hasData: true, fetchedAt: minutesAgo(1), staleLabel: "Tickets"),
      PanelSource(status: .failed(.network), hasData: false, fetchedAt: nil, staleLabel: "Pipelines"),
    ]
    #expect(panelContent(sources: sources, hasItems: false) == .offline)
  }

  @Test func authFailureOnThirdSourceNamesItsStaleLabel() {
    let sources = [
      PanelSource(status: .ok, hasData: true, fetchedAt: minutesAgo(1), staleLabel: "PRs"),
      PanelSource(status: .ok, hasData: true, fetchedAt: minutesAgo(1), staleLabel: "Tickets"),
      PanelSource(status: .failed(.authentication), hasData: true, fetchedAt: minutesAgo(5), staleLabel: "Pipelines"),
    ]
    #expect(panelSubtitle(sources: sources, now: now) == "Pipelines from 5m ago")
  }

  @Test func unconfiguredSourceFetchDateDoesNotSetTheAge() {
    let sources = [
      PanelSource(status: .ok, hasData: true, fetchedAt: minutesAgo(1), staleLabel: "PRs"),
      PanelSource(status: .failed(.notConfigured), hasData: false, fetchedAt: minutesAgo(90), staleLabel: "Pipelines"),
    ]
    #expect(panelSubtitle(sources: sources, now: now) == "Updated 1m ago")
  }

  @Test func earlierSourceAuthFailureWinsOverLaterOne() {
    let sources = [
      PanelSource(status: .ok, hasData: true, fetchedAt: minutesAgo(1), staleLabel: "PRs"),
      PanelSource(status: .failed(.authentication), hasData: true, fetchedAt: minutesAgo(9), staleLabel: "Tickets"),
      PanelSource(status: .failed(.authentication), hasData: true, fetchedAt: minutesAgo(5), staleLabel: "Pipelines"),
    ]
    #expect(panelSubtitle(sources: sources, now: now) == "Tickets from 9m ago")
  }
}

struct OfflineTitleTests {
  @Test func namesOnlyTheOfflineSource() {
    let sources = [("GitHub", SourceStatus.ok), ("Jira", .failed(.notConfigured)), ("CircleCI", .failed(.network))]
    #expect(offlineTitle(sources: sources) == "Can't reach CircleCI")
  }

  @Test func joinsTwoOfflineSourcesWithOr() {
    let sources = [("GitHub", SourceStatus.failed(.network)), ("Jira", .failed(.network)), ("CircleCI", .ok)]
    #expect(offlineTitle(sources: sources) == "Can't reach GitHub or Jira")
  }

  @Test func joinsThreeOfflineSourcesInOrder() {
    let sources = [("GitHub", SourceStatus.failed(.network)), ("Jira", .failed(.network)), ("CircleCI", .failed(.network))]
    #expect(offlineTitle(sources: sources) == "Can't reach GitHub, Jira or CircleCI")
  }
}
