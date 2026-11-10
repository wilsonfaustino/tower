import Foundation

public struct QueueInput: Sendable {
  public var viewerLogin: String
  public var authoredPullRequests: [PullRequest]
  public var reviewRequests: [PullRequest]
  public var jiraTickets: [JiraTicket]
  public var pipelines: [Pipeline]

  public init(
    viewerLogin: String, authoredPullRequests: [PullRequest], reviewRequests: [PullRequest], jiraTickets: [JiraTicket],
    pipelines: [Pipeline]
  ) {
    self.viewerLogin = viewerLogin
    self.authoredPullRequests = authoredPullRequests
    self.reviewRequests = reviewRequests
    self.jiraTickets = jiraTickets
    self.pipelines = pipelines
  }
}

// A review request older than this turns urgent.
private let urgentReviewAge: TimeInterval = 24 * 3600

public func buildQueue(_ input: QueueInput, now: Date) -> [QueueSection] {
  var itemsByKind: [SectionKind: [QueueItem]] = [:]

  for pullRequest in input.authoredPullRequests {
    if pullRequest.isDraft {
      itemsByKind[.waiting, default: []].append(
        authoredItem(pullRequest, symbol: .waiting, badge: Badge(text: "Draft", variant: .neutral), now: now))
    } else if pullRequest.isFailing {
      let checkWord = pullRequest.failedCheckCount == 1 ? "check" : "checks"
      itemsByKind[.fix, default: []].append(
        authoredItem(pullRequest, symbol: .failing, badge: Badge(text: "\(pullRequest.failedCheckCount) \(checkWord) failed", variant: .failing), now: now))
    } else if pullRequest.reviewDecision == .approved {
      itemsByKind[.merge, default: []].append(
        authoredItem(pullRequest, symbol: .merge, badge: Badge(text: "Approved", variant: .ready), now: now))
    } else {
      let badge = pullRequest.reviewDecision == .changesRequested ? Badge(text: "Changes requested", variant: .urgent) : nil
      itemsByKind[.waiting, default: []].append(authoredItem(pullRequest, symbol: .waiting, badge: badge, now: now))
    }
  }

  for pullRequest in input.reviewRequests where !pullRequest.authorIsBot {
    itemsByKind[.review, default: []].append(reviewItem(pullRequest, viewerLogin: input.viewerLogin, now: now))
  }
  let botPullRequestsByAuthor = Dictionary(grouping: input.reviewRequests.filter(\.authorIsBot), by: \.author)
  for (botLogin, pullRequests) in botPullRequestsByAuthor {
    itemsByKind[.review, default: []].append(botReviewItem(botLogin: botLogin, pullRequests: pullRequests, now: now))
  }

  for ticket in input.jiraTickets {
    if let item = tidyItem(ticket, authoredPullRequests: input.authoredPullRequests, now: now) {
      itemsByKind[.tidy, default: []].append(item)
    }
  }

  // Take the newest per key before reading the state, so a passing re-run clears a failure.
  // GitHub checks cover PR branches, so a key whose newest pipeline has a PR gives no row.
  let recentPipelines = input.pipelines.filter { now.timeIntervalSince($0.createdAt) <= pipelineWindow }
  let newestPipelines = newestPipelinePerKey(recentPipelines).filter { !$0.hasPullRequest }
  for pipeline in newestPipelines {
    switch pipeline.state {
    case .failed:
      itemsByKind[.fix, default: []].append(
        pipelineItem(pipeline, symbol: .failing, badge: Badge(text: "Pipeline failed", variant: .failing), now: now))
    case .running:
      itemsByKind[.watch, default: []].append(
        pipelineItem(pipeline, symbol: .running, badge: Badge(text: "Running", variant: .neutral), now: now))
    case .onHold:
      itemsByKind[.watch, default: []].append(
        pipelineItem(pipeline, symbol: .approvalHold, badge: Badge(text: "Needs approval", variant: .urgent), now: now))
    case .succeeded:
      break
    }
  }

  return SectionKind.allCases.compactMap { kind in
    guard let items = itemsByKind[kind], !items.isEmpty else { return nil }
    return QueueSection(kind: kind, items: items.sorted { $0.sortDate < $1.sortDate })
  }
}

extension PullRequest {
  var isFailing: Bool { checkState == .failure || checkState == .error }
  var itemId: String { "pr:\(repository)#\(number)" }
}

private func authoredItem(_ pullRequest: PullRequest, symbol: RowSymbol, badge: Badge?, now: Date) -> QueueItem {
  QueueItem(
    id: pullRequest.itemId, title: pullRequest.title,
    meta: "\(pullRequest.repository) · \(shortAge(from: pullRequest.updatedAt, now: now))",
    url: pullRequest.url, symbol: symbol, badge: badge, sortDate: pullRequest.updatedAt,
    strip: statusStrip(pullRequest), reference: "#\(pullRequest.number)")
}

private func statusStrip(_ pullRequest: PullRequest) -> StatusStrip {
  let checks: StatusStrip.Checks? =
    switch pullRequest.checkState {
    case .success: .passed
    case .failure, .error: .failed
    case .pending, .expected: .running
    case nil: nil
    }
  let threads =
    pullRequest.unresolvedThreadCount > 0
    ? StatusStrip.Threads(
      unresolvedCount: pullRequest.unresolvedThreadCount, isLowerBound: pullRequest.hasMoreThreadsThanFetched)
    : nil
  // Only a failing non-draft gets the "N checks failed" badge; a failing draft shows "Draft".
  return StatusStrip(
    checks: checks, threads: threads, approvals: approvalsPart(pullRequest), announcesFailedChecks: pullRequest.isDraft && checks == .failed)
}

