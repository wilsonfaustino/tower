import Foundation

public struct QueueInput: Sendable {
  public var viewerLogin: String
  public var authoredPullRequests: [PullRequest]
  public var reviewRequests: [PullRequest]
  public var jiraTickets: [JiraTicket]
  public var pipelines: [Pipeline]
  public var dismissedPipelines: Set<PipelineDismissal>
  public var dismissedPullRequests: Set<PullRequestDismissal>
  public var mergedPullRequests: [MergedPullRequest]
  public var teamAuthorFilters: TeamAuthorFilters
  public var reviewRequestScope: ReviewRequestScope

  public init(
    viewerLogin: String, authoredPullRequests: [PullRequest], reviewRequests: [PullRequest], jiraTickets: [JiraTicket],
    pipelines: [Pipeline], dismissedPipelines: Set<PipelineDismissal> = [],
    dismissedPullRequests: Set<PullRequestDismissal> = [], mergedPullRequests: [MergedPullRequest] = [],
    teamAuthorFilters: TeamAuthorFilters = TeamAuthorFilters(), reviewRequestScope: ReviewRequestScope = .directAndTeam
  ) {
    self.viewerLogin = viewerLogin
    self.authoredPullRequests = authoredPullRequests
    self.reviewRequests = reviewRequests
    self.jiraTickets = jiraTickets
    self.pipelines = pipelines
    self.dismissedPipelines = dismissedPipelines
    self.dismissedPullRequests = dismissedPullRequests
    self.mergedPullRequests = mergedPullRequests
    self.teamAuthorFilters = teamAuthorFilters
    self.reviewRequestScope = reviewRequestScope
  }
}

// A review request older than this turns urgent.
private let urgentReviewAge: TimeInterval = 24 * 3600

public func buildQueue(_ input: QueueInput, now: Date) -> [QueueSection] {
  var itemsByKind: [SectionKind: [QueueItem]] = [:]
  var waitingRows: [WaitingRow] = []

  for pullRequest in input.authoredPullRequests {
    if pullRequest.isDraft {
      waitingRows.append(
        WaitingRow(
          pullRequest: pullRequest,
          item: authoredItem(pullRequest, symbol: .draftPullRequest, badge: Badge(text: "Draft", variant: .neutral), now: now)))
    } else if pullRequest.isFailing {
      let checkWord = pullRequest.failedCheckCount == 1 ? "check" : "checks"
      itemsByKind[.fix, default: []].append(
        authoredItem(pullRequest, symbol: .failing, badge: Badge(text: "\(pullRequest.failedCheckCount) \(checkWord) failed", variant: .failing), now: now))
    } else if pullRequest.reviewDecision == .approved {
      itemsByKind[.merge, default: []].append(
        authoredItem(pullRequest, symbol: .merge, badge: Badge(text: "Approved", variant: .ready), now: now))
    } else {
      let badge = pullRequest.reviewDecision == .changesRequested ? Badge(text: "Changes requested", variant: .urgent) : nil
      waitingRows.append(
        WaitingRow(pullRequest: pullRequest, item: authoredItem(pullRequest, symbol: .pullRequest, badge: badge, now: now)))
    }
  }

  let openReviewRequests = input.reviewRequests.filter {
    isOpenReviewRequest(
      $0, viewerLogin: input.viewerLogin, teamAuthorFilters: input.teamAuthorFilters,
      reviewRequestScope: input.reviewRequestScope)
      && !input.dismissedPullRequests.contains($0.dismissal)
  }
  for pullRequest in openReviewRequests where !pullRequest.authorIsBot {
    itemsByKind[.review, default: []].append(reviewItem(pullRequest, viewerLogin: input.viewerLogin, now: now))
  }
  let botPullRequestsByAuthor = Dictionary(grouping: openReviewRequests.filter(\.authorIsBot), by: \.author)
  for (botLogin, pullRequests) in botPullRequestsByAuthor {
    itemsByKind[.review, default: []].append(
      botReviewItem(botLogin: botLogin, pullRequests: pullRequests, viewerLogin: input.viewerLogin, now: now))
  }
  if !waitingRows.isEmpty {
    itemsByKind[.waiting] = groupedByRepository(waitingRows, authoredPullRequests: input.authoredPullRequests, now: now)
  }

  for ticket in input.jiraTickets {
    if let item = tidyItem(
      ticket, authoredPullRequests: input.authoredPullRequests, mergedPullRequests: input.mergedPullRequests, now: now)
    {
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
      // Checked after the newest per key, so a dismissed newest pipeline does not bring back an older failure.
      if input.dismissedPipelines.contains(pipeline.dismissal) { break }
      itemsByKind[.fix, default: []].append(
        pipelineItem(
          pipeline, symbol: .failing, badge: Badge(text: "Pipeline failed", variant: .failing), now: now,
          dismissal: .pipeline(pipeline.dismissal)))
    case .running:
      itemsByKind[.watch, default: []].append(
        pipelineItem(pipeline, symbol: .running, badge: Badge(text: "Running", variant: .neutral), now: now))
    case .onHold:
      itemsByKind[.watch, default: []].append(
        pipelineItem(pipeline, symbol: .approvalHold, badge: Badge(text: "Needs approval", variant: .urgent), now: now))
    case .succeeded, .canceled:
      break
    }
  }

  return SectionKind.allCases.compactMap { kind in
    guard let items = itemsByKind[kind], !items.isEmpty else { return nil }
    // Ties keep the input order, so rows with the same date do not swap places between refreshes.
    let sortedItems = items.enumerated().sorted { ($0.element.sortDate, $0.offset) < ($1.element.sortDate, $1.offset) }
    return QueueSection(kind: kind, items: sortedItems.map(\.element))
  }
}

