import Core
import Foundation
import Testing

private let settings = CircleCISettings(apiToken: "circle-token", projectSlugs: ["gh/acme/app-web"])
private let now = isoDate("2027-01-15T12:00:00Z")

private func fractionalDate(_ text: String) -> Date {
  try! Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
}

private let workflowFixtureByPipelineId = [
  "017c68cd-10e2-44b1-82f2-aacb59609b9c": "circleci-workflows-success.json",
  "80f96bcb-62b4-4eee-9b92-24d709a8b5c3": "circleci-workflows-failed.json",
  "ecb77895-f2fd-4135-8535-a7d83b9c27fd": "circleci-workflows-success.json",
]

// Answers pipeline/mine with the recorded page and each workflow call with its recorded list.
private func fixtureTransport() -> StubTransport {
  StubTransport { request in
    let path = request.url!.path()
    if path.hasSuffix("/pipeline/mine") { return (try fixture("circleci-pipelines-mine.json"), 200) }
    let pipelineId = request.url!.deletingLastPathComponent().lastPathComponent
    return (try fixture(workflowFixtureByPipelineId[pipelineId]!), 200)
  }
}

// One pipeline/mine page that holds only the manual release, with its pipeline state and workflow list replaced.
private func releaseState(
  workflowFixture: String = "circleci-workflows-success.json", workflowData: Data? = nil, pipelineState: String = "created"
) async throws -> PipelineState {
  try await releasePipeline(workflowFixture: workflowFixture, workflowData: workflowData, pipelineState: pipelineState).state
}

private func releasePipeline(
  workflowFixture: String = "circleci-workflows-success.json", workflowData: Data? = nil, pipelineState: String = "created"
) async throws -> Pipeline {
  var page = try #require(try JSONSerialization.jsonObject(with: fixture("circleci-pipelines-mine.json")) as? [String: Any])
  var items = try #require(page["items"] as? [[String: Any]])
  var release = items[2]
  release["state"] = pipelineState
  items = [release]
  page["items"] = items
  let pageData = try JSONSerialization.data(withJSONObject: page)
  let workflowData = try workflowData ?? fixture(workflowFixture)
  let transport = StubTransport { request in
    (request.url!.path().hasSuffix("/pipeline/mine") ? pageData : workflowData, 200)
  }
  return try #require(try await CircleCIClient(settings: settings, transport: transport).fetch(now: now).first)
}

// One pipeline/mine page built from fixture items, each with its fields replaced.
private func pageData(_ itemChanges: [[String: Any]]) throws -> Data {
  var page = try #require(try JSONSerialization.jsonObject(with: fixture("circleci-pipelines-mine.json")) as? [String: Any])
  let template = try #require((page["items"] as? [[String: Any]])?[1])
  page["items"] = itemChanges.map { template.merging($0) { _, changed in changed } }
  return try JSONSerialization.data(withJSONObject: page)
}

private func vcs(branch: String, reviewUrl: String? = nil) -> [String: Any] {
  var vcs: [String: Any] = ["branch": branch]
  if let reviewUrl { vcs["review_url"] = reviewUrl }
  return vcs
}

// Holds each request for a moment and records the most requests in flight at once.
private final class SlowTransport: HTTPTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var inFlightCount = 0
  private var recordedMaxInFlight = 0
  private let pageData: Data
  private let workflowData: Data

  init(pageData: Data, workflowData: Data) {
    self.pageData = pageData
    self.workflowData = workflowData
  }

  var maxInFlight: Int { lock.withLock { recordedMaxInFlight } }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lock.withLock {
      inFlightCount += 1
      recordedMaxInFlight = max(recordedMaxInFlight, inFlightCount)
    }
    try await Task.sleep(for: .milliseconds(20))
    lock.withLock { inFlightCount -= 1 }
    let data = request.url!.path().hasSuffix("/pipeline/mine") ? pageData : workflowData
    return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }
}

// Each status gets its own workflow name, so no workflow is a rerun of another.
private func workflowList(statuses: [String]) throws -> Data {
  try workflowList(runs: statuses.enumerated().map { index, status in
    (name: "workflow-\(index)", status: status, createdAt: "2027-01-15T09:43:17.162Z")
  })
}

private func workflowList(runs: [(name: String, status: String, createdAt: String)]) throws -> Data {
  try workflowList(identifiedRuns: runs.map { (id: UUID().uuidString, name: $0.name, status: $0.status, createdAt: $0.createdAt) })
}

