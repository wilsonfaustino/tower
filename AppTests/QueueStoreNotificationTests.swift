import Core
import Foundation
import Testing

@testable import Tower

@MainActor private final class FakeNotifier: Notifier {
  var postedEvents: [NotificationEvent] = []
  func post(_ event: NotificationEvent) { postedEvents.append(event) }
  func requestAuthorization() {}
}

private struct StubTokenProvider: GitHubTokenProvider {
  func token() async throws(SourceFailure) -> String { "gh-token" }
}

// The test changes the values only between refreshes, so no lock is needed.
private final class CircleCIResponse: @unchecked Sendable {
  var workflowStatus = "running"
  var statusCode = 200
  var workflowStatusCode = 200
  var hasPullRequest = false
}

private let pipelineCreatedAt = Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))

// The fixture with the first authored PR given this many approvals.
private func githubData(approvals: Int) throws -> Data {
  var response = try #require(try JSONSerialization.jsonObject(with: fixture("github-search.json")) as? [String: Any])
  var data = try #require(response["data"] as? [String: Any])
  var authored = try #require(data["authored"] as? [String: Any])
  var nodes = try #require(authored["nodes"] as? [[String: Any]])
  nodes[0]["latestOpinionatedReviews"] = ["nodes": Array(repeating: ["state": "APPROVED"], count: approvals)]
  authored["nodes"] = nodes
  data["authored"] = authored
  response["data"] = data
  return try JSONSerialization.data(withJSONObject: response)
}

// The test changes the values only between refreshes, so no lock is needed.
private final class GitHubResponse: @unchecked Sendable {
  var body: Data
  init(body: Data) { self.body = body }
}