// The search also matches team requests, which stay after the viewer approves. A direct request always shows.
func isOpenReviewRequest(
  _ pullRequest: PullRequest, viewerLogin: String, teamAuthorFilters: TeamAuthorFilters,
  reviewRequestScope: ReviewRequestScope
) -> Bool {
  pullRequest.requestedReviewerLogins.contains(viewerLogin)
    || (reviewRequestScope == .directAndTeam && pullRequest.viewerLatestReviewState != .approved
      && teamAuthorFilters.allows(pullRequest))
}

extension PullRequest {
  var details: PullRequestDetails {
    PullRequestDetails(
      title: title, reference: "#\(number)", repository: repository, additions: additions, deletions: deletions)
  }
  var isFailing: Bool { checkState == .failure || checkState == .error }
  var itemId: String { "pr:\(repository)#\(number)" }
}

private func authoredItem(_ pullRequest: PullRequest, symbol: RowSymbol, badge: Badge?, now: Date) -> QueueItem {
  QueueItem(
    id: pullRequest.itemId, title: pullRequest.title,
    tag: pullRequest.repository, meta: shortAge(from: pullRequest.updatedAt, now: now),
    url: pullRequest.url, symbol: symbol, badge: badge, sortDate: pullRequest.updatedAt,
    strip: statusStrip(pullRequest), reference: "#\(pullRequest.number)", details: pullRequest.details)
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
    : nil
  let teamSlug = isDirectRequest ? nil : pullRequest.requestedTeamSlugs.first
  return QueueItem(
    id: pullRequest.itemId, title: pullRequest.title, tag: pullRequest.repository,
    meta: "\(pullRequest.author) · \(shortAge(from: requestedAt, now: now))", metaTeam: teamSlug.map { "team \($0)" },
    url: pullRequest.url, symbol: .review, badge: badge, sortDate: requestedAt, reference: "#\(pullRequest.number)",
    details: pullRequest.details, dismissal: .pullRequest(pullRequest.dismissal))
}

private func gitHubPullsSearchURL(_ searchQuery: String) -> URL {
  let urlSafeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
  let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: urlSafeCharacters) ?? ""
  return URL(string: "https://github.com/pulls?q=\(encodedQuery)")!
}

