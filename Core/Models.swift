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
  // The head commit SHA. A new commit brings back a dismissed review request.
  public var headCommitId: String?
  // The newest review request aimed at the viewer, or at a requested team when the request is team-only.
  // Notifications read it, so a request to someone else does not look like a new request to the viewer.
  public var viewerReviewRequestedAt: Date?

  public init(
    repository: String, number: Int, title: String, url: URL, author: String, authorIsBot: Bool, isDraft: Bool,
    updatedAt: Date, headBranch: String, reviewDecision: ReviewDecision?, checkState: CheckState?,
    failedCheckCount: Int, additions: Int, deletions: Int, requestedReviewerLogins: [String],
    requestedTeamSlugs: [String], reviewCount: Int, reviewRequestedAt: Date?, unresolvedThreadCount: Int = 0,
    hasMoreThreadsThanFetched: Bool = false, approvalCount: Int = 0, requiredApprovalCount: Int = 1,
    viewerLatestReviewState: ReviewState? = nil, headCommitId: String? = nil, viewerReviewRequestedAt: Date? = nil
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
    self.headCommitId = headCommitId
    self.viewerLatestReviewState = viewerLatestReviewState
    self.viewerReviewRequestedAt = viewerReviewRequestedAt
  }
}

// A PR merged in the last 30 days. Tidy reads it, so a ticket whose PR already merged is not "No PR".
public struct MergedPullRequest: Codable, Sendable, Equatable {
  public var title: String
  public var headBranch: String

  public init(title: String, headBranch: String) {
    self.title = title
    self.headBranch = headBranch
  }
}

public struct JiraTicket: Codable, Sendable, Equatable {
  public var key: String
  public var summary: String
  public var statusName: String
  public var updatedAt: Date
  public var url: URL
  // The Jira issue type name, for example "Bug". Nil in caches written before Tower read the type.
  public var issueTypeName: String?

  public init(key: String, summary: String, statusName: String, updatedAt: Date, url: URL, issueTypeName: String? = nil) {
    self.key = key
    self.summary = summary
    self.statusName = statusName
    self.updatedAt = updatedAt
    self.url = url
    self.issueTypeName = issueTypeName
  }
}

// Canceled means the pipeline ended with no success and no failure: canceled or not-run workflows, or none at all.
public enum PipelineState: String, Codable, Sendable {
  case running, onHold, failed, succeeded, canceled
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
  // Nil when the client has no workflow: an errored pipeline, no workflows, or a failed request for a PR pipeline.
  public var newestWorkflowId: String?
  // The newest run of each workflow name that failed. A rerun of another workflow leaves it the same.
  public var failedWorkflowIds: [String]?

  public init(
    id: String, projectSlug: String, number: Int, ref: String, refIsTag: Bool, triggerType: String,
    hasPullRequest: Bool, createdAt: Date, state: PipelineState, url: URL, newestWorkflowId: String?,
    failedWorkflowIds: [String]? = nil
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
    self.failedWorkflowIds = failedWorkflowIds
  }

  // A PR pipeline whose workflow request failed keeps the placeholder state. A read success always has a workflow id.
  public var workflowStateIsUnknown: Bool { hasPullRequest && state == .succeeded && newestWorkflowId == nil }
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
  case failing = "ph-x-circle"
  case review = "ph-eye"
  case merge = "ph-git-merge"
  case bug = "ph-bug"
  case story = "ph-bookmark-simple"
  case improvement = "ph-arrow-fat-up"
  case epic = "ph-lightning"
  case task = "ph-check-square"
  case subtask = "ph-check-square-offset"
  case ticket = "ph-ticket"
  case running = "ph-airplane-takeoff"
  case approvalHold = "ph-hand-palm"
  case pullRequest = "ph-git-pull-request"
  // Drawn in the Phosphor Bold style like GitHub's draft icon, not part of the Phosphor set.
  case draftPullRequest = "ph-git-pull-request-draft"