private func githubTransport(_ response: GitHubResponse) -> StubTransport {
  StubTransport { request in
    request.url?.host() == "api.github.com" ? (response.body, 200) : (Data(#"{"items":[]}"#.utf8), 200)
  }
}

// One branch pipeline, with or without a PR. Its state comes from the one workflow the stub returns.
private func circleciTransport(_ response: CircleCIResponse) throws -> StubTransport {
  let githubData = try fixture("github-search.json")
  return StubTransport { request in
    guard request.url?.host() == "circleci.com" else { return (githubData, 200) }
    if request.url!.path().hasSuffix("/workflow") {
      let body = #"{"items":[{"id":"workflow-1","name":"build","status":"\#(response.workflowStatus)","created_at":"\#(pipelineCreatedAt)"}]}"#
      return (Data(body.utf8), response.workflowStatusCode)
    }
    let reviewURL = response.hasPullRequest ? #","review_url":"https://github.com/acme/app-web/pull/7""# : ""
    let body = #"{"items":[{"id":"pipeline-1","number":7,"state":"created","created_at":"\#(pipelineCreatedAt)","project_slug":"gh/acme/app-web","trigger":{"type":"webhook"},"vcs":{"branch":"main"\#(reviewURL)}}]}"#
    return (Data(body.utf8), response.statusCode)
  }
}

// The test changes the values only between refreshes, so no lock is needed.
private final class SettingsBox: @unchecked Sendable {
  var organizations: [String] = []
  var circleciToken = "circle-token"
}

@MainActor private func makeStore(
  transport: StubTransport, notifier: FakeNotifier, cacheDirectory: URL? = nil,
  enabledKinds: Set<NotificationEventKind> = Set(NotificationEventKind.allCases), settings: SettingsBox = SettingsBox()
) -> QueueStore {
  QueueStore(
    tokenProvider: StubTokenProvider(), transport: transport,
    cacheDirectory: cacheDirectory
      ?? FileManager.default.temporaryDirectory.appendingPathComponent("tower-notify-\(UUID().uuidString)"),
    loadJiraSettings: { nil },
    loadCircleCISettings: { CircleCISettings(apiToken: settings.circleciToken, projectSlugs: ["gh/acme/app-web"]) },
    loadGitHubOrganizations: { settings.organizations }, notifier: notifier, loadEnabledNotificationKinds: { enabledKinds },
    defaults: UserDefaults(suiteName: "tower-notify-\(UUID().uuidString)")!)
}

@MainActor struct QueueStoreNotificationTests {
  @Test func firstRefreshPostsNothing() async throws {
    let response = CircleCIResponse()
    response.workflowStatus = "failed"
    let notifier = FakeNotifier()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier)
    await store.refresh()
    #expect(store.pipelines?.first?.state == .failed)
    #expect(notifier.postedEvents.isEmpty)
  }

  @Test func secondRefreshWithAChangePostsTheEvent() async throws {
    let response = CircleCIResponse()
    let notifier = FakeNotifier()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier)
    await store.refresh()
    response.workflowStatus = "failed"
    await store.refresh()
    #expect(notifier.postedEvents.map(\.kind) == [.ciFailed])
    #expect(notifier.postedEvents.first?.body == "main\napp-web #7")
    await store.refresh()
    #expect(notifier.postedEvents.count == 1)
  }

  @Test func pullRequestPipelineOnHoldPostsCINeedsApproval() async throws {
    let response = CircleCIResponse()
    response.hasPullRequest = true
    let notifier = FakeNotifier()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier)
    await store.refresh()
    response.workflowStatus = "on_hold"
    await store.refresh()
    #expect(notifier.postedEvents.map(\.kind) == [.ciNeedsApproval])
  }

  // A failed workflow read keeps the last known state, so the same hold does not post twice.
  @Test func failedWorkflowReadBetweenTwoHoldsPostsOnce() async throws {
    let response = CircleCIResponse()
    response.hasPullRequest = true
    let notifier = FakeNotifier()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier)
    await store.refresh()
    response.workflowStatus = "on_hold"
    await store.refresh()
    response.workflowStatusCode = 502
    await store.refresh()
    response.workflowStatusCode = 200
    await store.refresh()
    #expect(notifier.postedEvents.map(\.kind) == [.ciNeedsApproval])
  }

  // As at launch, a hold that was there before the first read Tower trusts is not news.
  @Test func holdFirstReadAfterAFailedReadPostsNothing() async throws {
    let response = CircleCIResponse()
    response.hasPullRequest = true
    response.workflowStatus = "on_hold"
    response.workflowStatusCode = 502
    let notifier = FakeNotifier()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier)
    await store.refresh()
    response.workflowStatusCode = 200
    await store.refresh()
    #expect(notifier.postedEvents.isEmpty)
    response.workflowStatus = "running"
    await store.refresh()
    response.workflowStatus = "on_hold"
    await store.refresh()
    #expect(notifier.postedEvents.map(\.kind) == [.ciNeedsApproval])
  }

  // The failed read keeps the known running state, so the hold after it is still a change.
  @Test func holdAfterAFailedReadOfARunningPipelinePosts() async throws {
    let response = CircleCIResponse()
    response.hasPullRequest = true
    let notifier = FakeNotifier()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier)
    await store.refresh()
    response.workflowStatusCode = 502
    await store.refresh()
    response.workflowStatusCode = 200
    response.workflowStatus = "on_hold"
    await store.refresh()
    #expect(notifier.postedEvents.map(\.kind) == [.ciNeedsApproval])
  }

  @Test func cachedDataIsNotTheBaseline() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("tower-notify-\(UUID().uuidString)")
    let runningPipeline = Pipeline(
      id: "pipeline-1", projectSlug: "gh/acme/app-web", number: 7, ref: "main", refIsTag: false,
      triggerType: "webhook", hasPullRequest: false, createdAt: Date(), state: .running,
      url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/7")!, newestWorkflowId: "workflow-1")
    try SourceCache(directory: cacheDirectory).save(Cached(value: [runningPipeline], fetchedAt: Date()), name: "circleci")
    let response = CircleCIResponse()
    response.workflowStatus = "failed"
    let notifier = FakeNotifier()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier, cacheDirectory: cacheDirectory)
    store.loadCache()
    #expect(store.pipelines?.first?.state == .running)
    await store.refresh()
    #expect(notifier.postedEvents.isEmpty)
  }

  @Test func failedFetchPostsNothingAndKeepsTheBaseline() async throws {
    let response = CircleCIResponse()
    let notifier = FakeNotifier()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier)
    await store.refresh()
    response.statusCode = 500
    await store.refresh()
    #expect(store.circleciStatus == .failed(.unexpected("HTTP 500")))
    #expect(notifier.postedEvents.isEmpty)
    response.statusCode = 200
    response.workflowStatus = "failed"
    await store.refresh()
    #expect(notifier.postedEvents.map(\.kind) == [.ciFailed])
  }

  @Test func newCircleCITokenStartsANewBaseline() async throws {
    let response = CircleCIResponse()
    let notifier = FakeNotifier()
    let settings = SettingsBox()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier, settings: settings)
    await store.refresh()
    settings.circleciToken = "other-account-token"
    response.workflowStatus = "failed"
    await store.refresh()
    #expect(notifier.postedEvents.isEmpty)
  }

  @Test func kindThatIsOffIsNotPosted() async throws {
    let response = CircleCIResponse()
    let notifier = FakeNotifier()
    let store = makeStore(
      transport: try circleciTransport(response), notifier: notifier, enabledKinds: [.ciPassed, .ciNeedsApproval])
    await store.refresh()
    response.workflowStatus = "failed"
    await store.refresh()
    #expect(notifier.postedEvents.isEmpty)
  }

  @Test func dismissedPipelinePostsNothing() async throws {
    let response = CircleCIResponse()
    response.workflowStatus = "failed"
    let notifier = FakeNotifier()
    let store = makeStore(transport: try circleciTransport(response), notifier: notifier)
    await store.refresh()
    let failedItem = try #require(store.sections.flatMap(\.items).first { $0.dismissal != nil && $0.title == "main" })
    store.dismiss(failedItem)
    response.workflowStatus = "running"
    await store.refresh()
    response.workflowStatus = "failed"
    await store.refresh()
    #expect(notifier.postedEvents.isEmpty)
  }
}