// Bot PRs (Dependabot, Renovate) collapse into one row per bot that opens a GitHub search.
private func botReviewItem(botLogin: String, pullRequests: [PullRequest], viewerLogin: String, now: Date) -> QueueItem {
  let oldestRequest = pullRequests.map { $0.reviewRequestedAt ?? $0.updatedAt }.min() ?? now
  let repositoryCount = Set(pullRequests.map(\.repository)).count
  let displayName = botLogin.replacingOccurrences(of: "[bot]", with: "").capitalized
  let children = pullRequests.map { reviewItem($0, viewerLogin: viewerLogin, now: now) }.sorted { $0.sortDate < $1.sortDate }
  return QueueItem(
    id: "bots:\(botLogin)",
    title: "\(pullRequests.count) \(displayName) \(pullRequests.count == 1 ? "PR" : "PRs")", tag: "bot",
    meta: "\(repositoryCount) \(repositoryCount == 1 ? "repo" : "repos") · \(shortAge(from: oldestRequest, now: now))",
    url: gitHubPullsSearchURL("is:pr is:open review-requested:@me author:app/\(botLogin)"),
    symbol: .review, badge: nil, sortDate: oldestRequest, children: children)
}

// This many units of work in one repo's Waiting PRs become one repo group row. A unit is one PR or one stack.
private let minimumRepoGroupUnitCount = 3

private struct WaitingRow {
  var pullRequest: PullRequest
  var item: QueueItem
}

extension PullRequest {
  // "<owner>/<repo>" from the PR URL (https://github.com/<owner>/<repo>/pull/<number>), so same-named repos in two
  // organizations stay apart. The PR model stores only the repo name.
  var repositoryPath: String {
    // The first path component is the root.
    let pathParts = Array(url.pathComponents.dropFirst())
    return pathParts.count >= 2 ? "\(pathParts[0])/\(pathParts[1])" : repository
  }

  // Unlike itemId, it includes the owner.
  fileprivate var stackKey: String { "\(repositoryPath)#\(number)" }
}

private struct BranchKey: Hashable {
  var repositoryPath: String
  var branch: String
}

private struct StackPosition {
  // The same for every PR of one stack.
  var stackId: String
  // 0 for a bottom PR of a stack, and one more than its deepest parent for any other PR.
  var depth: Int
}

