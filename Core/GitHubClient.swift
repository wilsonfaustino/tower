import Foundation

public protocol GitHubTokenProvider: Sendable {
  func token() async throws(SourceFailure) -> String
}

public struct GhCLITokenProvider: GitHubTokenProvider {
  // A GUI app does not get the shell PATH, so look where Homebrew installs gh.
  public static let defaultCandidatePaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

  public let candidatePaths: [String]

  public init(candidatePaths: [String] = defaultCandidatePaths) {
    self.candidatePaths = candidatePaths
  }

  public var ghPath: String? {
    candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  public func token() async throws(SourceFailure) -> String {
    guard let ghPath else { throw .authentication }
    let output: GhRunner.Output
    do {
      output = try await GhRunner.run(path: ghPath, arguments: ["auth", "token"], readsStandardError: false)
    } catch {
      throw .authentication
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

  public init(viewerLogin: String, authoredPullRequests: [PullRequest], reviewRequests: [PullRequest], reviewsSubmittedToday: Int, mergedToday: Int) {
    self.viewerLogin = viewerLogin
    self.authoredPullRequests = authoredPullRequests
    self.reviewRequests = reviewRequests
    self.reviewsSubmittedToday = reviewsSubmittedToday
    self.mergedToday = mergedToday
  }
}

public struct GitHubClient: Sendable {
  private static let endpoint = URL(string: "https://api.github.com/graphql")!
  private static let failedCheckRunStates: Set<String> = ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE"]
  private static let failedStatusContextStates: Set<String> = ["FAILURE", "ERROR"]

  private let tokenProvider: GitHubTokenProvider
  private let transport: HTTPTransport

  public init(tokenProvider: GitHubTokenProvider, transport: HTTPTransport) {
    self.tokenProvider = tokenProvider
    self.transport = transport
  }

  public func fetch(now: Date) async throws(SourceFailure) -> GitHubSnapshot {
    let token = try await tokenProvider.token()
    let todayParts = Calendar.current.dateComponents([.year, .month, .day], from: now)
    let today = String(format: "%04d-%02d-%02d", todayParts.year ?? 0, todayParts.month ?? 0, todayParts.day ?? 0)
    let variables = [
      "authoredQuery": "is:pr is:open author:@me archived:false",
      "requestedQuery": "is:pr is:open review-requested:@me archived:false",
      "reviewedQuery": "is:pr reviewed-by:@me -author:@me updated:>=\(today)",
      "mergedQuery": "is:pr author:@me merged:>=\(today)",
    ]
    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": searchQuery, "variables": variables])

    let data = try await sendMapped(request, transport: transport)
    let response: GraphQLResponse
    do {
      response = try Self.decoder.decode(GraphQLResponse.self, from: data)
    } catch {
      throw .unexpected("GitHub response did not decode")
    }
    if let message = response.errors?.first?.message { throw .unexpected(message) }
    guard let payload = response.data else { throw .unexpected("GitHub response has no data") }
    return GitHubSnapshot(
      viewerLogin: payload.viewer.login,
      authoredPullRequests: payload.authored.nodes.compactMap { $0.pullRequest },
      reviewRequests: payload.requested.nodes.compactMap { $0.pullRequest },
      reviewsSubmittedToday: payload.reviewed.issueCount,
      mergedToday: payload.merged.issueCount)
  }

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

// MARK: - GraphQL wire format

private let searchQuery = """
  query($authoredQuery: String!, $requestedQuery: String!, $reviewedQuery: String!, $mergedQuery: String!) {
    viewer { login }
    authored: search(type: ISSUE, query: $authoredQuery, first: 50) { nodes { ...PullRequestFields } }
    requested: search(type: ISSUE, query: $requestedQuery, first: 50) { nodes { ...PullRequestFields } }
    reviewed: search(type: ISSUE, query: $reviewedQuery, first: 1) { issueCount }
    merged: search(type: ISSUE, query: $mergedQuery, first: 1) { issueCount }
  }
  fragment PullRequestFields on PullRequest {
    number title url isDraft updatedAt headRefName additions deletions reviewDecision
    repository { name }
    author { __typename login }
    commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 1) {
      checkRunCountsByState { state count } statusContextCountsByState { state count } } } } } }
    reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { slug } } } }
    reviews(first: 1) { totalCount }
    timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 1) { nodes { ... on ReviewRequestedEvent { createdAt } } }
  }
  """

private struct GraphQLResponse: Decodable {
  struct ErrorMessage: Decodable { var message: String }
  struct Payload: Decodable {
    var viewer: Viewer
    var authored: Search
    var requested: Search
    var reviewed: Count
    var merged: Count
  }
  struct Viewer: Decodable { var login: String }
  struct Search: Decodable { var nodes: [PullRequestNode] }
  struct Count: Decodable { var issueCount: Int }

  var data: Payload?
  var errors: [ErrorMessage]?
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
  struct Timeline: Decodable { var nodes: [TimelineEvent] }
  struct TimelineEvent: Decodable { var createdAt: Date? }

  // Search can return non-PR nodes as empty objects, so every field is optional.
  var number: Int?
  var title: String?
  var url: URL?
  var isDraft: Bool?
  var updatedAt: Date?
  var headRefName: String?
  var additions: Int?
  var deletions: Int?
  var reviewDecision: ReviewDecision?
  var repository: Name?
  var author: Author?
  var commits: Commits?
  var reviewRequests: ReviewRequests?
  var reviews: TotalCount?
  var timelineItems: Timeline?

  var pullRequest: PullRequest? {
    guard let number, let title, let url, let updatedAt, let repository else { return nil }
    let rollup = commits?.nodes.last?.commit.statusCheckRollup
    let failedCheckRuns = (rollup?.contexts.checkRunCountsByState ?? [])
      .filter { GitHubClient.isFailedCheckRunState($0.state) }.reduce(0) { $0 + $1.count }
    let failedStatusContexts = (rollup?.contexts.statusContextCountsByState ?? [])
      .filter { GitHubClient.isFailedStatusContextState($0.state) }.reduce(0) { $0 + $1.count }
    let reviewers = reviewRequests?.nodes.compactMap(\.requestedReviewer) ?? []
    return PullRequest(
      repository: repository.name, number: number, title: title, url: url,
      author: author?.login ?? "ghost", authorIsBot: author?.typename == "Bot", isDraft: isDraft ?? false, updatedAt: updatedAt,
      headBranch: headRefName ?? "", reviewDecision: reviewDecision,
      checkState: rollup.flatMap { CheckState(rawValue: $0.state) },
      failedCheckCount: failedCheckRuns + failedStatusContexts,
      additions: additions ?? 0, deletions: deletions ?? 0,
      requestedReviewerLogins: reviewers.compactMap(\.login), requestedTeamSlugs: reviewers.compactMap(\.slug),
      reviewCount: reviews?.totalCount ?? 0, reviewRequestedAt: timelineItems?.nodes.last?.createdAt)
  }
}

extension GitHubClient {
  fileprivate static func isFailedCheckRunState(_ state: String) -> Bool { failedCheckRunStates.contains(state) }
  fileprivate static func isFailedStatusContextState(_ state: String) -> Bool { failedStatusContextStates.contains(state) }
}