private func approvalsPart(_ pullRequest: PullRequest) -> StatusStrip.Approvals? {
  if pullRequest.isDraft { return nil }
  let required = pullRequest.requiredApprovalCount
  if required == 0 {
    return pullRequest.approvalCount > 0 ? StatusStrip.Approvals(given: pullRequest.approvalCount, required: 0) : nil
  }
  return StatusStrip.Approvals(given: min(pullRequest.approvalCount, required), required: required)
}

private func reviewItem(_ pullRequest: PullRequest, viewerLogin: String, now: Date) -> QueueItem {
  let requestedAt = pullRequest.reviewRequestedAt ?? pullRequest.updatedAt
  let waitingSeconds = now.timeIntervalSince(requestedAt)
  let isDirectRequest = pullRequest.requestedReviewerLogins.contains(viewerLogin)
  // A teammate can pick up a team request, so only direct requests turn urgent.
  let badge =
    isDirectRequest && waitingSeconds >= urgentReviewAge
    ? Badge(text: "Waiting \(Int(waitingSeconds / 86400))d", variant: .urgent)
    : Badge(text: "+\(pullRequest.additions) \u{2212}\(pullRequest.deletions)", variant: .neutral)
  var metaParts = [pullRequest.repository, pullRequest.author]
  if !isDirectRequest, let teamSlug = pullRequest.requestedTeamSlugs.first {
    metaParts.append("team \(teamSlug)")
  }
  metaParts.append(shortAge(from: requestedAt, now: now))
  return QueueItem(
    id: pullRequest.itemId, title: pullRequest.title, meta: metaParts.joined(separator: " · "),
    url: pullRequest.url, symbol: .review, badge: badge, sortDate: requestedAt, reference: "#\(pullRequest.number)")
}

// Bot PRs (Dependabot, Renovate) collapse into one row per bot that opens a GitHub search.
private func botReviewItem(botLogin: String, pullRequests: [PullRequest], now: Date) -> QueueItem {
  let oldestRequest = pullRequests.map { $0.reviewRequestedAt ?? $0.updatedAt }.min() ?? now
  let repositoryCount = Set(pullRequests.map(\.repository)).count
  let displayName = botLogin.replacingOccurrences(of: "[bot]", with: "").capitalized
  let searchQuery = "is:pr is:open review-requested:@me author:app/\(botLogin)"
  let urlSafeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
  let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: urlSafeCharacters) ?? ""
  return QueueItem(
    id: "bots:\(botLogin)",
    title: "\(pullRequests.count) \(displayName) \(pullRequests.count == 1 ? "PR" : "PRs")",
    meta: "\(repositoryCount) \(repositoryCount == 1 ? "repo" : "repos") · \(shortAge(from: oldestRequest, now: now))",
    url: URL(string: "https://github.com/pulls?q=\(encodedQuery)")!,
    symbol: .review, badge: Badge(text: "Bot", variant: .neutral), sortDate: oldestRequest)
}

private func tidyItem(_ ticket: JiraTicket, authoredPullRequests: [PullRequest], now: Date) -> QueueItem? {
  let matchedPullRequests = authoredPullRequests.filter {
    ticketKey(ticket.key, matches: $0.title) || ticketKey(ticket.key, matches: $0.headBranch)
  }
  let symbol: RowSymbol
  let badgeText: String
  if matchedPullRequests.isEmpty {
    symbol = .noPullRequest
    badgeText = "No PR"
  } else if matchedPullRequests.allSatisfy(\.hasNoReviewer) {
    symbol = .noReviewer
    badgeText = "No reviewer"
  } else {
    return nil
  }
  return QueueItem(
    id: "jira:\(ticket.key)", title: ticket.summary,
    meta: "\(ticket.key) · \(ticket.statusName) · \(shortAge(from: ticket.updatedAt, now: now))",
    url: ticket.url, symbol: symbol, badge: Badge(text: badgeText, variant: .neutral), sortDate: ticket.updatedAt)
}

extension PullRequest {
  var hasNoReviewer: Bool { requestedReviewerLogins.isEmpty && requestedTeamSlugs.isEmpty && reviewCount == 0 }
}

extension Pipeline {
  // A manual release (api) and a merge (webhook) on the same branch are separate rows.
  var itemId: String { "pipeline:\(projectSlug):\(ref):\(triggerType)" }
}

// Keeps the input order.
func newestPipelinePerKey(_ pipelines: [Pipeline]) -> [Pipeline] {
  let newestByKey = Dictionary(grouping: pipelines, by: \.itemId).mapValues { $0.max { $0.createdAt < $1.createdAt }! }
  return pipelines.filter { newestByKey[$0.itemId] == $0 }
}

private func pipelineItem(_ pipeline: Pipeline, symbol: RowSymbol, badge: Badge, now: Date) -> QueueItem {
  let repository = pipeline.projectSlug.split(separator: "/").last.map(String.init) ?? pipeline.projectSlug
  return QueueItem(
    id: pipeline.itemId, title: "\(repository) \(pipeline.ref)",
    meta: "#\(pipeline.number) · \(pipeline.refIsTag ? "tag" : "branch") · \(shortAge(from: pipeline.createdAt, now: now))",
    url: pipeline.url, symbol: symbol, badge: badge, sortDate: pipeline.createdAt)
}