// A PR stacks on each open authored PR whose head branch is its base branch in the same repo. A stack is each connected
// set of such links, so one branch opened against two bases joins both PRs into one stack. All authored PRs take part,
// so a stack member in Fix or Merge still joins the Waiting members above and below it into one unit.
// The head branch of a fork PR is in the fork, so a fork PR is never the base of another PR.
private func stackPositions(_ pullRequests: [PullRequest]) -> [String: StackPosition] {
  let pullRequestsByHeadBranch = Dictionary(grouping: pullRequests.filter { $0.isCrossRepository != true }) {
    BranchKey(repositoryPath: $0.repositoryPath, branch: $0.headBranch)
  }
  var childKeysByKey: [String: [String]] = [:]
  var parentKeysByKey: [String: [String]] = [:]
  var linkedKeysByKey: [String: [String]] = [:]
  var parentCountByKey: [String: Int] = [:]
  for pullRequest in pullRequests {
    guard let baseBranch = pullRequest.baseBranch else { continue }
    let parents = pullRequestsByHeadBranch[BranchKey(repositoryPath: pullRequest.repositoryPath, branch: baseBranch)] ?? []
    for parent in parents where parent.stackKey != pullRequest.stackKey {
      childKeysByKey[parent.stackKey, default: []].append(pullRequest.stackKey)
      parentKeysByKey[pullRequest.stackKey, default: []].append(parent.stackKey)
      parentCountByKey[pullRequest.stackKey, default: 0] += 1
      linkedKeysByKey[pullRequest.stackKey, default: []].append(parent.stackKey)
      linkedKeysByKey[parent.stackKey, default: []].append(pullRequest.stackKey)
    }
  }

  var stackIdByKey: [String: String] = [:]
  for pullRequest in pullRequests where stackIdByKey[pullRequest.stackKey] == nil {
    var pendingKeys = [pullRequest.stackKey]
    while let key = pendingKeys.popLast() {
      guard stackIdByKey[key] == nil else { continue }
      stackIdByKey[key] = pullRequest.stackKey
      pendingKeys += linkedKeysByKey[key] ?? []
    }
  }

  // One topological pass from the bottom PRs. A PR's depth is one more than its deepest parent, so every parent sorts
  // before its children.
  var depthByKey: [String: Int] = [:]
  var remainingParentCountByKey = parentCountByKey
  var readyKeys = pullRequests.map(\.stackKey).filter { parentCountByKey[$0] == nil }
  while true {
    while let key = readyKeys.popLast() {
      // A child already released from a loop keeps its depth, so it is not pushed above its own children.
      for childKey in childKeysByKey[key] ?? [] where remainingParentCountByKey[childKey]! > 0 {
        depthByKey[childKey] = max(depthByKey[childKey] ?? 0, (depthByKey[key] ?? 0) + 1)
        remainingParentCountByKey[childKey]! -= 1
        if remainingParentCountByKey[childKey] == 0 { readyKeys.append(childKey) }
      }
    }
    // PRs in a loop of links wait on each other, and so do the PRs above the loop. Following waiting parents from any
    // waiting PR comes back to a PR in the loop. Releasing that PR lets the pass reach the rest in order.
    let waitingKeys = Set(remainingParentCountByKey.filter { $0.value > 0 }.keys)
    guard var loopKey = waitingKeys.min() else { break }
    var walkedKeys: Set<String> = []
    while walkedKeys.insert(loopKey).inserted,
      let waitingParentKey = (parentKeysByKey[loopKey] ?? []).filter(waitingKeys.contains).min()
    {
      loopKey = waitingParentKey
    }
    remainingParentCountByKey[loopKey] = 0
    readyKeys.append(loopKey)
  }

  let positions = pullRequests.map {
    ($0.stackKey, StackPosition(stackId: stackIdByKey[$0.stackKey]!, depth: depthByKey[$0.stackKey] ?? 0))
  }
  return Dictionary(positions) { first, _ in first }
}

// Keeps the input order, so rows with the same date keep their place across refreshes. A group takes the place of its
// oldest member, so it sorts where that PR would, also next to a row with the same date.
private func groupedByRepository(_ waitingRows: [WaitingRow], authoredPullRequests: [PullRequest], now: Date) -> [QueueItem] {
  let positions = stackPositions(authoredPullRequests)
  let rowsByRepository = Dictionary(grouping: waitingRows, by: \.pullRequest.repositoryPath)
  let groupByRepository = rowsByRepository.compactMapValues { repositoryRows -> (anchorStackKey: String, item: QueueItem)? in
    let units = Array(Dictionary(grouping: repositoryRows) { positions[$0.pullRequest.stackKey]!.stackId }.values)
    guard units.count >= minimumRepoGroupUnitCount else { return nil }
    let orderedRows = orderedGroupRows(units, positions: positions)
    let oldestRowDate = oldestDate(repositoryRows)
    let anchorRow = repositoryRows.first { $0.item.sortDate == oldestRowDate }!
    return (anchorRow.pullRequest.stackKey, repoGroupItem(rows: orderedRows, now: now))
  }
  // The set keeps a PR that the input holds twice from placing its group twice.
  var placedRepositoryPaths: Set<String> = []
  return waitingRows.compactMap { row in
    let repositoryPath = row.pullRequest.repositoryPath
    guard let group = groupByRepository[repositoryPath] else { return row.item }
    let isAnchor = row.pullRequest.stackKey == group.anchorStackKey
    return isAnchor && placedRepositoryPaths.insert(repositoryPath).inserted ? group.item : nil
  }
}

