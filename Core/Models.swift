import Foundation

public enum ReviewDecision: String, Codable, Sendable {
  case approved = "APPROVED"
  case changesRequested = "CHANGES_REQUESTED"
  case reviewRequired = "REVIEW_REQUIRED"
}

public enum ReviewState: String, Codable, Sendable {
  case approved = "APPROVED"
  case changesRequested = "CHANGES_REQUESTED"
  case commented = "COMMENTED"
  case dismissed = "DISMISSED"
  case pending = "PENDING"
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
  public var unresolvedThreadCount: Int
  // True when the PR has more review threads than the fetched first page, so the unresolved count is a lower bound.
  public var hasMoreThreadsThanFetched: Bool
  public var approvalCount: Int
  public var requiredApprovalCount: Int
  public var viewerLatestReviewState: ReviewState?

  public init(
    repository: String, number: Int, title: String, url: URL, author: String, authorIsBot: Bool, isDraft: Bool,
    updatedAt: Date, headBranch: String, reviewDecision: ReviewDecision?, checkState: CheckState?,
    failedCheckCount: Int, additions: Int, deletions: Int, requestedReviewerLogins: [String],
    requestedTeamSlugs: [String], reviewCount: Int, reviewRequestedAt: Date?, unresolvedThreadCount: Int = 0,
    hasMoreThreadsThanFetched: Bool = false, approvalCount: Int = 0, requiredApprovalCount: Int = 1,
    viewerLatestReviewState: ReviewState? = nil
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
    self.unresolvedThreadCount = unresolvedThreadCount
    self.hasMoreThreadsThanFetched = hasMoreThreadsThanFetched
    self.approvalCount = approvalCount
    self.requiredApprovalCount = requiredApprovalCount
    self.viewerLatestReviewState = viewerLatestReviewState
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

public enum PipelineState: String, Codable, Sendable {
  case running, onHold, failed, succeeded
}

public struct Pipeline: Codable, Sendable, Equatable {
  // The CircleCI pipeline id. The pipeline number is not unique across projects.
  public var id: String
  public var projectSlug: String
  public var number: Int
  public var ref: String
  public var refIsTag: Bool
  public var triggerType: String
  public var hasPullRequest: Bool
  public var createdAt: Date
  public var state: PipelineState
  public var url: URL
  // Nil when the client did not read the workflows: a PR pipeline, an errored pipeline or no workflows.
  public var newestWorkflowId: String?

  public init(
    id: String, projectSlug: String, number: Int, ref: String, refIsTag: Bool, triggerType: String,
    hasPullRequest: Bool, createdAt: Date, state: PipelineState, url: URL, newestWorkflowId: String?
  ) {
    self.id = id
    self.projectSlug = projectSlug
    self.number = number
    self.ref = ref
    self.refIsTag = refIsTag
    self.triggerType = triggerType
    self.hasPullRequest = hasPullRequest
    self.createdAt = createdAt
    self.state = state
    self.url = url
    self.newestWorkflowId = newestWorkflowId
  }
}

public enum SectionKind: Int, CaseIterable, Comparable, Sendable {
  case fix, review, merge, tidy, watch, waiting

  public static func < (lhs: SectionKind, rhs: SectionKind) -> Bool { lhs.rawValue < rhs.rawValue }

  public var title: String {
    switch self {
    case .fix: "Fix"
    case .review: "Review"
    case .merge: "Merge"
    case .tidy: "Tidy"
    case .watch: "Watch"
    case .waiting: "Waiting"
    }
  }
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
  case running = "airplane.departure"
  case approvalHold = "hand.raised"
  case waiting = "hourglass"
}

// The status strip of one authored PR row. A nil part is hidden.
public struct StatusStrip: Equatable, Sendable {
  public enum Checks: Sendable {
    case passed, failed, running
  }

  public struct Threads: Equatable, Sendable {
    public var unresolvedCount: Int
    // True when GitHub has more threads than Tower fetched, so the real count can be higher.
    public var isLowerBound: Bool

    public init(unresolvedCount: Int, isLowerBound: Bool) {
      self.unresolvedCount = unresolvedCount
      self.isLowerBound = isLowerBound
    }
  }

  // With required 0, given is not capped and the row shows no open slots.
  public struct Approvals: Equatable, Sendable {
    public var given: Int
    public var required: Int

    public init(given: Int, required: Int) {
      self.given = given
      self.required = required
    }

    // With required 0 the row draws one filled slot, whatever the real count.
    public var slotCount: Int { required == 0 ? min(given, 1) : max(given, required) }
  }

  public var checks: Checks?
  public var threads: Threads?
  public var approvals: Approvals?
  // False when the row badge already says the checks failed.
  public var announcesFailedChecks: Bool

  public init(checks: Checks?, threads: Threads?, approvals: Approvals?, announcesFailedChecks: Bool = false) {
    self.checks = checks
    self.threads = threads
    self.approvals = approvals
    self.announcesFailedChecks = announcesFailedChecks
  }

  public var isEmpty: Bool { checks == nil && threads == nil && approvals == nil }

  public var accessibilityPhrase: String {
    var parts: [String] = []
    switch checks {
    case .passed: parts.append("checks passed")
    case .running: parts.append("checks running")
    case .failed: if announcesFailedChecks { parts.append("checks failed") }
    case nil: break
    }
    if let threads {
      let threadWord = threads.unresolvedCount == 1 ? "thread" : "threads"
      let countPrefix = threads.isLowerBound ? "at least " : ""
      parts.append("\(countPrefix)\(threads.unresolvedCount) unresolved \(threadWord)")
    }
    if let approvals {
      if approvals.required == 0 {
        parts.append("\(approvals.given) \(approvals.given == 1 ? "approval" : "approvals")")
      } else {
        parts.append("\(approvals.given) of \(approvals.required) \(approvals.required == 1 ? "approval" : "approvals")")
      }
    }
    return parts.joined(separator: ", ")
  }
}

public struct PullRequestDetails: Equatable, Sendable {
  public var title: String
  public var reference: String
  public var repository: String
  public var additions: Int
  public var deletions: Int

  public init(title: String, reference: String, repository: String, additions: Int, deletions: Int) {
    self.title = title
    self.reference = reference
    self.repository = repository
    self.additions = additions
    self.deletions = deletions
  }

  // Inflection picks the plural form for the locale and formats the counts with its grouping separators.
  public var diffAccessibilityPhrase: String {
    let phrase = AttributedString(
      localized: "^[\(additions) line](inflect: true) added, ^[\(deletions) line](inflect: true) removed")
    return String(phrase.characters)
  }

  public func additionsText(locale: Locale = .current) -> String {
    "+\(additions.formatted(.number.locale(locale)))"
  }

  // U+2212 minus sign, as in the design, so the sign has the same width as the plus sign.
  public func deletionsText(locale: Locale = .current) -> String {
    "\u{2212}\(deletions.formatted(.number.locale(locale)))"
  }
}

public struct QueueItem: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  // The repo on PR rows. The row truncates it in the middle, so metaTail (author, age) stays visible.
  public var metaLead: String?
  public var metaTail: String
  // The team on team review requests. Shown last and truncated first, so a long slug does not hide the repo.
  public var metaTeam: String?
  public var url: URL
  public var symbol: RowSymbol
  public var badge: Badge?
  public var sortDate: Date
  public var strip: StatusStrip?
  // Shown before the title, for example a PR number.
  public var reference: String?
  // Nil on rows that are not one pull request (bots, tickets, pipelines).
  public var details: PullRequestDetails?
  // Set only on failed pipeline rows, the rows the owner can dismiss.
  public var dismissal: PipelineDismissal?

  public init(
    id: String, title: String, metaLead: String? = nil, meta: String, metaTeam: String? = nil, url: URL,
    symbol: RowSymbol, badge: Badge?,
    sortDate: Date, strip: StatusStrip? = nil, reference: String? = nil, details: PullRequestDetails? = nil,
    dismissal: PipelineDismissal? = nil
  ) {
    self.id = id
    self.title = title
    self.metaLead = metaLead
    self.metaTail = meta
    self.metaTeam = metaTeam
    self.url = url
    self.symbol = symbol
    self.badge = badge
    self.sortDate = sortDate
    self.strip = strip
    self.reference = reference
    self.details = details
    self.dismissal = dismissal
  }

  public var meta: String {
    [metaLead, metaTail, metaTeam].compactMap { $0 }.joined(separator: " · ")
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