private func workflowList(identifiedRuns runs: [(id: String, name: String, status: String, createdAt: String)]) throws -> Data {
  let items = runs.map { ["id": $0.id, "name": $0.name, "status": $0.status, "created_at": $0.createdAt] }
  return try JSONSerialization.data(withJSONObject: ["items": items])
}

struct CircleCIClientTests {
  @Test func decodesFixtureIntoPipelines() async throws {
    let pipelines = try await CircleCIClient(settings: settings, transport: fixtureTransport()).fetch(now: now)
    #expect(pipelines == [
      Pipeline(
        id: "017c68cd-10e2-44b1-82f2-aacb59609b9c", projectSlug: "gh/acme/app-web", number: 6053, ref: "fix-e2e-cleanup",
        refIsTag: false, triggerType: "webhook", hasPullRequest: true, createdAt: fractionalDate("2027-01-15T11:02:34.621Z"),
        state: .succeeded, url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/6053")!,
        newestWorkflowId: nil),
      Pipeline(
        id: "80f96bcb-62b4-4eee-9b92-24d709a8b5c3", projectSlug: "gh/acme/app-web", number: 6000, ref: "main",
        refIsTag: false, triggerType: "webhook", hasPullRequest: false, createdAt: fractionalDate("2027-01-15T09:43:16.805Z"),
        state: .failed, url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/6000")!,
        newestWorkflowId: "ab430a84-e501-4529-b4c9-20cc4c4a75e6"),
      Pipeline(
        id: "ecb77895-f2fd-4135-8535-a7d83b9c27fd", projectSlug: "gh/acme/app-web", number: 5952, ref: "main",
        refIsTag: false, triggerType: "api", hasPullRequest: false, createdAt: fractionalDate("2027-01-14T20:12:44.208Z"),
        state: .succeeded, url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/5952")!,
        newestWorkflowId: "ab5d9618-5c36-4df1-8648-dbec8ff09e11"),
    ])
  }

  @Test func sendsCircleTokenToEachProjectURL() async throws {
    let transport = fixtureTransport()
    let twoProjects = CircleCISettings(apiToken: "circle-token", projectSlugs: ["gh/acme/app-web", "gh/acme/app-api"])
    _ = try await CircleCIClient(settings: twoProjects, transport: transport).fetch(now: now)
    let pipelineRequests = transport.requests.filter { $0.url!.path().hasSuffix("/pipeline/mine") }
    #expect(Set(pipelineRequests.map(\.url!.absoluteString)) == [
      "https://circleci.com/api/v2/project/gh/acme/app-web/pipeline/mine",
      "https://circleci.com/api/v2/project/gh/acme/app-api/pipeline/mine",
    ])
    #expect(transport.requests.contains { $0.url!.absoluteString == "https://circleci.com/api/v2/pipeline/80f96bcb-62b4-4eee-9b92-24d709a8b5c3/workflow" })
    #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Circle-Token") == "circle-token" })
  }

  @Test(arguments: [
    nil,
    CircleCISettings(apiToken: "", projectSlugs: ["gh/acme/app-web"]),
    CircleCISettings(apiToken: "circle-token", projectSlugs: []),
  ])
  func missingSettingsIsNotConfiguredWithoutRequest(settings: CircleCISettings?) async {
    let transport = StubTransport { _ in (Data(), 200) }
    await #expect(throws: SourceFailure.notConfigured) {
      try await CircleCIClient(settings: settings, transport: transport).fetch(now: now)
    }
    #expect(transport.requests.isEmpty)
  }

  @Test func unauthorizedResponseIsAuthenticationFailure() async {
    let transport = StubTransport { _ in (Data(), 401) }
    await #expect(throws: SourceFailure.authentication) {
      try await CircleCIClient(settings: settings, transport: transport).fetch(now: now)
    }
  }

  @Test func failureInOneProjectFailsTheFetch() async {
    let pageData = try! fixture("circleci-pipelines-mine.json")
    let workflowData = try! fixture("circleci-workflows-success.json")
    let transport = StubTransport { request in
      let path = request.url!.path()
      if path.contains("/app-api/") { return (Data(), 500) }
      return (path.hasSuffix("/pipeline/mine") ? pageData : workflowData, 200)
    }
    let twoProjects = CircleCISettings(apiToken: "circle-token", projectSlugs: ["gh/acme/app-web", "gh/acme/app-api"])
    await #expect(throws: SourceFailure.unexpected("HTTP 500")) {
      try await CircleCIClient(settings: twoProjects, transport: transport).fetch(now: now)
    }
  }

  @Test func unknownProjectSlugNamesTheSlug() async {
    let pageData = try! fixture("circleci-pipelines-mine.json")
    let workflowData = try! fixture("circleci-workflows-success.json")
    let transport = StubTransport { request in
      let path = request.url!.path()
      if path.contains("/app-typo/") { return (Data(), 404) }
      return (path.hasSuffix("/pipeline/mine") ? pageData : workflowData, 200)
    }
    let typoProject = CircleCISettings(apiToken: "circle-token", projectSlugs: ["gh/acme/app-web", "gh/acme/app-typo"])
    await #expect(throws: SourceFailure.unexpected("gh/acme/app-typo not found")) {
      try await CircleCIClient(settings: typoProject, transport: transport).fetch(now: now)
    }
  }

  @Test func slugThatCannotFormURLNamesTheSlugWithoutRequest() async {
    let transport = StubTransport { _ in (Data(), 200) }
    let badSlug = CircleCISettings(apiToken: "circle-token", projectSlugs: ["gh/acme/app web"])
    await #expect(throws: SourceFailure.unexpected("gh/acme/app web not found")) {
      try await CircleCIClient(settings: badSlug, transport: transport).fetch(now: now)
    }
    #expect(transport.requests.isEmpty)
  }

  @Test func slugWhitespaceIsTrimmed() async throws {
    let transport = fixtureTransport()
    let paddedSlug = CircleCISettings(apiToken: "circle-token", projectSlugs: ["  gh/acme/app-web \t"])
    _ = try await CircleCIClient(settings: paddedSlug, transport: transport).fetch(now: now)
    #expect(transport.requests.first?.url?.absoluteString == "https://circleci.com/api/v2/project/gh/acme/app-web/pipeline/mine")
  }

  @Test func skipsPipelinesOlderThanOneDay() async throws {
    let transport = fixtureTransport()
    let pipelines = try await CircleCIClient(settings: settings, transport: transport).fetch(now: isoDate("2027-01-15T21:00:00Z"))
    #expect(pipelines.map(\.number) == [6053, 6000])
    #expect(!transport.requests.contains { $0.url!.path().contains("ecb77895-f2fd-4135-8535-a7d83b9c27fd") })
  }

  @Test func onHoldWorkflowIsOnHold() async throws {
    #expect(try await releaseState(workflowFixture: "circleci-workflows-on-hold.json") == .onHold)
  }

  @Test func failedWorkflowNextToSucceededSetupIsFailed() async throws {
    #expect(try await releaseState(workflowFixture: "circleci-workflows-failed.json") == .failed)
  }

  @Test func runningWorkflowIsRunning() async throws {
    #expect(try await releaseState(workflowFixture: "circleci-workflows-running.json") == .running)
  }

  @Test func succeededWorkflowsAreSucceeded() async throws {
    #expect(try await releaseState(workflowFixture: "circleci-workflows-success.json") == .succeeded)
  }

  @Test func successfulRerunAfterFailedRunsIsSucceeded() async throws {
    let workflowData = try workflowList(runs: [
      (name: "setup", status: "success", createdAt: "2027-01-15T09:43:17.162Z"),
      (name: "trunk-based", status: "failed", createdAt: "2027-01-15T09:44:25.166Z"),
      (name: "trunk-based", status: "failed", createdAt: "2027-01-15T10:10:02.511Z"),
      (name: "trunk-based", status: "success", createdAt: "2027-01-15T10:40:48.903Z"),
    ])
    #expect(try await releaseState(workflowData: workflowData) == .succeeded)
  }

  @Test func failedRerunAfterSuccessfulRunIsFailed() async throws {
    let workflowData = try workflowList(runs: [
      (name: "trunk-based", status: "success", createdAt: "2027-01-15T09:44:25.166Z"),
      (name: "trunk-based", status: "failed", createdAt: "2027-01-15T10:10:02.511Z"),
    ])
    #expect(try await releaseState(workflowData: workflowData) == .failed)
  }

  @Test func runningRerunAfterFailedRunIsRunning() async throws {
    let workflowData = try workflowList(runs: [
      (name: "trunk-based", status: "running", createdAt: "2027-01-15T10:10:02.511Z"),
      (name: "trunk-based", status: "failed", createdAt: "2027-01-15T09:44:25.166Z"),
    ])
    #expect(try await releaseState(workflowData: workflowData) == .running)
  }

  @Test func newestWorkflowIdIsTheNewestRunOfAnyName() async throws {
    let workflowData = try workflowList(identifiedRuns: [
      (id: "setup-run", name: "setup", status: "success", createdAt: "2027-01-15T09:43:17.162Z"),
      (id: "rerun", name: "trunk-based", status: "failed", createdAt: "2027-01-15T10:10:02.511Z"),
      (id: "first-run", name: "trunk-based", status: "failed", createdAt: "2027-01-15T09:44:25.166Z"),
    ])
    #expect(try await releasePipeline(workflowData: workflowData).newestWorkflowId == "rerun")
  }

  @Test func erroredPipelineHasNoNewestWorkflowId() async throws {
    #expect(try await releasePipeline(pipelineState: "errored").newestWorkflowId == nil)
  }

  @Test func erroredPipelineIsFailed() async throws {
    #expect(try await releaseState(pipelineState: "errored") == .failed)
  }

  @Test(arguments: [
    (["success", "canceled"], PipelineState.succeeded),
    (["error"], .failed),
    (["failing", "success"], .failed),
    (["unauthorized"], .failed),
    (["not_run"], .succeeded),
    (["success", "not_run"], .succeeded),
    (["on_hold", "failed"], .failed),
    (["on_hold", "running"], .onHold),
    (["running", "not_run"], .running),
    ([], .succeeded),
  ])
  func workflowStatusesMapToState(statuses: [String], expectedState: PipelineState) async throws {
    let pageData = try fixture("circleci-pipelines-mine.json")
    let workflowData = try workflowList(statuses: statuses)
    let transport = StubTransport { request in
      (request.url!.path().hasSuffix("/pipeline/mine") ? pageData : workflowData, 200)
    }
    let pipelines = try await CircleCIClient(settings: settings, transport: transport).fetch(now: now)
    #expect(pipelines.filter { !$0.hasPullRequest }.map(\.state) == [expectedState, expectedState])
  }

  @Test(arguments: [
    ("setup-pending", PipelineState.running),
    ("setup", .running),
    ("pending", .running),
    ("created", .succeeded),
    ("errored", .failed),
  ])
  func pipelineWithoutWorkflowsMapsFromPipelineState(pipelineState: String, expectedState: PipelineState) async throws {
    #expect(try await releaseState(workflowData: try workflowList(statuses: []), pipelineState: pipelineState) == expectedState)
  }

  @Test func skipsWorkflowRequestForPipelineWithPullRequest() async throws {
    let transport = fixtureTransport()
    _ = try await CircleCIClient(settings: settings, transport: transport).fetch(now: now)
    #expect(!transport.requests.contains { $0.url!.path().contains("017c68cd-10e2-44b1-82f2-aacb59609b9c") })
  }

  @Test func readsWorkflowsOnlyForNewestPipelinePerKey() async throws {
    let page = try pageData([
      ["id": "newer", "number": 2, "created_at": "2027-01-15T11:00:00.000Z", "vcs": vcs(branch: "main")],
      ["id": "older", "number": 1, "created_at": "2027-01-15T10:00:00.000Z", "vcs": vcs(branch: "main")],
    ])
    let workflowData = try workflowList(statuses: ["success"])
    let transport = StubTransport { request in (request.url!.path().hasSuffix("/pipeline/mine") ? page : workflowData, 200) }
    let pipelines = try await CircleCIClient(settings: settings, transport: transport).fetch(now: now)
    #expect(pipelines.map(\.number) == [2])
    #expect(transport.requests.filter { $0.url!.path().hasSuffix("/workflow") }.map { $0.url!.path() } == ["/api/v2/pipeline/newer/workflow"])
  }

  @Test func newerPullRequestPipelineSkipsWorkflowsForTheKey() async throws {
    let page = try pageData([
      ["id": "newer", "number": 2, "created_at": "2027-01-15T11:00:00.000Z",
       "vcs": vcs(branch: "feature/x", reviewUrl: "https://github.com/acme/app-web/pull/7")],
      ["id": "older", "number": 1, "created_at": "2027-01-15T10:00:00.000Z", "vcs": vcs(branch: "feature/x")],
    ])
    let transport = StubTransport { _ in (page, 200) }
    let pipelines = try await CircleCIClient(settings: settings, transport: transport).fetch(now: now)
    #expect(pipelines.map(\.number) == [2])
    #expect(transport.requests.count == 1)
  }

  @Test func capsWorkflowRequestsInFlight() async throws {
    let page = try pageData((1...10).map { index in
      ["id": "pipeline-\(index)", "number": index, "vcs": vcs(branch: "branch-\(index)")]
    })
    let transport = SlowTransport(pageData: page, workflowData: try workflowList(statuses: ["success"]))
    let pipelines = try await CircleCIClient(settings: settings, transport: transport).fetch(now: now)
    #expect(pipelines.count == 10)
    #expect(transport.maxInFlight == 4)
  }
}