// Units by their oldest PR, and the PRs of a stack bottom first. Ties fall back to the PR number, so the order inside an
// expanded group does not change between refreshes.
private func orderedGroupRows(_ units: [[WaitingRow]], positions: [String: StackPosition]) -> [WaitingRow] {
  func isBefore(_ left: WaitingRow, _ right: WaitingRow) -> Bool {
    let (leftDepth, rightDepth) = (positions[left.pullRequest.stackKey]!.depth, positions[right.pullRequest.stackKey]!.depth)
    if leftDepth != rightDepth { return leftDepth < rightDepth }
    if left.item.sortDate != right.item.sortDate { return left.item.sortDate < right.item.sortDate }
    return left.pullRequest.number < right.pullRequest.number
  }
  let sortedUnits = units.map { $0.sorted(by: isBefore) }
  return sortedUnits.sorted {
    let (leftDate, rightDate) = (oldestDate($0), oldestDate($1))
    return leftDate != rightDate ? leftDate < rightDate : $0[0].pullRequest.number < $1[0].pullRequest.number
  }.flatMap(\.self)
}

private func oldestDate(_ rows: [WaitingRow]) -> Date { rows.map(\.item.sortDate).min()! }

// The group sorts where its oldest PR would, and its age is the oldest PR's age, as on the bot group.
private func repoGroupItem(rows: [WaitingRow], now: Date) -> QueueItem {
  let repositoryPath = rows[0].pullRequest.repositoryPath
  let oldestRowDate = oldestDate(rows)
  // A draft shows "Draft", not "Changes requested", so it does not count.
  let changesRequestedCount = rows.filter { !$0.pullRequest.isDraft && $0.pullRequest.reviewDecision == .changesRequested }.count
  return QueueItem(
    id: "repo:\(repositoryPath)", title: rows[0].pullRequest.repository,
    meta: "\(rows.count) PRs · \(shortAge(from: oldestRowDate, now: now))",
    url: gitHubPullsSearchURL("is:pr is:open author:@me repo:\(repositoryPath)"), symbol: .pullRequest,
    badge: changesRequestedCount > 0 ? Badge(text: "\(changesRequestedCount) changes requested", variant: .urgent) : nil,
    sortDate: oldestRowDate, children: rows.map(\.item))
}

private func tidyItem(
  _ ticket: JiraTicket, authoredPullRequests: [PullRequest], mergedPullRequests: [MergedPullRequest], now: Date
) -> QueueItem? {
  // A merged PR means the code is done and the ticket waits for a deploy or a status change, not for the owner.
  let hasMergedPullRequest = mergedPullRequests.contains {
    ticketKey(ticket.key, matches: $0.title) || ticketKey(ticket.key, matches: $0.headBranch)
  }
  if hasMergedPullRequest { return nil }
  let matchedPullRequests = authoredPullRequests.filter {
    ticketKey(ticket.key, matches: $0.title) || ticketKey(ticket.key, matches: $0.headBranch)
  }
  // A draft counts as the ticket's PR, but you do not ask for a review on a draft.
  let nonDraftPullRequests = matchedPullRequests.filter { !$0.isDraft }
  let badgeText: String
  if matchedPullRequests.isEmpty {
    badgeText = "No PR"
  } else if !nonDraftPullRequests.isEmpty && nonDraftPullRequests.allSatisfy(\.hasNoReviewer) {
    badgeText = "No reviewer"
  } else {
    return nil
  }
  return QueueItem(
    id: "jira:\(ticket.key)", title: ticket.summary, tag: ticket.key,
    meta: "\(ticket.statusName) · \(shortAge(from: ticket.updatedAt, now: now))",
    url: ticket.url, symbol: RowSymbol(jiraIssueTypeName: ticket.issueTypeName),
    badge: Badge(text: badgeText, variant: .neutral), sortDate: ticket.updatedAt)
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

private func pipelineItem(
  _ pipeline: Pipeline, symbol: RowSymbol, badge: Badge, now: Date, dismissal: Dismissal? = nil
) -> QueueItem {
  let repository = pipeline.projectSlug.split(separator: "/").last.map(String.init) ?? pipeline.projectSlug
  return QueueItem(
    id: pipeline.itemId, title: pipeline.ref, tag: repository,
    meta: "#\(pipeline.number) · \(pipeline.refIsTag ? "tag" : "branch") · \(shortAge(from: pipeline.createdAt, now: now))",
    url: pipeline.url, symbol: symbol, badge: badge, sortDate: pipeline.createdAt, dismissal: dismissal)
}
