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
private func releaseState(workflowFixture: String = "circleci-workflows-success.json", pipelineState: String = "created") async throws -> PipelineState {
  var page = try #require(try JSONSerialization.jsonObject(with: fixture("circleci-pipelines-mine.json")) as? [String: Any])
  var items = try #require(page["items"] as? [[String: Any]])
  var release = items[2]
  release["state"] = pipelineState
  items = [release]
  page["items"] = items
  let pageData = try JSONSerialization.data(withJSONObject: page)
  let workflowData = try fixture(workflowFixture)
  let transport = StubTransport { request in
    (request.url!.path().hasSuffix("/pipeline/mine") ? pageData : workflowData, 200)
  }
  return try #require(try await CircleCIClient(settings: settings, transport: transport).fetch(now: now).first).state
}

private func workflowList(statuses: [String]) throws -> Data {
  let items = statuses.map { ["id": UUID().uuidString, "name": "release", "status": $0] }
  return try JSONSerialization.data(withJSONObject: ["items": items])
}

struct CircleCIClientTests {
  @Test func decodesFixtureIntoPipelines() async throws {
    let pipelines = try await CircleCIClient(settings: settings, transport: fixtureTransport()).fetch(now: now)
    #expect(pipelines == [
      Pipeline(
        projectSlug: "gh/acme/app-web", number: 6053, ref: "fix-e2e-cleanup", refIsTag: false, triggerType: "webhook",
        hasPullRequest: true, createdAt: fractionalDate("2027-01-15T11:02:34.621Z"), state: .succeeded,
        url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/6053")!),
      Pipeline(
        projectSlug: "gh/acme/app-web", number: 6000, ref: "main", refIsTag: false, triggerType: "webhook",
        hasPullRequest: false, createdAt: fractionalDate("2027-01-15T09:43:16.805Z"), state: .failed,
        url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/6000")!),
      Pipeline(
        projectSlug: "gh/acme/app-web", number: 5952, ref: "main", refIsTag: false, triggerType: "api",
        hasPullRequest: false, createdAt: fractionalDate("2027-01-14T20:12:44.208Z"), state: .succeeded,
        url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/5952")!),
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
    #expect(pipelines.map(\.state) == [expectedState, expectedState, expectedState])
  }
}
