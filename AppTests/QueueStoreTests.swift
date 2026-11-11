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

private func temporaryDefaults() -> UserDefaults {
  UserDefaults(suiteName: "tower-store-\(UUID().uuidString)")!
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
  circleci: CircleCISettings? = circleciSettings,
  githubOrganizations: [String] = [],
  defaults: UserDefaults = temporaryDefaults()
) -> QueueStore {
  QueueStore(
    tokenProvider: StubTokenProvider(result: token), transport: transport, cacheDirectory: cacheDirectory,
    loadJiraSettings: { jira }, loadCircleCISettings: { circleci },
    loadGitHubOrganizations: { githubOrganizations }, defaults: defaults)
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

private let failedPipeline = Pipeline(
  id: "pipeline-6000", projectSlug: "gh/acme/app-web", number: 6000, ref: "main", refIsTag: false,
  triggerType: "webhook", hasPullRequest: false, createdAt: Date(), state: .failed,
  url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/6000")!, newestWorkflowId: "workflow-1")

// A cache that holds only the failed pipeline, so loadCache shows one Fix row without a network call.
private func cacheDirectoryWithFailedPipeline() throws -> URL {
  let cacheDirectory = temporaryDirectory()
  try SourceCache(directory: cacheDirectory).save(Cached(value: [failedPipeline], fetchedAt: Date()), name: "circleci")
  return cacheDirectory
}

@MainActor struct QueueStoreDismissTests {
  @Test func dismissHidesTheFailedPipelineAndKeepsItForTheNextLaunch() throws {
    let cacheDirectory = try cacheDirectoryWithFailedPipeline()
    let defaults = temporaryDefaults()
    let store = makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory, defaults: defaults)
    store.loadCache()
    let fixItem = try #require(store.sections.first { $0.kind == .fix }?.items.first)
    store.dismiss(fixItem)
    #expect(store.sections.isEmpty)
    #expect(store.menuBarState == .normal)

    let relaunchedStore = makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory, defaults: defaults)
    relaunchedStore.loadCache()
    #expect(relaunchedStore.sections.isEmpty)
  }

  @Test func successfulRefreshDropsDismissalsOfPipelinesNoLongerReturned() async throws {
    let cacheDirectory = try cacheDirectoryWithFailedPipeline()
    let store = makeStore(transport: try routingTransport(), cacheDirectory: cacheDirectory)
    store.loadCache()
    store.dismiss(try #require(store.sections.first?.items.first))
    #expect(store.dismissedPipelines == [failedPipeline.dismissal])
    await store.refresh()
    #expect(store.dismissedPipelines.isEmpty)
  }

  @Test func failedRefreshKeepsDismissals() async throws {
    let cacheDirectory = try cacheDirectoryWithFailedPipeline()
    let store = makeStore(transport: try routingTransport(circleci: 500), cacheDirectory: cacheDirectory)
    store.loadCache()
    store.dismiss(try #require(store.sections.first?.items.first))
    await store.refresh()
    #expect(store.circleciStatus == .failed(.unexpected("HTTP 500")))
    #expect(store.dismissedPipelines == [failedPipeline.dismissal])
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

@MainActor struct QueueStoreOrganizationFilterTests {
  private let baseQueries = [
    "authoredQuery": "is:pr is:open author:@me archived:false",
    "requestedQuery": "is:pr is:open review-requested:@me archived:false",
  ]

  private func githubSearchVariables(in transport: StubTransport) throws -> [[String: String]] {
    try transport.requests.filter { $0.url?.host() == "api.github.com" }.map { githubRequest in
      let body = try #require(githubRequest.httpBody)
      let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      return try #require(payload["variables"] as? [String: String])
    }
  }

  private func searchVariables(organizations: [String]) async throws -> [String: String] {
    let transport = try routingTransport()
    let store = makeStore(transport: transport, githubOrganizations: organizations)
    await store.refresh()
    return try #require(try githubSearchVariables(in: transport).first)
  }

  private let queryNames = ["authoredQuery", "requestedQuery", "reviewedQuery", "mergedQuery"]

  @Test func emptyListLeavesTheFourQueriesUnchanged() async throws {
    let variables = try await searchVariables(organizations: [])
    for name in queryNames { #expect(!variables[name]!.contains("org:")) }
    #expect(variables["authoredQuery"] == baseQueries["authoredQuery"])
    #expect(variables["requestedQuery"] == baseQueries["requestedQuery"])
    #expect(variables["reviewedQuery"]!.hasPrefix("is:pr reviewed-by:@me -author:@me updated:>="))
    #expect(variables["mergedQuery"]!.hasPrefix("is:pr author:@me merged:>="))
  }

  @Test func twoOwnersAddBothQualifiersToAllFourQueries() async throws {
    let unfilteredVariables = try await searchVariables(organizations: [])
    let variables = try await searchVariables(organizations: ["acme", "side-project"])
    for name in queryNames {
      #expect(variables[name] == unfilteredVariables[name]! + " org:acme org:side-project")
    }
  }

  @Test func eachRefreshReadsTheCurrentOrganizations() async throws {
    let transport = try routingTransport()
    var currentOrganizations = ["acme"]
    let store = QueueStore(
      tokenProvider: StubTokenProvider(result: .success("gh-token")), transport: transport,
      cacheDirectory: temporaryDirectory(), loadJiraSettings: { jiraSettings },
      loadCircleCISettings: { circleciSettings }, loadGitHubOrganizations: { currentOrganizations })
    await store.refresh()
    currentOrganizations = ["side-project"]
    await store.refresh()
    let requestVariables = try githubSearchVariables(in: transport)
    #expect(requestVariables.count == 2)
    #expect(requestVariables[0]["authoredQuery"]!.hasSuffix(" org:acme"))
    #expect(requestVariables[1]["authoredQuery"]!.hasSuffix(" org:side-project"))
  }

  @Test func blankPaddedAndInvalidLinesYieldOnlyTrimmedValidLogins() async throws {
    let variables = try await searchVariables(
      organizations: ["  acme  ", "", "   ", "bad owner", "evil:qualifier", "under_score", "Side-Project"])
    for name in queryNames {
      #expect(variables[name]!.hasSuffix(" org:acme org:Side-Project"))
      #expect(variables[name]!.components(separatedBy: "org:").count == 3)
    }
  }

  @Test func onlyInvalidOrBlankLinesLeaveTheQueriesUnchanged() async throws {
    let unfilteredVariables = try await searchVariables(organizations: [])
    let variables = try await searchVariables(organizations: ["", "  ", "not valid", "a/b"])
    #expect(variables == unfilteredVariables)
  }
}
