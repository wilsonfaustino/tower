import AppKit
import Core
import Foundation
import Testing

@testable import Tower

private struct StubTokenProvider: GitHubTokenProvider {
  var result: Result<String, SourceFailure>
  func token() async throws(SourceFailure) -> String { try result.get() }
}

// The test changes the code only between refreshes, so no lock is needed.
private final class StatusCodeBox: @unchecked Sendable {
  var value = 200
}

private let jiraSettings = JiraSettings(
  siteURL: URL(string: "https://acme.atlassian.net")!, email: "me@acme.dev", apiToken: "jira-token")
private let circleciSettings = CircleCISettings(apiToken: "circle-token", projectSlugs: ["gh/acme/app-web"])

private func temporaryDirectory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("tower-store-\(UUID().uuidString)")
}

// Answers each source by host, so one stub serves the whole refresh.
private func routingTransport(github: Int = 200, jira: Int = 200, circleci: Int = 200) throws -> StubTransport {
  let githubData = try fixture("github-search.json")
  let jiraData = try fixture("jira-search.json")
  return StubTransport { request in
    switch request.url?.host() {
    case "api.github.com": (githubData, github)
    case "acme.atlassian.net": (jiraData, jira)
    default: (Data(#"{"items":[]}"#.utf8), circleci)
    }
  }
}

@MainActor private func makeStore(
  token: Result<String, SourceFailure> = .success("gh-token"),
  transport: StubTransport,
  cacheDirectory: URL = temporaryDirectory(),
  jira: JiraSettings? = jiraSettings,
  circleci: CircleCISettings? = circleciSettings
) -> QueueStore {
  QueueStore(
    tokenProvider: StubTokenProvider(result: token), transport: transport, cacheDirectory: cacheDirectory,
    loadJiraSettings: { jira }, loadCircleCISettings: { circleci })
}

@MainActor struct QueueStoreRefreshTests {
  @Test func successfulRefreshMarksEverySourceOkAndFillsSections() async throws {
    let store = makeStore(transport: try routingTransport())
    await store.refresh()
    #expect(store.githubStatus == .ok)
    #expect(store.jiraStatus == .ok)
    #expect(store.circleciStatus == .ok)
    #expect(store.githubSnapshot?.viewerLogin == "octo-me")
    #expect(store.jiraTickets?.map(\.key) == ["PROJ-1432", "PROJ-1440"])
    #expect(store.pipelines == [])
    #expect(store.githubFetchedAt != nil)
    #expect(store.jiraFetchedAt != nil)
    #expect(store.circleciFetchedAt != nil)
    #expect(!store.sections.isEmpty)
    #expect(store.menuBarState == MenuBarState(sections: store.sections))
    #expect(!store.isRefreshing)
    #expect(!store.hasAuthenticationFailure)
  }

  @Test func successfulRefreshWritesTheCache() async throws {
    let cacheDirectory = temporaryDirectory()
    let store = makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory)
    await store.refresh()
    let cache = SourceCache(directory: cacheDirectory)
    #expect(cache.load(GitHubSnapshot.self, name: "github")?.value == store.githubSnapshot)
    #expect(cache.load([JiraTicket].self, name: "jira")?.value == store.jiraTickets)
    #expect(cache.load([Pipeline].self, name: "circleci")?.value == [])
  }

  @Test func rejectedCredentialsMarkEachSourceAsAuthenticationFailure() async throws {
    let store = makeStore(
      token: .failure(.authentication), transport: try routingTransport(jira: 401, circleci: 403))
    await store.refresh()
    #expect(store.githubStatus == .failed(.authentication))
    #expect(store.jiraStatus == .failed(.authentication))
    #expect(store.circleciStatus == .failed(.authentication))
    #expect(store.hasAuthenticationFailure)
  }

  @Test func failedRefreshKeepsTheLastData() async throws {
    let jiraStatusCode = StatusCodeBox()
    let githubData = try fixture("github-search.json")
    let jiraData = try fixture("jira-search.json")
    let transport = StubTransport { request in
      request.url?.host() == "api.github.com" ? (githubData, 200) : (jiraData, jiraStatusCode.value)
    }
    let store = makeStore(transport: transport, circleci: nil)
    await store.refresh()
    let firstFetchedAt = store.jiraFetchedAt
    jiraStatusCode.value = 500
    await store.refresh()
    #expect(store.jiraStatus == .failed(.unexpected("HTTP 500")))
    #expect(store.jiraTickets?.count == 2)
    #expect(store.jiraFetchedAt == firstFetchedAt)
  }

  @Test func missingSettingsClearJiraAndCircleCIData() async throws {
    let cacheDirectory = temporaryDirectory()
    let configuredStore = makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory)
    await configuredStore.refresh()
    let store = makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory, jira: nil, circleci: nil)
    store.loadCache()
    #expect(store.jiraTickets != nil)
    await store.refresh()
    #expect(store.jiraStatus == .failed(.notConfigured))
    #expect(store.circleciStatus == .failed(.notConfigured))
    #expect(store.jiraTickets == nil)
    #expect(store.pipelines == nil)
    #expect(store.circleciFetchedAt == nil)
  }
}

