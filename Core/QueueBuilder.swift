import Foundation

public struct QueueInput: Sendable {
  public var viewerLogin: String
  public var authoredPullRequests: [PullRequest]
  public var reviewRequests: [PullRequest]
  public var jiraTickets: [JiraTicket]

  public init(viewerLogin: String, authoredPullRequests: [PullRequest], reviewRequests: [PullRequest], jiraTickets: [JiraTicket]) {
    self.viewerLogin = viewerLogin
    self.authoredPullRequests = authoredPullRequests
    self.reviewRequests = reviewRequests
    self.jiraTickets = jiraTickets
  }
}

// A review request older than this turns urgent.
private let urgentReviewAge: TimeInterval = 24 * 3600

public func buildQueue(_ input: QueueInput, now: Date) -> [QueueSection] {
  var itemsByKind: [SectionKind: [QueueItem]] = [:]

  for pullRequest in input.authoredPullRequests where !pullRequest.isDraft {
    if pullRequest.isFailing {
      let checkWord = pullRequest.failedCheckCount == 1 ? "check" : "checks"
      itemsByKind[.fix, default: []].append(
        authoredItem(pullRequest, symbol: .failing, badge: Badge(text: "\(pullRequest.failedCheckCount) \(checkWord) failed", variant: .failing), now: now))
    } else if pullRequest.reviewDecision == .approved {
      itemsByKind[.merge, default: []].append(
        authoredItem(pullRequest, symbol: .merge, badge: Badge(text: "Approved", variant: .ready), now: now))
    }
  }

  for pullRequest in input.reviewRequests {
    itemsByKind[.review, default: []].append(reviewItem(pullRequest, viewerLogin: input.viewerLogin, now: now))
  }

  for ticket in input.jiraTickets {
    if let item = tidyItem(ticket, authoredPullRequests: input.authoredPullRequests, now: now) {
      itemsByKind[.tidy, default: []].append(item)
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

private func authoredItem(_ pullRequest: PullRequest, symbol: RowSymbol, badge: Badge, now: Date) -> QueueItem {
  QueueItem(
    id: pullRequest.itemId, title: pullRequest.title,
    meta: "\(pullRequest.repository) #\(pullRequest.number) · \(shortAge(from: pullRequest.updatedAt, now: now))",
    url: pullRequest.url, symbol: symbol, badge: badge, sortDate: pullRequest.updatedAt)
}

private func reviewItem(_ pullRequest: PullRequest, viewerLogin: String, now: Date) -> QueueItem {
  let requestedAt = pullRequest.reviewRequestedAt ?? pullRequest.updatedAt
  let waitingSeconds = now.timeIntervalSince(requestedAt)
  let badge =
    waitingSeconds >= urgentReviewAge
    ? Badge(text: "Waiting \(Int(waitingSeconds / 86400))d", variant: .urgent)
    : Badge(text: "+\(pullRequest.additions) \u{2212}\(pullRequest.deletions)", variant: .neutral)
  var metaParts = ["\(pullRequest.repository) #\(pullRequest.number)", pullRequest.author]
  if !pullRequest.requestedReviewerLogins.contains(viewerLogin), let teamSlug = pullRequest.requestedTeamSlugs.first {
    metaParts.append("team \(teamSlug)")
  }
  metaParts.append(shortAge(from: requestedAt, now: now))
  return QueueItem(
    id: pullRequest.itemId, title: pullRequest.title, meta: metaParts.joined(separator: " · "),
    url: pullRequest.url, symbol: .review, badge: badge, sortDate: requestedAt)
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
