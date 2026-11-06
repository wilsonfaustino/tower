import Foundation

public enum ReviewDecision: String, Codable, Sendable {
  case approved = "APPROVED"
  case changesRequested = "CHANGES_REQUESTED"
  case reviewRequired = "REVIEW_REQUIRED"
}

public enum CheckState: String, Codable, Sendable {
  case success = "SUCCESS"
  case failure = "FAILURE"
  case error = "ERROR"
  case pending = "PENDING"
  case expected = "EXPECTED"
}

public struct PullRequest: Codable, Sendable, Equatable {
  public var repository: String
  public var number: Int
  public var title: String
  public var url: URL
  public var author: String
  public var authorIsBot: Bool
  public var isDraft: Bool
  public var updatedAt: Date
  public var headBranch: String
  public var reviewDecision: ReviewDecision?
  public var checkState: CheckState?
  public var failedCheckCount: Int
  public var additions: Int
  public var deletions: Int
  public var requestedReviewerLogins: [String]
  public var requestedTeamSlugs: [String]
  public var reviewCount: Int
  public var reviewRequestedAt: Date?

  public init(
    repository: String, number: Int, title: String, url: URL, author: String, authorIsBot: Bool, isDraft: Bool,
    updatedAt: Date, headBranch: String, reviewDecision: ReviewDecision?, checkState: CheckState?,
    failedCheckCount: Int, additions: Int, deletions: Int, requestedReviewerLogins: [String],
    requestedTeamSlugs: [String], reviewCount: Int, reviewRequestedAt: Date?
  ) {
    self.repository = repository
    self.number = number
    self.title = title
    self.url = url
    self.author = author
    self.authorIsBot = authorIsBot
    self.isDraft = isDraft
    self.updatedAt = updatedAt
    self.headBranch = headBranch
    self.reviewDecision = reviewDecision
    self.checkState = checkState
    self.failedCheckCount = failedCheckCount
    self.additions = additions
    self.deletions = deletions
    self.requestedReviewerLogins = requestedReviewerLogins
    self.requestedTeamSlugs = requestedTeamSlugs
    self.reviewCount = reviewCount
    self.reviewRequestedAt = reviewRequestedAt
  }
}

public struct JiraTicket: Codable, Sendable, Equatable {
  public var key: String
  public var summary: String
  public var statusName: String
  public var updatedAt: Date
  public var url: URL

  public init(key: String, summary: String, statusName: String, updatedAt: Date, url: URL) {
    self.key = key
    self.summary = summary
    self.statusName = statusName
    self.updatedAt = updatedAt
    self.url = url
  }
}

public enum SectionKind: Int, CaseIterable, Comparable, Sendable {
  case fix, review, merge, tidy

  public static func < (lhs: SectionKind, rhs: SectionKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum BadgeVariant: Sendable {
  case failing, urgent, ready, neutral
}

public struct Badge: Equatable, Sendable {
  public var text: String
  public var variant: BadgeVariant

  public init(text: String, variant: BadgeVariant) {
    self.text = text
    self.variant = variant
  }
}

public enum RowSymbol: String, CaseIterable, Sendable {
  case failing = "xmark.circle"
  case review = "eye"
  case merge = "arrow.triangle.merge"
  case noPullRequest = "arrow.triangle.branch"
  case noReviewer = "person.crop.circle.badge.questionmark"
}

public struct QueueItem: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var meta: String
  public var url: URL
  public var symbol: RowSymbol
  public var badge: Badge?
  public var sortDate: Date

  public init(id: String, title: String, meta: String, url: URL, symbol: RowSymbol, badge: Badge?, sortDate: Date) {
    self.id = id
    self.title = title
    self.meta = meta
    self.url = url
    self.symbol = symbol
    self.badge = badge
    self.sortDate = sortDate
  }
}

public struct QueueSection: Identifiable, Equatable, Sendable {
  public var kind: SectionKind
  public var items: [QueueItem]
  public var id: SectionKind { kind }

  public init(kind: SectionKind, items: [QueueItem]) {
    self.kind = kind
    self.items = items
  }
}
