import Core
import Foundation
import Testing

private struct StubTokenProvider: GitHubTokenProvider {
  var result: Result<String, SourceFailure>
  func token() async throws(SourceFailure) -> String { try result.get() }
}

private let now = isoDate("2027-01-15T12:00:00Z")

private final class AttemptCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var attempts = 0

  var count: Int { lock.withLock { attempts } }

  func next() -> Int {
    lock.withLock {
      attempts += 1
      return attempts
    }
  }
}

// Holds every request until the summary and an authored page have both started.
private actor RequestRendezvous {
  private var startedKinds: Set<String> = []
  private var waitingRequests: [CheckedContinuation<Void, Never>] = []

  func arrive(_ kind: String) async {
    startedKinds.insert(kind)
    if startedKinds.count == 2 {
      waitingRequests.forEach { $0.resume() }
      waitingRequests = []
      return
    }
    await withCheckedContinuation { waitingRequests.append($0) }
  }
}

private struct RendezvousTransport: HTTPTransport {
  let body: Data
  let rendezvous = RequestRendezvous()

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    await rendezvous.arrive(try variables(in: request)["authoredQuery"] != nil ? "authored" : "summary")
    return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }
}

// Answers the summary with 401 and holds every authored request until it is cancelled.
private final class CancellationRecordingTransport: HTTPTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  var authoredRequestWasCancelled: Bool { lock.withLock { cancelled } }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let isAuthored = try variables(in: request)["authoredQuery"] != nil
    if isAuthored {
      do {
        try await Task.sleep(for: .seconds(30))
      } catch {
        lock.withLock { cancelled = true }
        throw error
      }
    }
    return (Data(), HTTPURLResponse(url: request.url!, statusCode: isAuthored ? 200 : 401, httpVersion: nil, headerFields: nil)!)
  }
}

private func authoredPage(_ fixtureData: Data, hasNextPage: Bool, endCursor: String?) throws -> Data {
  var page = try #require(try JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
  var pageData = try #require(page["data"] as? [String: Any])
  var pageAuthored = try #require(pageData["authored"] as? [String: Any])
  pageAuthored["pageInfo"] = ["hasNextPage": hasNextPage, "endCursor": endCursor.map { $0 as Any } ?? NSNull()]
  pageData["authored"] = pageAuthored
  page["data"] = pageData
  return try JSONSerialization.data(withJSONObject: page)
}

private func client(token: Result<String, SourceFailure> = .success("secret-token"), transport: StubTransport) -> GitHubClient {
  GitHubClient(tokenProvider: StubTokenProvider(result: token), transport: transport)
}

private func authoredStripPullRequests() async throws -> [PullRequest] {
  let fixtureData = try fixture("github-search-authored-strip.json")
  return try await client(transport: StubTransport { _ in (fixtureData, 200) }).fetch(now: now).authoredPullRequests
}

