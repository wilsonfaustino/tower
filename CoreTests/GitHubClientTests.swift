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

struct GitHubClientTests {
  @Test func decodesFixtureIntoSnapshot() async throws {
    let fixtureData = try fixture("github-search.json")
    let snapshot = try await client(transport: StubTransport { _ in (fixtureData, 200) }).fetch(now: now)
    #expect(snapshot.viewerLogin == "octo-me")
    #expect(snapshot.authoredPullRequests.count == 2)
    #expect(snapshot.reviewRequests.count == 2)
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
    let todayParts = Calendar.current.dateComponents([.year, .month, .day], from: now)
    let today = String(format: "%04d-%02d-%02d", todayParts.year!, todayParts.month!, todayParts.day!)
    #expect(variables["authoredQuery"] == "is:pr is:open author:@me archived:false")
    #expect(variables["requestedQuery"] == "is:pr is:open review-requested:@me archived:false")
    #expect(variables["mergedQuery"] == "is:pr author:@me merged:>=\(today)")
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