@MainActor struct QueueStoreCacheTests {
  @Test func loadCacheRestoresEverySourceWithItsFetchTime() async throws {
    let cacheDirectory = temporaryDirectory()
    await makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory).refresh()
    let fetchedAt = try #require(SourceCache(directory: cacheDirectory).load([JiraTicket].self, name: "jira")?.fetchedAt)

    let store = makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory)
    store.loadCache()
    #expect(store.githubSnapshot?.viewerLogin == "octo-me")
    #expect(store.jiraTickets?.count == 2)
    #expect(store.pipelines == [])
    #expect(store.jiraFetchedAt == fetchedAt)
    #expect(store.githubFetchedAt == fetchedAt)
    #expect(store.circleciFetchedAt == fetchedAt)
    #expect(!store.sections.isEmpty)
    #expect(store.githubStatus == .idle)
  }

  @Test func loadCacheSkipsCircleCIWithoutSettings() async throws {
    let cacheDirectory = temporaryDirectory()
    await makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory).refresh()
    let store = makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory, circleci: nil)
    store.loadCache()
    #expect(store.pipelines == nil)
    #expect(store.circleciFetchedAt == nil)
  }

  @Test func emptyCacheLeavesTheStoreEmpty() throws {
    let store = makeStore(transport: try routingTransport())
    store.loadCache()
    #expect(store.githubSnapshot == nil)
    #expect(store.jiraTickets == nil)
    #expect(store.sections.isEmpty)
    #expect(store.todaySummary == nil)
  }
}

@MainActor struct QueueStoreSourceTests {
  @Test func panelSourcesListGitHubThenJiraThenCircleCI() async throws {
    let store = makeStore(transport: try routingTransport(), circleci: nil)
    await store.refresh()
    let sources = store.panelSources
    #expect(sources.map(\.staleLabel) == ["PRs", "Tickets", "Pipelines"])
    #expect(sources.map(\.status) == [.ok, .ok, .failed(.notConfigured)])
    #expect(sources.map(\.hasData) == [true, true, false])
    #expect(sources[0].fetchedAt == store.githubFetchedAt)
  }

  @Test func todaySummaryComesFromTheGitHubSnapshot() async throws {
    let store = makeStore(transport: try routingTransport())
    await store.refresh()
    let snapshot = try #require(store.githubSnapshot)
    let summary = try #require(store.todaySummary)
    #expect(summary.reviews == snapshot.reviewsSubmittedToday)
    #expect(summary.merges == snapshot.mergedToday)
  }
}

// The stub transport answers on another thread, so wait in short steps instead of one yield.
@MainActor private func waitUntil(_ condition: () -> Bool) async throws {
  for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
}

@MainActor struct QueueStoreStartTests {
  @Test func startLoadsTheCacheAndRefreshes() async throws {
    let cacheDirectory = temporaryDirectory()
    await makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory).refresh()
    let store = makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory)
    store.start()
    #expect(store.jiraTickets?.count == 2)
    try await waitUntil { store.jiraStatus != .idle }
    #expect(store.jiraStatus == .ok)
  }

  @Test func becomingActiveAfterAnAuthenticationFailureRefreshesAgain() async throws {
    let transport = try routingTransport(jira: 401)
    let store = makeStore(transport: transport, circleci: nil)
    store.start()
    try await waitUntil { store.jiraStatus != .idle && !store.isRefreshing }
    #expect(store.hasAuthenticationFailure)
    let requestCount = transport.requests.count
    store.start()
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    try await waitUntil { transport.requests.count > requestCount && !store.isRefreshing }
    #expect(transport.requests.count > requestCount)
  }
}

@MainActor struct QueueStoreBannerMessageTests {
  @Test func withoutDataTheBannerSaysHowToFixIt() async throws {
    let store = makeStore(token: .failure(.authentication), transport: try routingTransport(jira: 401, circleci: 401))
    await store.refresh()
    let now = Date()
    #expect(store.githubBannerMessage(now: now) == "Run gh auth login to show your PRs.")
    #expect(store.jiraBannerMessage(now: now) == "Check your Jira email and API token in Settings.")
    #expect(store.circleciBannerMessage(now: now) == "Check your CircleCI API token in Settings.")
  }

  @Test func withDataTheBannerGivesTheAgeAndTheCurrentSources() async throws {
    let store = makeStore(transport: try routingTransport())
    await store.refresh()
    let fetchedAt = try #require(store.githubFetchedAt)
    let now = fetchedAt.addingTimeInterval(300)
    #expect(store.githubBannerMessage(now: now) == "Showing PRs from 5 min ago. Jira and CircleCI are current.")
    #expect(store.jiraBannerMessage(now: now) == "Showing tickets from 5 min ago. GitHub and CircleCI are current.")
    #expect(store.circleciBannerMessage(now: now) == "Showing pipelines from 5 min ago. GitHub and Jira are current.")
  }
}