struct GitHubClientTests {
  @Test func decodesFixtureIntoSnapshot() async throws {
    let fixtureData = try fixture("github-search.json")
    let snapshot = try await client(transport: StubTransport { _ in (fixtureData, 200) }).fetch(now: now)
    #expect(snapshot.viewerLogin == "octo-me")
    #expect(snapshot.authoredPullRequests.count == 2)
    #expect(snapshot.reviewRequests.count == 3)
    #expect(snapshot.reviewsSubmittedToday == 4)
    #expect(snapshot.mergedToday == 2)
    let failing = snapshot.authoredPullRequests[0]
    #expect(failing.repository == "app-web")
    #expect(failing.number == 2184)
    #expect(failing.title == "Migrate field map to MapLibre 4")
    #expect(failing.url == URL(string: "https://github.com/acme/app-web/pull/2184"))
    #expect(failing.author == "octo-me")
    #expect(failing.isDraft == false)
    #expect(failing.updatedAt == isoDate("2027-01-15T11:35:00Z"))
    #expect(failing.headBranch == "proj-1201-maplibre")
    #expect(failing.baseBranch == "proj-1200-map")
    #expect(failing.isCrossRepository == false)
    #expect(snapshot.authoredPullRequests[1].baseBranch == nil)
    #expect(failing.reviewDecision == .reviewRequired)
    #expect(failing.checkState == .failure)
    #expect(failing.failedCheckCount == 3)
    #expect(failing.additions == 120)
    #expect(failing.deletions == 80)
    #expect(failing.requestedReviewerLogins == ["ana"])
    #expect(failing.requestedTeamSlugs == [])
    #expect(failing.reviewCount == 0)
    #expect(failing.reviewRequestedAt == isoDate("2027-01-14T10:00:00Z"))
    #expect(snapshot.reviewRequests[0].requestedTeamSlugs == ["web-core"])
    #expect(snapshot.reviewRequests[0].viewerLatestReviewState == .approved)
    #expect(snapshot.reviewRequests[0].reviewCount == 0)
    #expect(snapshot.reviewRequests[1].viewerLatestReviewState == .commented)
    #expect(snapshot.reviewRequests[2].viewerLatestReviewState == nil)
    #expect(snapshot.reviewRequests[1].checkState == nil)
    #expect(snapshot.reviewRequests[1].requestedReviewerLogins == ["octo-me"])
    #expect(snapshot.authoredPullRequests[1].reviewRequestedAt == nil)
    #expect(failing.authorIsBot == false)
    #expect(snapshot.reviewRequests[2].author == "dependabot")
    #expect(snapshot.reviewRequests[2].authorIsBot == true)
    #expect(snapshot.reviewRequests[2].headCommitId == "9f2c4e1a7b3d5f60e8c1a2b4d6f8e0a1c3e5b7d9")
    #expect(snapshot.reviewRequests[1].headCommitId == nil)
  }

