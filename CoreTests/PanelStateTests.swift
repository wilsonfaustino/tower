import Core
import Foundation
import Testing

private let now = isoDate("2027-01-15T12:00:00Z")

private func content(
  github: SourceStatus, jira: SourceStatus = .failed(.notConfigured),
  githubHasData: Bool = false, jiraHasData: Bool = false, hasItems: Bool = false
) -> PanelContent {
  panelContent(github: github, jira: jira, githubHasData: githubHasData, jiraHasData: jiraHasData, hasItems: hasItems)
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
      github: github, jira: jira, githubFetchedAt: githubMinutesAgo.map { now.addingTimeInterval(-$0 * 60) },
      jiraFetchedAt: nil, now: now)
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