  // Company-managed Jira projects name the type "Sub-task", team-managed projects "Subtask".
  public init(jiraIssueTypeName: String?) {
    switch jiraIssueTypeName?.lowercased() {
    case "bug": self = .bug
    case "story": self = .story
    case "improvement": self = .improvement
    case "epic": self = .epic
    case "task": self = .task
    case "sub-task", "subtask": self = .subtask
    default: self = .ticket
    }
  }

  // VoiceOver reads the issue type, because the row icon is hidden from it. Nil on rows whose icon adds no words.
  public var issueTypeSpokenName: String? {
    switch self {
    case .bug: "Bug"
    case .story: "Story"
    case .improvement: "Improvement"
    case .epic: "Epic"
    case .task: "Task"
    case .subtask: "Sub-task"
    case .failing, .review, .merge, .ticket, .running, .approvalHold, .pullRequest, .draftPullRequest: nil
    }
  }
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
  // The short source label shown as a tag before the meta line: the repo, a Jira key, or "bot".
  public var tag: String?
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
  // Set only on the rows the owner can dismiss: failed pipelines and single review requests.
  public var dismissal: Dismissal?
  // Non-empty on a group row (bot PRs, PRs with the same title prefix). The panel expands it in place.
  public var children: [QueueItem]

  public init(
    id: String, title: String, tag: String? = nil, meta: String, metaTeam: String? = nil, url: URL,
    symbol: RowSymbol, badge: Badge?,
    sortDate: Date, strip: StatusStrip? = nil, reference: String? = nil, details: PullRequestDetails? = nil,
    dismissal: Dismissal? = nil, children: [QueueItem] = []
  ) {
    self.id = id
    self.title = title
    self.tag = tag
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
    self.children = children
  }

  public var meta: String {
    [tag, metaTail, metaTeam].compactMap { $0 }.joined(separator: " · ")
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

// The panel tabs. Watch rows are not in a tab: the panel pins them below both tabs.
public enum PanelTab: String, CaseIterable, Sendable {
  case needsYou, waiting

  public var title: String {
    switch self {
    case .needsYou: "Needs you"
    case .waiting: "Waiting"
    }
  }

  public var sectionKinds: [SectionKind] {
    switch self {
    case .needsYou: [.fix, .review, .merge, .tidy]
    case .waiting: [.waiting]
    }
  }
}

public func sections(_ sections: [QueueSection], in tab: PanelTab) -> [QueueSection] {
  sections.filter { tab.sectionKinds.contains($0.kind) }
}

// The raw value is the stored setting.
public enum PanelLayout: String, CaseIterable, Sendable {
  case split, consolidated

  public var title: String {
    switch self {
    case .split: "Split"
    case .consolidated: "Consolidated"
    }
  }
}

// The sections the scroll list shows. The queue builder already leaves out empty sections and keeps
// urgency order, so Consolidated shows the queue as it is and ignores the tab.
public func displayedSections(_ sections: [QueueSection], layout: PanelLayout, tab: PanelTab) -> [QueueSection] {
  switch layout {
  case .split: Core.sections(sections, in: tab)
  case .consolidated: sections
  }
}

// The row status dot. The legend under the list names each case.
public enum StatusDot: CaseIterable, Sendable {
  case failing, urgent, ready, pending

  public var legendLabel: String {
    switch self {
    case .failing: "failing"
    case .urgent: "needs you"
    case .ready: "passing"
    case .pending: "pending"
    }
  }
}

extension QueueItem {
  // A failing, urgent or ready badge sets the dot. Otherwise the checks set it, so a draft with failed checks is red.
  // A group row takes the worst dot of its children.
  public var statusDot: StatusDot {
    if !children.isEmpty {
      let childDots = children.map(\.statusDot)
      let worstFirst: [StatusDot] = [.failing, .urgent, .pending, .ready]
      return worstFirst.first { childDots.contains($0) } ?? .pending
    }
    switch badge?.variant {
    case .failing: return .failing
    case .urgent: return .urgent
    case .ready: return .ready
    case .neutral, nil: break
    }
    switch strip?.checks {
    case .passed: return .ready
    case .failed: return .failing
    case .running, nil: return .pending
    }
  }
}