  @Test func sendsBearerTokenToGraphQLEndpoint() async throws {
    let fixtureData = try fixture("github-search.json")
    let transport = StubTransport { _ in (fixtureData, 200) }
    _ = try await client(transport: transport).fetch(now: now)
    let request = try #require(transport.requests.first)
    #expect(request.url == URL(string: "https://api.github.com/graphql"))
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "bearer secret-token")
  }

  @Test func sendsSearchQueriesWithLocalDate() async throws {
    let fixtureData = try fixture("github-search.json")
    let transport = StubTransport { _ in (fixtureData, 200) }
    _ = try await client(transport: transport).fetch(now: now)
    let today = localStartOfDayTimestamp(now)
    let monthAgo = localStartOfDayTimestamp(Calendar.current.date(byAdding: .day, value: -30, to: now)!)
    let summary = try variables(containing: "requestedQuery", in: transport)
    #expect(summary["requestedQuery"] as? String == "is:pr is:open review-requested:@me archived:false")
    #expect(summary["mergedQuery"] as? String == "is:pr author:@me merged:>=\(today)")
    #expect(summary["reviewedQuery"] as? String == "is:pr reviewed-by:@me -author:@me updated:>=\(today)")
    #expect(summary["recentlyMergedQuery"] as? String == "is:pr author:@me is:merged merged:>=\(monthAgo) sort:updated-desc")
    let authored = try variables(containing: "authoredQuery", in: transport)
    #expect(authored["authoredQuery"] as? String == "is:pr is:open author:@me archived:false")
  }

  @Test func authoredSearchAsksForASmallPage() async throws {
    let fixtureData = try fixture("github-search.json")
    let transport = StubTransport { _ in (fixtureData, 200) }
    _ = try await client(transport: transport).fetch(now: now)
    let authored = try variables(containing: "authoredQuery", in: transport)
    #expect(authored["pageSize"] as? Int == 20)
    #expect(authored["cursor"] == nil)
    let authoredSearch = try query(containing: "authoredQuery", in: transport)
    #expect(authoredSearch.contains("first: $pageSize, after: $cursor"))
  }

  @Test func authoredSearchFollowsTheCursorUntilTheLastPage() async throws {
    let firstBody = try authoredPage(try fixture("github-search.json"), hasNextPage: true, endCursor: "cursor-1")
    let firstPage = try #require(try JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
    let firstAuthored = try #require((firstPage["data"] as? [String: Any])?["authored"] as? [String: Any])
    var lastPageNode = try #require((firstAuthored["nodes"] as? [[String: Any]])?.first)
    lastPageNode["number"] = 3001
    lastPageNode["url"] = "https://github.com/acme/app-web/pull/3001"
    var lastPage = firstPage
    var lastData = try #require(lastPage["data"] as? [String: Any])
    lastData["authored"] = [
      "nodes": [lastPageNode], "pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
    ]
    lastPage["data"] = lastData
    let lastBody = try JSONSerialization.data(withJSONObject: lastPage)

    let transport = StubTransport { request in
      let cursor = (try variables(in: request))["cursor"] as? String
      return (cursor == "cursor-1" ? lastBody : firstBody, 200)
    }
    let snapshot = try await client(transport: transport).fetch(now: now)
    #expect(snapshot.authoredPullRequests.map(\.number) == [2184, 988, 3001])
    let authoredRequests = transport.requests.filter { request in
      ((try? variables(in: request))?["authoredQuery"] as? String) != nil
    }
    #expect(authoredRequests.count == 2)
    let secondPageBody = try #require(authoredRequests.last?.httpBody)
    let secondPageVariables = try variables(in: secondPageBody)
    #expect(secondPageVariables["cursor"] as? String == "cursor-1")
  }

  @Test func authoredSearchStopsAtThePageCap() async throws {
    let fixtureData = try fixture("github-search.json")
    // Each page points to the next one, and page 11 is the last, so a missing cap ends with 11 requests, not a loop.
    let transport = StubTransport { request in
      let cursor = (try variables(in: request))["cursor"] as? String
      let pageNumber = (cursor.flatMap { Int($0.dropFirst("cursor-".count)) } ?? 0) + 1
      return (try authoredPage(fixtureData, hasNextPage: pageNumber < 11, endCursor: "cursor-\(pageNumber)"), 200)
    }
    let snapshot = try await client(transport: transport).fetch(now: now)
    let authoredRequests = transport.requests.filter { request in
      ((try? variables(in: request))?["authoredQuery"] as? String) != nil
    }
    #expect(authoredRequests.count == 10)
    // Every page repeats the same 2 pull requests, and a repeat shows once.
    #expect(snapshot.authoredPullRequests.count == 2)
  }

  @Test func pageThatRepeatsItsCursorFails() async throws {
    let body = try authoredPage(try fixture("github-search.json"), hasNextPage: true, endCursor: "cursor-1")
    let transport = StubTransport { _ in (body, 200) }
    await #expect(throws: SourceFailure.unexpected("GitHub search page repeated its cursor")) {
      try await client(transport: transport).fetch(now: now)
    }
  }

  @Test func badGatewayOnALaterAuthoredPageIsRetriedWithTheSameCursor() async throws {
    let fixtureData = try fixture("github-search.json")
    let firstBody = try authoredPage(fixtureData, hasNextPage: true, endCursor: "cursor-1")
    let secondPageAttempts = AttemptCounter()
    let transport = StubTransport { request in
      guard (try variables(in: request))["cursor"] as? String == "cursor-1" else { return (firstBody, 200) }
      return secondPageAttempts.next() == 1 ? (Data(), 502) : (fixtureData, 200)
    }
    _ = try await client(transport: transport).fetch(now: now)
    #expect(secondPageAttempts.count == 2)
  }

  @Test func authoredPullRequestOnTwoPagesShowsOnce() async throws {
    let lastBody = try fixture("github-search.json")
    let firstBody = try authoredPage(lastBody, hasNextPage: true, endCursor: "cursor-1")

    let transport = StubTransport { request in
      let cursor = (try variables(in: request))["cursor"] as? String
      return (cursor == "cursor-1" ? lastBody : firstBody, 200)
    }
    let snapshot = try await client(transport: transport).fetch(now: now)
    #expect(snapshot.authoredPullRequests.count == 2)
    #expect(snapshot.authoredPullRequests.first?.number == 2184)
  }

  // A sequential fetch never answers its first request, so it hangs until the time limit.
  @Test(.timeLimit(.minutes(1))) func summaryRunsNextToTheAuthoredPages() async throws {
    let transport = RendezvousTransport(body: try fixture("github-search.json"))
    let client = GitHubClient(tokenProvider: StubTokenProvider(result: .success("secret-token")), transport: transport)
    let snapshot = try await client.fetch(now: now)
    #expect(snapshot.viewerLogin == "octo-me")
  }

  @Test func pageWithMoreResultsButNoCursorFails() async throws {
    let body = try authoredPage(try fixture("github-search.json"), hasNextPage: true, endCursor: nil)
    let transport = StubTransport { _ in (body, 200) }
    await #expect(throws: SourceFailure.unexpected("GitHub search page has no cursor")) {
      try await client(transport: transport).fetch(now: now)
    }
  }

  @Test func summaryAuthenticationFailureWinsOverAuthoredFailure() async {
    let transport = StubTransport { request in
      (try variables(in: request))["requestedQuery"] != nil ? (Data(), 401) : (Data(), 502)
    }
    await #expect(throws: SourceFailure.authentication) { try await client(transport: transport).fetch(now: now) }
  }

  // If the fetch waited for the authored search, the 30 s sleep would end uncancelled.
  @Test(.timeLimit(.minutes(1))) func summaryAuthenticationFailureCancelsTheAuthoredPages() async {
    let transport = CancellationRecordingTransport()
    let client = GitHubClient(tokenProvider: StubTokenProvider(result: .success("secret-token")), transport: transport)
    await #expect(throws: SourceFailure.authentication) { try await client.fetch(now: now) }
    #expect(transport.authoredRequestWasCancelled)
  }

  @Test func summaryFailureWinsWhenNeitherFailureIsAuthentication() async {
    let authoredErrorBody = Data(#"{"errors":[{"message":"authored search failed"}]}"#.utf8)
    let transport = StubTransport { request in
      (try variables(in: request))["requestedQuery"] != nil ? (Data(), 500) : (authoredErrorBody, 200)
    }
    await #expect(throws: SourceFailure.unexpected("HTTP 500")) { try await client(transport: transport).fetch(now: now) }
  }

  @Test func authoredAuthenticationFailureWinsOverSummaryFailure() async {
    let transport = StubTransport { request in
      (try variables(in: request))["requestedQuery"] != nil ? (Data(), 502) : (Data(), 401)
    }
    await #expect(throws: SourceFailure.authentication) { try await client(transport: transport).fetch(now: now) }
  }

  @Test func badGatewayIsRetriedOnce() async throws {
    let fixtureData = try fixture("github-search.json")
    let summaryAttempts = AttemptCounter()
    let transport = StubTransport { request in
      guard (try variables(in: request))["requestedQuery"] != nil else { return (fixtureData, 200) }
      return summaryAttempts.next() == 1 ? (Data(), 502) : (fixtureData, 200)
    }
    let snapshot = try await client(transport: transport).fetch(now: now)
    #expect(snapshot.viewerLogin == "octo-me")
    #expect(summaryAttempts.count == 2)
  }

  @Test func secondBadGatewayIsUnexpectedFailure() async {
    let summaryAttempts = AttemptCounter()
    let transport = StubTransport { request in
      guard (try variables(in: request))["requestedQuery"] != nil else { return (try fixture("github-search.json"), 200) }
      _ = summaryAttempts.next()
      return (Data(), 502)
    }
    await #expect(throws: SourceFailure.unexpected("HTTP 502")) { try await client(transport: transport).fetch(now: now) }
    #expect(summaryAttempts.count == 2)
  }

  @Test func decodesRecentlyMergedPullRequests() async throws {
    let fixtureData = try fixture("github-search.json")
    let snapshot = try await client(transport: StubTransport { _ in (fixtureData, 200) }).fetch(now: now)
    #expect(snapshot.recentlyMergedPullRequests == [
      MergedPullRequest(title: "Handle empty heatmap responses", headBranch: "proj-1500-heatmap")
    ])
  }

  @Test func cachedSnapshotWithoutMergedPullRequestsStillDecodes() throws {
    let oldCache = #"{"viewerLogin":"me","authoredPullRequests":[],"reviewRequests":[],"reviewsSubmittedToday":0,"mergedToday":0}"#
    let snapshot = try JSONDecoder().decode(GitHubSnapshot.self, from: Data(oldCache.utf8))
    #expect(snapshot.recentlyMergedPullRequests == nil)
  }

  @Test func cachedPullRequestWithoutBaseBranchStillDecodes() throws {
    let current = PullRequest(
      repository: "app-web", number: 1, title: "T", url: URL(string: "https://github.com/acme/app-web/pull/1")!,
      author: "me", authorIsBot: false, isDraft: false, updatedAt: now, headBranch: "two", reviewDecision: nil,
      checkState: nil, failedCheckCount: 0, additions: 0, deletions: 0, requestedReviewerLogins: [],
      requestedTeamSlugs: [], reviewCount: 0, reviewRequestedAt: nil, baseBranch: "one", isCrossRepository: false)
    let encoded = try JSONEncoder().encode(current)
    var cachedPullRequest = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    cachedPullRequest["baseBranch"] = nil
    cachedPullRequest["isCrossRepository"] = nil
    let oldCache = try JSONSerialization.data(withJSONObject: cachedPullRequest)
    let pullRequest = try JSONDecoder().decode(PullRequest.self, from: oldCache)
    #expect(pullRequest.baseBranch == nil)
    #expect(pullRequest.isCrossRepository == nil)
  }

  @Test func onlyAuthoredSearchAsksForStripFields() async throws {
    let fixtureData = try fixture("github-search.json")
    let transport = StubTransport { _ in (fixtureData, 200) }
    _ = try await client(transport: transport).fetch(now: now)
    let stripFields = ["baseRef", "latestOpinionatedReviews", "reviewThreads"]
    let authoredFields = try fieldsRequested(bySearch: "authored", in: try query(containing: "authoredQuery", in: transport))
    let requestedFields = try fieldsRequested(bySearch: "requested", in: try query(containing: "requestedQuery", in: transport))
    for field in stripFields {
      #expect(authoredFields.contains(field))
      #expect(!requestedFields.contains(field))
    }
  }

  @Test func reviewThreadsSampleTheNewestPage() async throws {
    let fixtureData = try fixture("github-search.json")
    let transport = StubTransport { _ in (fixtureData, 200) }
    _ = try await client(transport: transport).fetch(now: now)
    #expect(try query(containing: "authoredQuery", in: transport).contains("reviewThreads(last: 50)"))
  }

  @Test func requiredApprovalCountIsHighestPullRequestRule() async throws {
    let pullRequests = try await authoredStripPullRequests()
    #expect(pullRequests[0].requiredApprovalCount == 2)
    #expect(pullRequests[1].requiredApprovalCount == 1)
    #expect(pullRequests[2].requiredApprovalCount == 0)
    #expect(pullRequests[3].requiredApprovalCount == 1)
  }

  @Test func approvalCountCountsOnlyApprovedReviewsWithoutCap() async throws {
    let pullRequests = try await authoredStripPullRequests()
    #expect(pullRequests[0].approvalCount == 3)
    #expect(pullRequests[1].approvalCount == 0)
    #expect(pullRequests[2].approvalCount == 1)
  }

  @Test func unresolvedThreadCountComesFromFetchedThreads() async throws {
    let pullRequests = try await authoredStripPullRequests()
    #expect(pullRequests[0].unresolvedThreadCount == 2)
    #expect(pullRequests[0].hasMoreThreadsThanFetched == false)
    #expect(pullRequests[1].unresolvedThreadCount == 0)
    #expect(pullRequests[2].unresolvedThreadCount == 0)
  }

  @Test func threadTotalOverFiftySetsOverflow() async throws {
    let pullRequests = try await authoredStripPullRequests()
    #expect(pullRequests[3].unresolvedThreadCount == 2)
    #expect(pullRequests[3].hasMoreThreadsThanFetched == true)
  }

  @Test func reviewRequestsGetNeutralStripDefaults() async throws {
    let fixtureData = try fixture("github-search.json")
    let snapshot = try await client(transport: StubTransport { _ in (fixtureData, 200) }).fetch(now: now)
    let reviewRequest = snapshot.reviewRequests[0]
    #expect(reviewRequest.unresolvedThreadCount == 0)
    #expect(reviewRequest.hasMoreThreadsThanFetched == false)
    #expect(reviewRequest.approvalCount == 0)
    #expect(reviewRequest.requiredApprovalCount == 1)
  }

  @Test func hangingGhIsUnexpectedFailureNotSignIn() async throws {
    let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("tower-slow-gh-\(UUID().uuidString)")
    try "#!/bin/sh\nsleep 5\n".write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    let provider = GhCLITokenProvider(candidatePaths: [scriptURL.path], timeout: .milliseconds(200))
    await #expect(throws: SourceFailure.unexpected("gh timed out")) { try await provider.token() }
  }

  @Test func unauthorizedResponseIsAuthenticationFailure() async {
    let transport = StubTransport { _ in (Data(), 401) }
    await #expect(throws: SourceFailure.authentication) { try await client(transport: transport).fetch(now: now) }
  }

  @Test func offlineIsNetworkFailure() async {
    let transport = StubTransport { _ in throw URLError(.notConnectedToInternet) }
    await #expect(throws: SourceFailure.network) { try await client(transport: transport).fetch(now: now) }
  }

  @Test func graphQLErrorsAreUnexpectedFailure() async {
    let body = Data(#"{"errors":[{"message":"Field 'x' doesn't exist"}]}"#.utf8)
    let transport = StubTransport { _ in (body, 200) }
    await #expect(throws: SourceFailure.unexpected("Field 'x' doesn't exist")) {
      try await client(transport: transport).fetch(now: now)
    }
  }

  @Test func graphQLErrorsWithDataKeepTheSnapshot() async throws {
    var response = try #require(try JSONSerialization.jsonObject(with: fixture("github-search.json")) as? [String: Any])
    response["errors"] = [["message": "Resource protected by organization SAML enforcement"]]
    let body = try JSONSerialization.data(withJSONObject: response)
    let snapshot = try await client(transport: StubTransport { _ in (body, 200) }).fetch(now: now)
    #expect(snapshot.viewerLogin == "octo-me")
    #expect(snapshot.authoredPullRequests.count == 2)
  }

  // Puts the given reviewers and request events on the first review request of the fixture.
  private func firstReviewRequest(
    reviewers: [[String: String]], requestEvents: [(createdAt: String, reviewer: [String: String])],
    leadingNullEvent: Bool = false
  ) async throws -> PullRequest? {
    var response = try #require(try JSONSerialization.jsonObject(with: fixture("github-search.json")) as? [String: Any])
    var data = try #require(response["data"] as? [String: Any])
    var requested = try #require(data["requested"] as? [String: Any])
    var nodes = try #require(requested["nodes"] as? [[String: Any]])
    nodes[0]["reviewRequests"] = ["nodes": reviewers.map { ["requestedReviewer": $0] }]
    let eventNodes: [Any] = requestEvents.map { ["createdAt": $0.createdAt, "requestedReviewer": $0.reviewer] }
    nodes[0]["timelineItems"] = ["nodes": (leadingNullEvent ? [NSNull()] : []) + eventNodes]
    requested["nodes"] = nodes
    data["requested"] = requested
    response["data"] = data
    let body = try JSONSerialization.data(withJSONObject: response)
    return try await client(transport: StubTransport { _ in (body, 200) }).fetch(now: now).reviewRequests.first
  }

  @Test func viewerRequestTimeIgnoresALaterRequestToSomeoneElse() async throws {
    let pullRequest = try await firstReviewRequest(
      reviewers: [["login": "octo-me"], ["login": "someone-else"]],
      requestEvents: [("2027-01-14T09:00:00Z", ["login": "octo-me"]), ("2027-01-14T11:00:00Z", ["login": "someone-else"])])
    #expect(pullRequest?.viewerReviewRequestedAt == isoDate("2027-01-14T09:00:00Z"))
    #expect(pullRequest?.reviewRequestedAt == isoDate("2027-01-14T11:00:00Z"))
  }

  @Test func nullRequestEventIsSkipped() async throws {
    let pullRequest = try await firstReviewRequest(
      reviewers: [["login": "octo-me"]], requestEvents: [("2027-01-14T09:00:00Z", ["login": "octo-me"])],
      leadingNullEvent: true)
    #expect(pullRequest?.viewerReviewRequestedAt == isoDate("2027-01-14T09:00:00Z"))
  }

  @Test func directRequestIgnoresALaterRequestToATeam() async throws {
    let pullRequest = try await firstReviewRequest(
      reviewers: [["login": "octo-me"], ["slug": "design"]],
      requestEvents: [("2027-01-14T09:00:00Z", ["login": "octo-me"]), ("2027-01-14T11:00:00Z", ["slug": "design"])])
    #expect(pullRequest?.viewerReviewRequestedAt == isoDate("2027-01-14T09:00:00Z"))
  }

  @Test func teamOnlyRequestUsesTheNewestRequestedTeam() async throws {
    let pullRequest = try await firstReviewRequest(
      reviewers: [["slug": "web"]],
      requestEvents: [("2027-01-14T09:00:00Z", ["slug": "web"]), ("2027-01-14T11:00:00Z", ["login": "someone-else"])])
    #expect(pullRequest?.viewerReviewRequestedAt == isoDate("2027-01-14T09:00:00Z"))
  }

  @Test func nullSearchNodeWithErrorsKeepsTheOtherPullRequests() async throws {
    var response = try #require(try JSONSerialization.jsonObject(with: fixture("github-search.json")) as? [String: Any])
    var data = try #require(response["data"] as? [String: Any])
    var authored = try #require(data["authored"] as? [String: Any])
    var nodes = try #require(authored["nodes"] as? [Any])
    nodes.insert(NSNull(), at: 0)
    authored["nodes"] = nodes
    data["authored"] = authored
    response["data"] = data
    response["errors"] = [["message": "Resource protected by organization SAML enforcement", "path": ["authored", "nodes", 0]]]
    let body = try JSONSerialization.data(withJSONObject: response)
    let snapshot = try await client(transport: StubTransport { _ in (body, 200) }).fetch(now: now)
    #expect(snapshot.authoredPullRequests.count == 2)
  }

  @Test func tokenFailurePassesThroughWithoutRequest() async {
    let transport = StubTransport { _ in (Data(), 200) }
    await #expect(throws: SourceFailure.authentication) {
      try await client(token: .failure(.authentication), transport: transport).fetch(now: now)
    }
    #expect(transport.requests.isEmpty)
  }

  @Test func ghThatExitsNonZeroIsAuthenticationFailure() async {
    let provider = GhCLITokenProvider(candidatePaths: ["/usr/bin/false"])
    await #expect(throws: SourceFailure.authentication) { try await provider.token() }
  }

  @Test func missingGhIsAuthenticationFailure() async {
    let provider = GhCLITokenProvider(candidatePaths: ["/nonexistent/gh"])
    await #expect(throws: SourceFailure.authentication) { try await provider.token() }
  }
}

