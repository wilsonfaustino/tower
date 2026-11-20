import Foundation

public protocol GitHubTokenProvider: Sendable {
  func token() async throws(SourceFailure) -> String
}

public struct GhCLITokenProvider: GitHubTokenProvider {
  // A GUI app does not get the shell PATH, so look where Homebrew installs gh.
  public static let defaultCandidatePaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

  public let candidatePaths: [String]
  private let timeout: Duration

  public init(candidatePaths: [String] = defaultCandidatePaths, timeout: Duration = GhRunner.defaultTimeout) {
    self.candidatePaths = candidatePaths
    self.timeout = timeout
  }

  public var ghPath: String? {
    candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  public func token() async throws(SourceFailure) -> String {
    guard let ghPath else { throw .authentication }
    let output: GhRunner.Output
    do {
      output = try await GhRunner.run(path: ghPath, arguments: ["auth", "token"], readsStandardError: false, timeout: timeout)
    } catch .timedOut {
      // A hung gh (an unanswered keychain prompt) says nothing about the sign-in.
      throw .unexpected("gh timed out")
    } catch {
      throw .unexpected("gh could not start")
    }
    let token = String(decoding: output.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard output.exitStatus == 0, !token.isEmpty else { throw .authentication }
    return token
  }
}

public struct GitHubSnapshot: Codable, Sendable, Equatable {
  public var viewerLogin: String
  public var authoredPullRequests: [PullRequest]
  public var reviewRequests: [PullRequest]
  public var reviewsSubmittedToday: Int
  public var mergedToday: Int
  // Optional so a snapshot cached before this field existed still decodes.
  public var recentlyMergedPullRequests: [MergedPullRequest]?

  public init(
    viewerLogin: String, authoredPullRequests: [PullRequest], reviewRequests: [PullRequest], reviewsSubmittedToday: Int,
    mergedToday: Int, recentlyMergedPullRequests: [MergedPullRequest]? = []
  ) {
    self.viewerLogin = viewerLogin
    self.authoredPullRequests = authoredPullRequests
    self.reviewRequests = reviewRequests
    self.reviewsSubmittedToday = reviewsSubmittedToday
    self.mergedToday = mergedToday
    self.recentlyMergedPullRequests = recentlyMergedPullRequests
  }
}

public struct GitHubClient: Sendable {
  private static let endpoint = URL(string: "https://api.github.com/graphql")!
  private static let failedCheckRunStates: Set<String> = ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE"]
  private static let failedStatusContextStates: Set<String> = ["FAILURE", "ERROR"]
  // A search page this small keeps every request below the GitHub edge timeout, which answers a heavier one with a 502.
  private static let authoredPageSize = 20
  // Caps the authored search at 200 pull requests, so a response that always sends a cursor cannot loop.
  private static let maxAuthoredPages = 10

  private let tokenProvider: GitHubTokenProvider
  private let transport: HTTPTransport
  private let ownerQualifiers: String

  public init(tokenProvider: GitHubTokenProvider, transport: HTTPTransport, owners: [String] = []) {
    self.tokenProvider = tokenProvider
    self.transport = transport
    ownerQualifiers = owners
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }
      .map { " org:\($0)" }
      .joined()
  }

  public func fetch(now: Date) async throws(SourceFailure) -> GitHubSnapshot {
    let token = try await tokenProvider.token()
    // GitHub reads a bare date as UTC, so send the local start of day with its offset.
    let today = Self.timestampFormatter.string(from: Calendar.current.startOfDay(for: now))
    let recentlyMergedStart = Calendar.current.date(byAdding: .day, value: -recentlyMergedDays, to: now) ?? now
    let recentlyMergedSince = Self.timestampFormatter.string(from: Calendar.current.startOfDay(for: recentlyMergedStart))
    let summaryVariables = [
      "requestedQuery": "is:pr is:open review-requested:@me archived:false\(ownerQualifiers)",
      "reviewedQuery": "is:pr reviewed-by:@me -author:@me updated:>=\(today)\(ownerQualifiers)",
      "mergedQuery": "is:pr author:@me merged:>=\(today)\(ownerQualifiers)",
      "recentlyMergedQuery": "is:pr author:@me is:merged merged:>=\(recentlyMergedSince) sort:updated-desc\(ownerQualifiers)",
    ]
    let authoredSearchText = "is:pr is:open author:@me archived:false\(ownerQualifiers)"
    // async let erases the typed error, so both requests come back as a Result.
    async let summaryResult: Result<SummaryResponse.Payload, SourceFailure> = {
      do throws(SourceFailure) {
        return .success(try await fetchSummary(token: token, variables: summaryVariables))
      } catch {
        return .failure(error)
      }
    }()
    async let authoredResult: Result<[PullRequestNode?], SourceFailure> = {
      do throws(SourceFailure) {
        return .success(try await fetchAuthoredPullRequests(token: token, query: authoredSearchText))
      } catch {
        return .failure(error)
      }
    }()
    // An authentication failure from either request wins, so the reconnect prompt shows.
    // Throwing before the authored result is read cancels the pages that are still running.
    let summary: SummaryResponse.Payload
    switch await summaryResult {
    case .success(let payload):
      summary = payload
    case .failure(.authentication):
      throw .authentication
    case .failure(let summaryFailure):
      if case .failure(.authentication) = await authoredResult { throw .authentication }
      throw summaryFailure
    }
    let authored = try await authoredResult.get()
    // A search cursor does not lock the result set, so a PR can show on two pages.
    var seenURLs: Set<URL> = []
    return GitHubSnapshot(
      viewerLogin: summary.viewer.login,
      authoredPullRequests: authored.compactMap { $0?.pullRequest(viewerLogin: summary.viewer.login) }
        .filter { seenURLs.insert($0.url).inserted },
      reviewRequests: summary.requested.nodes.compactMap { $0?.pullRequest(viewerLogin: summary.viewer.login) },
      reviewsSubmittedToday: summary.reviewed.issueCount,
      mergedToday: summary.merged.issueCount,
      recentlyMergedPullRequests: (summary.recentlyMerged?.nodes ?? []).compactMap { $0?.mergedPullRequest })
  }

  private func fetchSummary(token: String, variables: [String: String]) async throws(SourceFailure) -> SummaryResponse.Payload {
    let response: SummaryResponse = try await sendGraphQL(token: token, query: summaryQuery, variables: variables)
    guard let payload = response.data else {
      throw .unexpected(response.errors?.first?.message ?? "GitHub response has no data")
    }
    return payload
  }

  private func fetchAuthoredPullRequests(token: String, query: String) async throws(SourceFailure) -> [PullRequestNode?] {
    var nodes: [PullRequestNode?] = []
    var cursor: String?
    var usedCursors: Set<String> = []
    for _ in 0..<Self.maxAuthoredPages {
      var variables: [String: Any] = ["authoredQuery": query, "pageSize": Self.authoredPageSize]
      if let cursor { variables["cursor"] = cursor }
      let response: AuthoredResponse = try await sendGraphQL(token: token, query: authoredQuery, variables: variables)
      // GraphQL can return data and errors together; one failed field should not hide the PRs that did load.
      guard let page = response.data?.authored else {
        throw .unexpected(response.errors?.first?.message ?? "GitHub response has no data")
      }
      nodes += page.nodes
      guard page.pageInfo.hasNextPage else { break }
      // Stopping here, or reading the same page again, would save a short list as if it were complete.
      guard let endCursor = page.pageInfo.endCursor else {
        throw .unexpected("GitHub search page has no cursor")
      }
      guard usedCursors.insert(endCursor).inserted else {
        throw .unexpected("GitHub search page repeated its cursor")
      }
      cursor = endCursor
    }
    return nodes
  }

  private func sendGraphQL<Response: Decodable>(
    token: String, query: String, variables: [String: Any]
  ) async throws(SourceFailure) -> Response {
    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
    let data: Data
    do {
      data = try await sendMapped(request, transport: transport)
    } catch .unexpected("HTTP 502") {
      // The GitHub edge answers 502 now and then even to a light request, and a second try usually gets through.
      data = try await sendMapped(request, transport: transport)
    }
    do {
      return try Self.decoder.decode(Response.self, from: data)
    } catch {
      throw .unexpected("GitHub response did not decode")
    }
  }

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
    return formatter
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

// MARK: - GraphQL wire format

// The strip counts unresolved threads on the newest page only and does not page further.
private let reviewThreadPageSize = 50

// How far back a merged PR still counts as a ticket's PR. A ticket usually waits days, not months, for a deploy.
// The search reads one page of 100, newest first, so a busy month drops only the oldest merges.
private let recentlyMergedDays = 30

private let summaryQuery = """
  query($requestedQuery: String!, $reviewedQuery: String!, $mergedQuery: String!, $recentlyMergedQuery: String!) {
    viewer { login }
    requested: search(type: ISSUE, query: $requestedQuery, first: 50) { nodes { ...PullRequestFields } }
    reviewed: search(type: ISSUE, query: $reviewedQuery, first: 1) { issueCount }
    merged: search(type: ISSUE, query: $mergedQuery, first: 1) { issueCount }
    recentlyMerged: search(type: ISSUE, query: $recentlyMergedQuery, first: 100) {
      nodes { ... on PullRequest { title headRefName } }
    }
  }
  \(pullRequestFieldsFragment)
  """

private let authoredQuery = """
  query($authoredQuery: String!, $pageSize: Int!, $cursor: String) {
    authored: search(type: ISSUE, query: $authoredQuery, first: $pageSize, after: $cursor) { pageInfo { hasNextPage endCursor } nodes { ...AuthoredPullRequestFields } }
  }
  \(pullRequestFieldsFragment)
  \(authoredPullRequestFieldsFragment)
  """

private let pullRequestFieldsFragment = """
  fragment PullRequestFields on PullRequest {
    number title url isDraft updatedAt headRefName headRefOid additions deletions reviewDecision
    repository { name }
    author { __typename login }
    commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 1) {
      checkRunCountsByState { state count } statusContextCountsByState { state count } } } } } }
    reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { slug } } } }
    reviews(first: 1) { totalCount }
    viewerLatestReview { state }
    timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 25) { nodes { ... on ReviewRequestedEvent {
      createdAt requestedReviewer { ... on User { login } ... on Team { slug } } } } }
  }
  """

private let authoredPullRequestFieldsFragment = """
  fragment AuthoredPullRequestFields on PullRequest {
    ...PullRequestFields
    baseRef { rules(first: 10) { nodes { parameters { ... on PullRequestParameters { requiredApprovingReviewCount } } } } }
    latestOpinionatedReviews(first: 20, writersOnly: true) { nodes { state } }
    reviewThreads(last: \(reviewThreadPageSize)) { totalCount nodes { isResolved } }
  }
  """

private struct SummaryResponse: Decodable {
  struct Payload: Decodable {
    var viewer: Viewer
    var requested: Search
    var reviewed: Count
    var merged: Count
    // Optional so a response without this search, like the test fixtures for other fields, still decodes.
    var recentlyMerged: MergedSearch?
  }

  var data: Payload?
  var errors: [ErrorMessage]?
}

private struct AuthoredResponse: Decodable {
  struct Payload: Decodable { var authored: AuthoredSearch }

  var data: Payload?
  var errors: [ErrorMessage]?
}

private struct ErrorMessage: Decodable { var message: String }
private struct Viewer: Decodable { var login: String }
// A node GitHub cannot return (for example a PR behind SAML) comes back as null next to an errors entry.
private struct Search: Decodable { var nodes: [PullRequestNode?] }
private struct Count: Decodable { var issueCount: Int }
private struct MergedSearch: Decodable { var nodes: [MergedNode?] }
private struct AuthoredSearch: Decodable {
  var nodes: [PullRequestNode?]
  var pageInfo: PageInfo
}
private struct PageInfo: Decodable {
  var hasNextPage: Bool
  var endCursor: String?
}

// Search can return non-PR nodes as empty objects, so both fields are optional.
private struct MergedNode: Decodable {
  var title: String?
  var headRefName: String?

  var mergedPullRequest: MergedPullRequest? {
    guard let title else { return nil }
    return MergedPullRequest(title: title, headBranch: headRefName ?? "")
  }
}

private struct StateCount: Decodable {
  var state: String
  var count: Int
}

private struct PullRequestNode: Decodable {
  struct Name: Decodable { var name: String }
  struct Author: Decodable {
    var typename: String?
    var login: String

    enum CodingKeys: String, CodingKey {
      case typename = "__typename"
      case login
    }
  }
  struct Commits: Decodable { var nodes: [CommitNode] }
  struct CommitNode: Decodable { var commit: Commit }
  struct Commit: Decodable { var statusCheckRollup: Rollup? }
  struct Rollup: Decodable {
    var state: String
    var contexts: Contexts
  }
  struct Contexts: Decodable {
    var checkRunCountsByState: [StateCount]?
    var statusContextCountsByState: [StateCount]?
  }
  struct ReviewRequests: Decodable { var nodes: [ReviewRequest] }
  struct ReviewRequest: Decodable { var requestedReviewer: Reviewer? }
  struct Reviewer: Decodable {
    var login: String?
    var slug: String?
  }
  struct TotalCount: Decodable { var totalCount: Int }
  // GitHub can return a null event, for example one the token cannot read.
  struct Timeline: Decodable { var nodes: [TimelineEvent?] }
  struct TimelineEvent: Decodable {
    var createdAt: Date?
    var requestedReviewer: Reviewer?
  }
  struct BaseRef: Decodable { var rules: Rules? }
  struct Rules: Decodable { var nodes: [Rule] }
  struct Rule: Decodable { var parameters: RuleParameters? }
  // Rules that are not pull request rules come back with empty parameters.
  struct RuleParameters: Decodable { var requiredApprovingReviewCount: Int? }
  struct Reviews: Decodable { var nodes: [Review] }
  struct Review: Decodable { var state: String }
  struct Threads: Decodable {
    var totalCount: Int
    var nodes: [Thread]
  }
  struct Thread: Decodable { var isResolved: Bool }

  // Search can return non-PR nodes as empty objects, so every field is optional.
  var number: Int?
  var title: String?
  var url: URL?
  var isDraft: Bool?
  var updatedAt: Date?
  var headRefName: String?
  var headRefOid: String?
  var additions: Int?
  var deletions: Int?
  var reviewDecision: ReviewDecision?
  var repository: Name?
  var author: Author?
  var commits: Commits?
  var reviewRequests: ReviewRequests?
  var reviews: TotalCount?
  var viewerLatestReview: Review?
  var timelineItems: Timeline?
  var baseRef: BaseRef?
  var latestOpinionatedReviews: Reviews?
  var reviewThreads: Threads?

  func pullRequest(viewerLogin: String) -> PullRequest? {
    guard let number, let title, let url, let updatedAt, let repository else { return nil }
    let rollup = commits?.nodes.last?.commit.statusCheckRollup
    let failedCheckRuns = (rollup?.contexts.checkRunCountsByState ?? [])
      .filter { GitHubClient.isFailedCheckRunState($0.state) }.reduce(0) { $0 + $1.count }
    let failedStatusContexts = (rollup?.contexts.statusContextCountsByState ?? [])
      .filter { GitHubClient.isFailedStatusContextState($0.state) }.reduce(0) { $0 + $1.count }
    let reviewers = reviewRequests?.nodes.compactMap(\.requestedReviewer) ?? []
    let requestEvents = (timelineItems?.nodes ?? []).compactMap(\.self)
    // Tower does not know the viewer's teams, so a team-only request matches any requested team.
    let isDirectRequest = reviewers.contains { $0.login == viewerLogin }
    let viewerRequestEvent = requestEvents.last { event in
      isDirectRequest
        ? event.requestedReviewer?.login == viewerLogin
        : event.requestedReviewer?.slug.map { reviewers.compactMap(\.slug).contains($0) } == true
    }
    let requiredApprovalCounts = baseRef?.rules?.nodes.compactMap { $0.parameters?.requiredApprovingReviewCount } ?? []
    return PullRequest(
      repository: repository.name, number: number, title: title, url: url,
      author: author?.login ?? "ghost", authorIsBot: author?.typename == "Bot", isDraft: isDraft ?? false, updatedAt: updatedAt,
      headBranch: headRefName ?? "", reviewDecision: reviewDecision,
      checkState: rollup.flatMap { CheckState(rawValue: $0.state) },
      failedCheckCount: failedCheckRuns + failedStatusContexts,
      additions: additions ?? 0, deletions: deletions ?? 0,
      requestedReviewerLogins: reviewers.compactMap(\.login), requestedTeamSlugs: reviewers.compactMap(\.slug),
      reviewCount: reviews?.totalCount ?? 0, reviewRequestedAt: requestEvents.last?.createdAt,
      unresolvedThreadCount: reviewThreads?.nodes.filter { !$0.isResolved }.count ?? 0,
      hasMoreThreadsThanFetched: (reviewThreads?.totalCount ?? 0) > reviewThreadPageSize,
      approvalCount: latestOpinionatedReviews?.nodes.filter { $0.state == "APPROVED" }.count ?? 0,
      requiredApprovalCount: requiredApprovalCounts.max() ?? 1,
      viewerLatestReviewState: viewerLatestReview.flatMap { ReviewState(rawValue: $0.state) }, headCommitId: headRefOid,
      viewerReviewRequestedAt: viewerRequestEvent?.createdAt)
  }
}

extension GitHubClient {
  fileprivate static func isFailedCheckRunState(_ state: String) -> Bool { failedCheckRunStates.contains(state) }
  fileprivate static func isFailedStatusContextState(_ state: String) -> Bool { failedStatusContextStates.contains(state) }
}