@MainActor struct QueueStoreGitHubNotificationTests {
  @Test func higherApprovalCountPostsApproved() async throws {
    let response = GitHubResponse(body: try githubData(approvals: 0))
    let notifier = FakeNotifier()
    let store = makeStore(transport: githubTransport(response), notifier: notifier)
    await store.refresh()
    response.body = try githubData(approvals: 1)
    await store.refresh()
    #expect(notifier.postedEvents.map(\.kind) == [.approvalReceived])
    #expect(notifier.postedEvents.first?.url == URL(string: "https://github.com/acme/app-web/pull/2184"))
  }

  @Test func newOrganizationsStartANewBaseline() async throws {
    let response = GitHubResponse(body: try githubData(approvals: 0))
    let notifier = FakeNotifier()
    let settings = SettingsBox()
    let store = makeStore(transport: githubTransport(response), notifier: notifier, settings: settings)
    await store.refresh()
    settings.organizations = ["acme"]
    response.body = try githubData(approvals: 1)
    await store.refresh()
    #expect(notifier.postedEvents.isEmpty)
  }

  // A direct only fetch leaves out team requests, so the next fetch for every request would see them as new.
  @Test func newReviewRequestScopeStartsANewBaseline() async throws {
    let transport = StubTransport { request in
      request.url?.host() == "api.github.com"
        ? (try githubFixture(answering: request), 200) : (Data(#"{"items":[]}"#.utf8), 200)
    }
    let notifier = FakeNotifier()
    let store = makeStore(transport: transport, notifier: notifier)
    store.reviewRequestScope = .directOnly
    await store.refresh()
    store.reviewRequestScope = .directAndTeam
    await store.refresh()
    await store.refresh()
    #expect(store.githubSnapshot?.reviewRequests.count == 3)
    #expect(notifier.postedEvents.isEmpty)
  }

  @Test func pullRequestMissingFromOneResponsePostsNothingWhenItReturns() async throws {
    let fullBody = try githubData(approvals: 1)
    var response = try #require(try JSONSerialization.jsonObject(with: fullBody) as? [String: Any])
    var data = try #require(response["data"] as? [String: Any])
    var authored = try #require(data["authored"] as? [String: Any])
    var nodes = try #require(authored["nodes"] as? [Any])
    nodes[0] = NSNull()
    authored["nodes"] = nodes
    data["authored"] = authored
    response["data"] = data
    let githubResponse = GitHubResponse(body: fullBody)
    let notifier = FakeNotifier()
    let store = makeStore(transport: githubTransport(githubResponse), notifier: notifier)
    await store.refresh()
    githubResponse.body = try JSONSerialization.data(withJSONObject: response)
    await store.refresh()
    githubResponse.body = fullBody
    await store.refresh()
    #expect(notifier.postedEvents.isEmpty)
  }

  @Test func demoModePostsNothing() async throws {
    let notifier = FakeNotifier()
    let store = makeStore(transport: githubTransport(GitHubResponse(body: try githubData(approvals: 0))), notifier: notifier)
    store.demoScenario = DemoScenario(name: .clearSkies, now: .now)
    await store.refresh()
    store.demoScenario = DemoScenario(name: .typical, now: .now)
    await store.refresh()
    #expect(!store.sections.isEmpty)
    #expect(notifier.postedEvents.isEmpty)
  }

  @Test func notifyDemoPostsEachKindOnceOnTheFirstRefresh() async throws {
    let notifier = FakeNotifier()
    let store = makeStore(transport: githubTransport(GitHubResponse(body: try githubData(approvals: 0))), notifier: notifier)
    store.demoScenario = DemoScenario(name: .notify, now: .now)
    store.start()
    #expect(notifier.postedEvents.isEmpty)
    await store.refresh()
    #expect(notifier.postedEvents.map(\.kind).sorted { $0.rawValue < $1.rawValue }
      == NotificationEventKind.allCases.sorted { $0.rawValue < $1.rawValue })
    #expect(store.pipelines?.contains { $0.number == 1204 && $0.state == .onHold } == true)
    await store.refresh()
    #expect(notifier.postedEvents.count == NotificationEventKind.allCases.count)
  }
}

struct NotificationSettingsKeysTests {
  @Test func everyKindIsOnWhenNothingIsSaved() {
    let defaults = UserDefaults(suiteName: "tower-notify-\(UUID().uuidString)")!
    #expect(NotificationSettingsKeys.enabledKinds(defaults: defaults) == Set(NotificationEventKind.allCases))
  }

  @Test func kindSavedAsOffIsLeftOut() {
    let defaults = UserDefaults(suiteName: "tower-notify-\(UUID().uuidString)")!
    defaults.set(false, forKey: NotificationSettingsKeys.key(.ciPassed))
    #expect(!NotificationSettingsKeys.enabledKinds(defaults: defaults).contains(.ciPassed))
    #expect(NotificationSettingsKeys.enabledKinds(defaults: defaults).count == 4)
  }
}

struct UserNotificationRequestTests {
  @Test func requestCarriesTheEventIdTextAndURL() {
    let event = NotificationEvent(
      kind: .approvalReceived, id: "approvalReceived:pr:app-web#1:approvals=1", body: "Add login\napp-web #1",
      url: URL(string: "https://github.com/acme/app-web/pull/1")!)
    let request = UserNotificationNotifier.request(for: event)
    #expect(request.identifier == event.id)
    #expect(request.content.title == "Approved")
    #expect(request.content.body == "Add login\napp-web #1")
    #expect(UserNotificationNotifier.url(fromUserInfo: request.content.userInfo) == event.url)
  }
}