// The search line plus the text of every fragment it spreads, followed through nested spreads.
private func fieldsRequested(bySearch alias: String, in query: String) throws -> String {
  let searchLine = try #require(query.split(separator: "\n").first { $0.contains("\(alias): search(") })
  var text = String(searchLine)
  var pendingFragments = fragmentNames(spreadIn: text)
  var visitedFragments: Set<String> = []
  while let fragmentName = pendingFragments.popLast() {
    guard visitedFragments.insert(fragmentName).inserted else { continue }
    let fragmentStart = try #require(query.range(of: "fragment \(fragmentName) on"))
    let rest = query[fragmentStart.upperBound...]
    let fragmentBody = rest.range(of: "fragment ").map { rest[..<$0.lowerBound] } ?? rest
    text += fragmentBody
    pendingFragments += fragmentNames(spreadIn: String(fragmentBody))
  }
  return text
}

private func fragmentNames(spreadIn text: String) -> [String] {
  text.matches(of: /\.\.\.([A-Za-z]+)/).map { String($0.output.1) }
}

private func variables(in request: URLRequest) throws -> [String: Any] {
  let body = try #require(request.httpBody)
  return try variables(in: body)
}

private func variables(in body: Data) throws -> [String: Any] {
  let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
  return try #require(payload["variables"] as? [String: Any])
}

private func variables(containing variable: String, in transport: StubTransport) throws -> [String: Any] {
  let payload = try #require(try transport.requests.map { try variables(in: $0) }.first { $0[variable] != nil })
  return payload
}

private func query(containing variable: String, in transport: StubTransport) throws -> String {
  let request = try #require(transport.requests.first { (try? variables(in: $0)[variable]) != nil })
  let body = try #require(request.httpBody)
  let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
  return try #require(payload["query"] as? String)
}
