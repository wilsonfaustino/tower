import Core
import Foundation
import Testing

private struct StubTokenProvider: GitHubTokenProvider {
  var result: Result<String, SourceFailure>
  func token() async throws(SourceFailure) -> String { try result.get() }
}

private let now = isoDate("2027-01-15T12:00:00Z")

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
    #expect(snapshot.reviewRequests[1].checkState == nil)
    #expect(snapshot.reviewRequests[1].requestedReviewerLogins == ["octo-me"])
    #expect(snapshot.authoredPullRequests[1].reviewRequestedAt == nil)
    #expect(failing.authorIsBot == false)
    #expect(snapshot.reviewRequests[2].author == "dependabot")
    #expect(snapshot.reviewRequests[2].authorIsBot == true)
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
    let body = try #require(transport.requests.first?.httpBody)
    let variables = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["variables"] as? [String: String])
    let today = localStartOfDayTimestamp(now)
    #expect(variables["authoredQuery"] == "is:pr is:open author:@me archived:false")
    #expect(variables["requestedQuery"] == "is:pr is:open review-requested:@me archived:false")
    #expect(variables["mergedQuery"] == "is:pr author:@me merged:>=\(today)")
    #expect(variables["reviewedQuery"] == "is:pr reviewed-by:@me -author:@me updated:>=\(today)")
  }

  @Test func onlyAuthoredSearchAsksForStripFields() async throws {
    let fixtureData = try fixture("github-search.json")
    let transport = StubTransport { _ in (fixtureData, 200) }
    _ = try await client(transport: transport).fetch(now: now)
    let body = try #require(transport.requests.first?.httpBody)
    let query = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["query"] as? String)
    let stripFields = ["baseRef", "latestOpinionatedReviews", "reviewThreads"]
    let authoredFields = try fieldsRequested(bySearch: "authored", in: query)
    let requestedFields = try fieldsRequested(bySearch: "requested", in: query)
    for field in stripFields {
      #expect(authoredFields.contains(field))
      #expect(!requestedFields.contains(field))
    }
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
