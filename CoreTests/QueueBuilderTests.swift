import Core
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3600

private func pullRequest(
  owner: String = "acme",
  repository: String = "app-web",
  number: Int = 1,
  title: String = "Some change",
  author: String = "me",
  authorIsBot: Bool = false,
  isDraft: Bool = false,
  updatedHoursAgo: Double = 1,
  headBranch: String = "feature/x",
  reviewDecision: ReviewDecision? = nil,
  checkState: CheckState? = .success,
  failedCheckCount: Int = 0,
  additions: Int = 0,
  deletions: Int = 0,
  requestedReviewerLogins: [String] = [],
  requestedTeamSlugs: [String] = [],
  reviewCount: Int = 0,
  reviewRequestedHoursAgo: Double? = nil,
  unresolvedThreadCount: Int = 0,
  hasMoreThreadsThanFetched: Bool = false,
  approvalCount: Int = 0,
  requiredApprovalCount: Int = 1,
  viewerLatestReviewState: ReviewState? = nil,
  headCommitId: String? = nil,
  baseBranch: String? = nil,
  isCrossRepository: Bool? = nil
) -> PullRequest {
  PullRequest(
    repository: repository, number: number, title: title,
    url: URL(string: "https://github.com/\(owner)/\(repository)/pull/\(number)")!,
    author: author, authorIsBot: authorIsBot, isDraft: isDraft, updatedAt: now.addingTimeInterval(-updatedHoursAgo * hour),
    headBranch: headBranch, reviewDecision: reviewDecision, checkState: checkState,
    failedCheckCount: failedCheckCount, additions: additions, deletions: deletions,
    requestedReviewerLogins: requestedReviewerLogins, requestedTeamSlugs: requestedTeamSlugs,
    reviewCount: reviewCount,
    reviewRequestedAt: reviewRequestedHoursAgo.map { now.addingTimeInterval(-$0 * hour) },
    unresolvedThreadCount: unresolvedThreadCount, hasMoreThreadsThanFetched: hasMoreThreadsThanFetched,
    approvalCount: approvalCount, requiredApprovalCount: requiredApprovalCount, viewerLatestReviewState: viewerLatestReviewState,
    headCommitId: headCommitId, baseBranch: baseBranch, isCrossRepository: isCrossRepository)
}

private func ticket(
  key: String, statusName: String = "In Progress", updatedHoursAgo: Double = 72, issueTypeName: String? = nil
) -> JiraTicket {
  JiraTicket(
    key: key, summary: "Ticket \(key)", statusName: statusName,
    updatedAt: now.addingTimeInterval(-updatedHoursAgo * hour),
    url: URL(string: "https://acme.atlassian.net/browse/\(key)")!, issueTypeName: issueTypeName)
}

private func pipeline(
  projectSlug: String = "gh/acme/app-web",
  number: Int = 1842,
  ref: String = "main",
  refIsTag: Bool = false,
  triggerType: String = "api",
  hasPullRequest: Bool = false,
  createdHoursAgo: Double = 0.1,
  state: PipelineState = .failed,
  newestWorkflowId: String? = "workflow-1"
) -> Pipeline {
  Pipeline(
    id: "pipeline-\(number)", projectSlug: projectSlug, number: number, ref: ref, refIsTag: refIsTag, triggerType: triggerType,
    hasPullRequest: hasPullRequest, createdAt: now.addingTimeInterval(-createdHoursAgo * hour), state: state,
    url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/\(number)")!,
    newestWorkflowId: newestWorkflowId)
}

private func queue(
  authored: [PullRequest] = [], reviewRequests: [PullRequest] = [], tickets: [JiraTicket] = [], pipelines: [Pipeline] = [],
  dismissedPipelines: Set<PipelineDismissal> = [], dismissedPullRequests: Set<PullRequestDismissal> = [],
  merged: [MergedPullRequest] = []
) -> [QueueSection] {
  buildQueue(
    QueueInput(
      viewerLogin: "me", authoredPullRequests: authored, reviewRequests: reviewRequests, jiraTickets: tickets,
      pipelines: pipelines, dismissedPipelines: dismissedPipelines, dismissedPullRequests: dismissedPullRequests,
      mergedPullRequests: merged),
    now: now)
}

private func items(_ sections: [QueueSection], _ kind: SectionKind) -> [QueueItem] {
  sections.first { $0.kind == kind }?.items ?? []
}

struct QueueBuilderTests {
  @Test func emptyInputHasNoSections() {
    #expect(queue().isEmpty)
  }

  @Test func failingPullRequestGoesToFix() {
    let sections = queue(authored: [
      pullRequest(number: 2184, title: "Migrate field map", updatedHoursAgo: 25.0 / 60, checkState: .failure, failedCheckCount: 3)
    ])
    let fixItems = items(sections, .fix)
    #expect(fixItems.count == 1)
    #expect(fixItems.first?.badge == Badge(text: "3 checks failed", variant: .failing))
    #expect(fixItems.first?.meta == "app-web · 25m")
    #expect(fixItems.first?.reference == "#2184")
    #expect(fixItems.first?.symbol == .failing)
  }

  @Test func singleFailedCheckUsesSingular() {
    let sections = queue(authored: [pullRequest(checkState: .error, failedCheckCount: 1)])
    #expect(items(sections, .fix).first?.badge?.text == "1 check failed")
  }

  @Test func failingApprovedPullRequestGoesToFixOnly() {
    let sections = queue(authored: [pullRequest(reviewDecision: .approved, checkState: .failure, failedCheckCount: 2)])
    #expect(items(sections, .fix).count == 1)
    #expect(items(sections, .merge).isEmpty)
  }

  @Test func draftPullRequestGoesToWaitingEvenWhenFailing() {
    let sections = queue(authored: [pullRequest(isDraft: true, checkState: .failure, failedCheckCount: 1)])
    #expect(sections.map(\.kind) == [.waiting])
    #expect(items(sections, .waiting).first?.badge == Badge(text: "Draft", variant: .neutral))
    #expect(items(sections, .waiting).first?.symbol == .draftPullRequest)
  }

  @Test func openPullRequestWithoutApprovalGoesToWaiting() {
    let sections = queue(authored: [
      pullRequest(repository: "app-api", number: 45, updatedHoursAgo: 3, reviewDecision: .reviewRequired, checkState: nil)
    ])
    let waitingItems = items(sections, .waiting)
    #expect(sections.map(\.kind) == [.waiting])
    #expect(waitingItems.first?.meta == "app-api · 3h")
    #expect(waitingItems.first?.reference == "#45")
    #expect(waitingItems.first?.symbol == .pullRequest)
    #expect(waitingItems.first?.badge == nil)
  }

  @Test func changesRequestedPullRequestShowsBadgeInWaiting() {
    let sections = queue(authored: [pullRequest(reviewDecision: .changesRequested)])
    #expect(items(sections, .waiting).first?.badge == Badge(text: "Changes requested", variant: .urgent))
    #expect(items(sections, .waiting).first?.symbol == .pullRequest)
  }

  @Test func approvedGreenPullRequestGoesToMerge() {
    let sections = queue(authored: [pullRequest(repository: "app-api", number: 988, updatedHoursAgo: 48, reviewDecision: .approved)])
    let mergeItems = items(sections, .merge)
    #expect(mergeItems.first?.badge == Badge(text: "Approved", variant: .ready))
    #expect(mergeItems.first?.meta == "app-api · 2d")
    #expect(mergeItems.first?.reference == "#988")
    #expect(mergeItems.first?.symbol == .merge)
  }

  @Test func recentReviewRequestHasNoBadgeAndCarriesDetails() {
    let sections = queue(reviewRequests: [
      pullRequest(repository: "ui-kit", number: 412, title: "Add tooltip", author: "Rui", additions: 12, deletions: 4,
                  requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 23)
    ])
    let reviewItem = items(sections, .review).first
    #expect(reviewItem?.badge == nil)
    #expect(reviewItem?.details == PullRequestDetails(
      title: "Add tooltip", reference: "#412", repository: "ui-kit", additions: 12, deletions: 4))
    #expect(reviewItem?.meta == "ui-kit · Rui · 23h")
    #expect(reviewItem?.reference == "#412")
    #expect(reviewItem?.symbol == .review)
  }

  @Test func oldReviewRequestIsUrgent() {
    let sections = queue(reviewRequests: [
      pullRequest(author: "Ana", requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 25)
    ])
    #expect(items(sections, .review).first?.badge == Badge(text: "Waiting 1d", variant: .urgent))
  }

  @Test func oldTeamReviewRequestHasNoBadge() {
    let sections = queue(reviewRequests: [
      pullRequest(author: "Ana", additions: 3, deletions: 1, requestedTeamSlugs: ["web-core"], reviewRequestedHoursAgo: 50)
    ])
    #expect(items(sections, .review).first?.badge == nil)
  }

  @Test func authoredPullRequestCarriesDetails() {
    let sections = queue(authored: [
      pullRequest(repository: "api-core", number: 88, title: "Cache tokens", additions: 48, deletions: 12)
    ])
    #expect(items(sections, .waiting).first?.details == PullRequestDetails(
      title: "Cache tokens", reference: "#88", repository: "api-core", additions: 48, deletions: 12))
  }

  @Test func diffPhraseUsesPluralForms() {
    let details = PullRequestDetails(title: "Change", reference: "#1", repository: "app-web", additions: 48, deletions: 12)
    #expect(details.diffAccessibilityPhrase == "48 lines added, 12 lines removed")
  }

  @Test func diffPhraseUsesSingularForms() {
    let details = PullRequestDetails(title: "Change", reference: "#1", repository: "app-web", additions: 1, deletions: 1)
    #expect(details.diffAccessibilityPhrase == "1 line added, 1 line removed")
  }

  @Test func diffPhraseUsesPluralFormsForZero() {
    let details = PullRequestDetails(title: "Change", reference: "#1", repository: "app-web", additions: 0, deletions: 0)
    #expect(details.diffAccessibilityPhrase == "0 lines added, 0 lines removed")
  }

  @Test func diffTextUsesSignsAndLocaleGrouping() {
    let details = PullRequestDetails(
      title: "Change", reference: "#1", repository: "app-web", additions: 1204, deletions: 318)
    #expect(details.additionsText(locale: Locale(identifier: "en_US")) == "+1,204")
    #expect(details.deletionsText(locale: Locale(identifier: "en_US")) == "\u{2212}318")
    #expect(details.additionsText(locale: Locale(identifier: "de_DE")) == "+1.204")
  }

  @Test func botTicketAndPipelineRowsHaveNoDetails() {
    let sections = queue(
      reviewRequests: [
        pullRequest(author: "renovate", authorIsBot: true, requestedTeamSlugs: ["obs"], reviewRequestedHoursAgo: 2)
      ],
      tickets: [ticket(key: "PROJ-1")],
      pipelines: [pipeline()])
    let allItems = sections.flatMap(\.items)
    #expect(allItems.count == 3)
    #expect(allItems.allSatisfy { $0.details == nil })
  }

  @Test func botReviewRequestsCollapseIntoOneRow() throws {
    let sections = queue(reviewRequests: [
      pullRequest(repository: "api-notifier", number: 7, author: "dependabot", authorIsBot: true,
                  requestedTeamSlugs: ["obs"], reviewRequestedHoursAgo: 72),
      pullRequest(repository: "api-config", number: 8, author: "dependabot", authorIsBot: true,
                  requestedTeamSlugs: ["obs"], reviewRequestedHoursAgo: 5),
      pullRequest(repository: "api-config", number: 9, author: "dependabot", authorIsBot: true,
                  requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 30),
      pullRequest(number: 10, author: "Ana", requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 1),
    ])
    let reviewItems = items(sections, .review)
    #expect(reviewItems.count == 2)
    let botItem = try #require(reviewItems.first { $0.id == "bots:dependabot" })
    #expect(botItem.title == "3 Dependabot PRs")
    #expect(botItem.tag == "bot")
    #expect(botItem.metaTail == "2 repos · 3d")
    #expect(botItem.reference == nil)
    #expect(botItem.badge == nil)
    #expect(botItem.url == URL(string: "https://github.com/pulls?q=is%3Apr%20is%3Aopen%20review-requested%3A%40me%20author%3Aapp%2Fdependabot"))
    #expect(botItem.symbol == .review)
    #expect(botItem.children.map(\.id) == ["pr:api-notifier#7", "pr:api-config#9", "pr:api-config#8"])
    #expect(botItem.children.first?.tag == "api-notifier")
    #expect(botItem.children.first?.reference == "#7")
    #expect(botItem.children.first?.metaTail == "dependabot · 3d")
  }

  @Test func singleBotReviewRequestUsesSingular() {
    let sections = queue(reviewRequests: [
      pullRequest(author: "renovate", authorIsBot: true, requestedTeamSlugs: ["obs"], reviewRequestedHoursAgo: 2)
    ])
    #expect(items(sections, .review).first?.title == "1 Renovate PR")
    #expect(items(sections, .review).first?.metaTail == "1 repo · 2h")
  }

  @Test func teamReviewRequestShowsTeamInMeta() {
    let sections = queue(reviewRequests: [
      pullRequest(number: 2179, author: "Ana", requestedTeamSlugs: ["web-core"], reviewRequestedHoursAgo: 30)
    ])
    #expect(items(sections, .review).first?.meta == "app-web · Ana · 1d · team web-core")
  }

  // The row truncates the team first and then the repo, so the author and age stay visible.
  @Test func pullRequestRowsSplitRepoAndTeamFromRestOfMeta() {
    let sections = queue(
      authored: [pullRequest(repository: "app-api", number: 45, updatedHoursAgo: 3, reviewDecision: .reviewRequired, checkState: nil)],
      reviewRequests: [pullRequest(number: 2179, author: "Ana", requestedTeamSlugs: ["web-core"], reviewRequestedHoursAgo: 30)])
    let authoredItem = items(sections, .waiting).first
    let reviewItem = items(sections, .review).first
    #expect(authoredItem?.tag == "app-api")
    #expect(authoredItem?.metaTail == "3h")
    #expect(authoredItem?.metaTeam == nil)
    #expect(reviewItem?.tag == "app-web")
    #expect(reviewItem?.metaTail == "Ana · 1d")
    #expect(reviewItem?.metaTeam == "team web-core")
  }

  @Test func nonPullRequestRowsKeepMetaWhole() {
    let sections = queue(reviewRequests: [
      pullRequest(author: "renovate", authorIsBot: true, requestedTeamSlugs: ["obs"], reviewRequestedHoursAgo: 2)
    ])
    #expect(items(sections, .review).first?.tag == "bot")
    #expect(items(sections, .review).first?.metaTail == "1 repo · 2h")
  }

  @Test func teamRequestApprovedByViewerHasNoReviewRow() {
    let sections = queue(reviewRequests: [
      pullRequest(author: "Ana", requestedTeamSlugs: ["web-core"], reviewRequestedHoursAgo: 30, viewerLatestReviewState: .approved)
    ])
    #expect(items(sections, .review).isEmpty)
  }

  @Test func teamRequestWithoutViewerReviewHasReviewRow() {
    let sections = queue(reviewRequests: [
      pullRequest(author: "Ana", requestedTeamSlugs: ["web-core"], reviewRequestedHoursAgo: 30)
    ])
    #expect(items(sections, .review).count == 1)
  }

  @Test func teamRequestWithViewerChangesRequestedHasReviewRow() {
    let sections = queue(reviewRequests: [
      pullRequest(author: "Ana", requestedTeamSlugs: ["web-core"], reviewRequestedHoursAgo: 30,
                  viewerLatestReviewState: .changesRequested)
    ])
    #expect(items(sections, .review).count == 1)
  }

  @Test func directRequestAfterViewerApprovalHasReviewRow() {
    let sections = queue(reviewRequests: [
      pullRequest(author: "Ana", requestedReviewerLogins: ["me"], requestedTeamSlugs: ["web-core"],
                  reviewRequestedHoursAgo: 30, viewerLatestReviewState: .approved)
    ])
    #expect(items(sections, .review).count == 1)
  }

  @Test func ticketWithoutPullRequestShowsNoPR() {
    let sections = queue(tickets: [ticket(key: "PROJ-1432", updatedHoursAgo: 72, issueTypeName: "Bug")])
    let tidyItem = items(sections, .tidy).first
    #expect(tidyItem?.badge == Badge(text: "No PR", variant: .neutral))
    #expect(tidyItem?.tag == "PROJ-1432")
    #expect(tidyItem?.metaTail == "In Progress · 3d")
    #expect(tidyItem?.symbol == .bug)
  }

  @Test func ticketWithUnreviewedPullRequestShowsNoReviewer() {
    let sections = queue(
      authored: [pullRequest(headBranch: "proj-1440-export")],
      tickets: [ticket(key: "PROJ-1440", statusName: "In Review", issueTypeName: "Story")])
    let tidyItem = items(sections, .tidy).first
    #expect(tidyItem?.badge == Badge(text: "No reviewer", variant: .neutral))
    #expect(tidyItem?.symbol == .story)
  }

  @Test(arguments: [
    ("Bug", RowSymbol.bug), ("Story", .story), ("Improvement", .improvement), ("Epic", .epic), ("Task", .task),
    ("Sub-task", .subtask), ("Subtask", .subtask), ("bug", .bug), ("Spike", .ticket), ("", .ticket),
  ])
  func jiraIssueTypeMapsToRowSymbol(issueTypeName: String, expectedSymbol: RowSymbol) {
    #expect(RowSymbol(jiraIssueTypeName: issueTypeName) == expectedSymbol)
  }

  @Test func ticketWithoutIssueTypeShowsTicketSymbol() {
    let tidyItem = items(queue(tickets: [ticket(key: "PROJ-1432")]), .tidy).first
    #expect(tidyItem?.symbol == .ticket)
  }

  @Test func ticketWithMergedPullRequestIsHidden() {
    let mergedByBranch = MergedPullRequest(title: "fix(timeline): handle empty heatmap", headBranch: "p40-65563-heatmap")
    #expect(items(queue(tickets: [ticket(key: "P40-65563")], merged: [mergedByBranch]), .tidy).isEmpty)
    let mergedByTitle = MergedPullRequest(title: "P40-65563 handle empty heatmap", headBranch: "fix/heatmap")
    #expect(items(queue(tickets: [ticket(key: "P40-65563")], merged: [mergedByTitle]), .tidy).isEmpty)
  }

  @Test func mergedPullRequestForAnotherTicketKeepsNoPR() {
    let otherMerged = MergedPullRequest(title: "Other work", headBranch: "p40-11111-other")
    let tidyItem = items(queue(tickets: [ticket(key: "P40-65563")], merged: [otherMerged]), .tidy).first
    #expect(tidyItem?.badge == Badge(text: "No PR", variant: .neutral))
  }

  @Test func ticketWithOnlyDraftPullRequestIsHidden() {
    let sections = queue(
      authored: [pullRequest(isDraft: true, headBranch: "proj-1440-export")],
      tickets: [ticket(key: "PROJ-1440")])
    #expect(items(sections, .tidy).isEmpty)
  }

  @Test func ticketWithUnreviewedDraftAndNonDraftShowsNoReviewer() {
    let sections = queue(
      authored: [
        pullRequest(number: 1, isDraft: true, headBranch: "proj-1440-export"),
        pullRequest(number: 2, headBranch: "proj-1440-import"),
      ],
      tickets: [ticket(key: "PROJ-1440")])
    #expect(items(sections, .tidy).first?.badge == Badge(text: "No reviewer", variant: .neutral))
  }

  @Test func reviewedDraftDoesNotHideUnreviewedNonDraft() {
    let sections = queue(
      authored: [
        pullRequest(number: 1, isDraft: true, headBranch: "proj-1440-export", reviewCount: 1),
        pullRequest(number: 2, headBranch: "proj-1440-import"),
      ],
      tickets: [ticket(key: "PROJ-1440")])
    #expect(items(sections, .tidy).first?.badge == Badge(text: "No reviewer", variant: .neutral))
  }

  @Test func ticketWithReviewedPullRequestIsHidden() {
    let sections = queue(
      authored: [pullRequest(title: "PROJ-1440 export", reviewCount: 1)],
      tickets: [ticket(key: "PROJ-1440")])
    #expect(items(sections, .tidy).isEmpty)
  }

  @Test func sectionsFollowUrgencyOrderAndItemsOldestFirst() {
    let sections = queue(
      authored: [
        pullRequest(number: 1, reviewDecision: .approved),
        pullRequest(number: 2, updatedHoursAgo: 1, checkState: .failure, failedCheckCount: 1),
        pullRequest(number: 3, updatedHoursAgo: 5, checkState: .failure, failedCheckCount: 1),
        pullRequest(number: 5),
      ],
      reviewRequests: [pullRequest(number: 4, author: "Ana", requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 2)],
      tickets: [ticket(key: "PROJ-9")])
    #expect(sections.map(\.kind) == [.fix, .review, .merge, .tidy, .waiting])
    #expect(items(sections, .fix).map(\.id) == ["pr:app-web#3", "pr:app-web#2"])
  }
}

struct RepoGroupTests {
  private func waitingPullRequest(
    _ number: Int, owner: String = "acme", repository: String = "app-web", hoursAgo: Double, head: String = "",
    base: String? = nil, title: String = "Some change", isDraft: Bool = false, reviewDecision: ReviewDecision? = nil,
    isCrossRepository: Bool? = nil
  ) -> PullRequest {
    pullRequest(
      owner: owner, repository: repository, number: number, title: title, isDraft: isDraft, updatedHoursAgo: hoursAgo,
      headBranch: head.isEmpty ? "branch-\(number)" : head, reviewDecision: reviewDecision, baseBranch: base,
      isCrossRepository: isCrossRepository)
  }

  private func repoGroup(_ sections: [QueueSection], _ id: String = "repo:acme/app-web") -> QueueItem? {
    items(sections, .waiting).first { $0.id == id }
  }

  @Test func threeIndependentPullRequestsBecomeOneGroup() throws {
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 1), waitingPullRequest(2, hoursAgo: 50), waitingPullRequest(3, hoursAgo: 3),
      waitingPullRequest(9, repository: "app-api", hoursAgo: 2),
    ])
    #expect(items(sections, .waiting).map(\.id) == ["repo:acme/app-web", "pr:app-api#9"])
    let groupItem = try #require(repoGroup(sections))
    #expect(groupItem.title == "app-web")
    #expect(groupItem.tag == nil)
    #expect(groupItem.metaTail == "3 PRs · 2d")
    #expect(groupItem.symbol == .pullRequest)
    #expect(groupItem.badge == nil)
    #expect(groupItem.sortDate == now.addingTimeInterval(-50 * hour))
    #expect(groupItem.children.map(\.id) == ["pr:app-web#2", "pr:app-web#3", "pr:app-web#1"])
    #expect(groupItem.url == URL(
      string: "https://github.com/pulls?q=is%3Apr%20is%3Aopen%20author%3A%40me%20repo%3Aacme%2Fapp-web"))
  }

  @Test func twoPullRequestsStayPlainRows() {
    let sections = queue(authored: [waitingPullRequest(1, hoursAgo: 1), waitingPullRequest(2, hoursAgo: 2)])
    #expect(items(sections, .waiting).map(\.id) == ["pr:app-web#2", "pr:app-web#1"])
  }

  @Test func stackOfThreeAndOneIndependentPullRequestStayPlainRows() {
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 4, head: "one", base: "main"),
      waitingPullRequest(2, hoursAgo: 3, head: "two", base: "one"),
      waitingPullRequest(3, hoursAgo: 2, head: "three", base: "two"),
      waitingPullRequest(4, hoursAgo: 1, base: "main"),
    ])
    #expect(items(sections, .waiting).allSatisfy { $0.children.isEmpty })
    #expect(items(sections, .waiting).count == 4)
  }

  @Test func stackOfTwoAndTwoIndependentPullRequestsBecomeOneGroup() throws {
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 5, head: "one", base: "main"),
      waitingPullRequest(2, hoursAgo: 1, head: "two", base: "one"),
      waitingPullRequest(3, hoursAgo: 4, base: "main"),
      waitingPullRequest(4, hoursAgo: 2, base: "main"),
    ])
    let groupItem = try #require(repoGroup(sections))
    #expect(items(sections, .waiting).count == 1)
    #expect(groupItem.metaTail == "4 PRs · 5h")
  }

  @Test func stackMembersSitTogetherBottomFirst() throws {
    // The top of the stack is the oldest PR, but the bottom comes first, and the stack sorts by its oldest PR.
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 2, head: "bottom", base: "main"),
      waitingPullRequest(2, hoursAgo: 9, head: "top", base: "middle"),
      waitingPullRequest(3, hoursAgo: 1, head: "middle", base: "bottom"),
      waitingPullRequest(4, hoursAgo: 5, base: "main"),
      waitingPullRequest(5, hoursAgo: 12, base: "main"),
    ])
    let groupItem = try #require(repoGroup(sections))
    #expect(groupItem.children.map(\.id) == ["pr:app-web#5", "pr:app-web#1", "pr:app-web#3", "pr:app-web#2", "pr:app-web#4"])
  }

  @Test func stackWithMemberInFixCountsAsOneUnitAndLeavesTheFixMemberOut() throws {
    let failing = pullRequest(
      number: 2, updatedHoursAgo: 3, headBranch: "two", checkState: .failure, failedCheckCount: 1, baseBranch: "one")
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 4, head: "one", base: "main"), failing,
      waitingPullRequest(3, hoursAgo: 2, head: "three", base: "two"),
      waitingPullRequest(4, hoursAgo: 1, base: "main"),
    ])
    #expect(items(sections, .fix).map(\.id) == ["pr:app-web#2"])
    #expect(items(sections, .waiting).map(\.id) == ["pr:app-web#1", "pr:app-web#3", "pr:app-web#4"])

    let groupedSections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 4, head: "one", base: "main"), failing,
      waitingPullRequest(3, hoursAgo: 2, head: "three", base: "two"),
      waitingPullRequest(4, hoursAgo: 1, base: "main"), waitingPullRequest(5, hoursAgo: 6, base: "main"),
    ])
    let groupItem = try #require(repoGroup(groupedSections))
    #expect(groupItem.children.map(\.id) == ["pr:app-web#5", "pr:app-web#1", "pr:app-web#3", "pr:app-web#4"])
  }

  @Test func pullRequestsThatShareAHeadBranchJoinOneStack() throws {
    // One branch opened against main and against release, with a third PR on top of it, is one unit.
    let stack = [
      waitingPullRequest(1, hoursAgo: 4, head: "feature", base: "main"),
      waitingPullRequest(2, hoursAgo: 3, head: "feature", base: "release"),
      waitingPullRequest(3, hoursAgo: 2, head: "next", base: "feature"),
    ]
    let sections = queue(authored: stack + [waitingPullRequest(4, hoursAgo: 1, base: "main")])
    #expect(items(sections, .waiting).allSatisfy { $0.children.isEmpty })

    let groupedSections = queue(
      authored: stack + [waitingPullRequest(4, hoursAgo: 1, base: "main"), waitingPullRequest(5, hoursAgo: 5, base: "main")])
    let groupItem = try #require(repoGroup(groupedSections))
    #expect(groupItem.children.map(\.id) == ["pr:app-web#5", "pr:app-web#1", "pr:app-web#2", "pr:app-web#3", "pr:app-web#4"])
  }

  @Test func everyParentComesBeforeItsChild() throws {
    // feature is open twice: against main, and on top of base. The PR on feature must follow both, also when it is older.
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 2, head: "feature", base: "main"),
      waitingPullRequest(2, hoursAgo: 3, head: "base", base: "main"),
      waitingPullRequest(3, hoursAgo: 1, head: "feature", base: "base"),
      waitingPullRequest(4, hoursAgo: 9, head: "top", base: "feature"),
      waitingPullRequest(5, hoursAgo: 1, base: "main"), waitingPullRequest(6, hoursAgo: 1.5, base: "main"),
    ])
    let groupItem = try #require(repoGroup(sections))
    #expect(groupItem.children.map(\.id) == [
      "pr:app-web#2", "pr:app-web#1", "pr:app-web#3", "pr:app-web#4", "pr:app-web#6", "pr:app-web#5",
    ])
  }

  @Test(.timeLimit(.minutes(1)))
  func layersOfSharedHeadBranchesStayFast() {
    // Each layer opens one branch three times, on top of the layer below. A walk over every path would take 3^16 steps.
    let layerCount = 16
    let pullRequests = (0..<layerCount).flatMap { layer in
      (0..<3).map { copy in
        waitingPullRequest(
          layer * 3 + copy + 1, hoursAgo: Double(layer + 1), head: "layer-\(layer)", base: layer == 0 ? "main" : "layer-\(layer - 1)")
      }
    }
    let sections = queue(authored: pullRequests)
    #expect(items(sections, .waiting).count == layerCount * 3)
    #expect(items(sections, .waiting).allSatisfy { $0.children.isEmpty })
  }

  @Test func crossRepositoryPullRequestIsNeverTheBaseOfAStack() throws {
    // A fork PR from the fork's main branch must not pull every PR based on main into one stack.
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 4, head: "main", base: "main", isCrossRepository: true),
      waitingPullRequest(2, hoursAgo: 3, base: "main", isCrossRepository: false),
      waitingPullRequest(3, hoursAgo: 2, base: "main", isCrossRepository: false),
    ])
    let groupItem = try #require(repoGroup(sections))
    #expect(groupItem.children.count == 3)
  }

  @Test func badgeCountsPullRequestsWithChangesRequested() throws {
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 1, reviewDecision: .changesRequested),
      waitingPullRequest(2, hoursAgo: 2, reviewDecision: .changesRequested),
      waitingPullRequest(3, hoursAgo: 3, isDraft: true, reviewDecision: .changesRequested),
      waitingPullRequest(4, hoursAgo: 4),
    ])
    let groupItem = try #require(repoGroup(sections))
    #expect(groupItem.badge == Badge(text: "2 changes requested", variant: .urgent))
  }

  @Test func childrenKeepTheirOwnSymbolsAndBadges() throws {
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 1, reviewDecision: .changesRequested),
      waitingPullRequest(2, hoursAgo: 2, isDraft: true), waitingPullRequest(3, hoursAgo: 3),
    ])
    let groupItem = try #require(repoGroup(sections))
    #expect(groupItem.children.map(\.symbol) == [.pullRequest, .draftPullRequest, .pullRequest])
    #expect(groupItem.children.map(\.badge?.text) == [nil, "Draft", "Changes requested"])
    #expect(groupItem.children.allSatisfy { $0.tag == "app-web" && $0.strip != nil })
  }

  @Test func childrenWithTheSameAgeKeepPullRequestNumberOrder() throws {
    let sections = queue(authored: [5, 2, 9, 1].map { waitingPullRequest($0, hoursAgo: 3) })
    #expect(try #require(repoGroup(sections)).children.map(\.id) == ["pr:app-web#1", "pr:app-web#2", "pr:app-web#5", "pr:app-web#9"])
  }

  @Test func waitingRowsWithTheSameAgeKeepTheirInputOrder() {
    let sections = queue(authored: [
      waitingPullRequest(1, repository: "app-api", hoursAgo: 2), waitingPullRequest(2, repository: "app-web", hoursAgo: 2),
      waitingPullRequest(3, repository: "app-ios", hoursAgo: 2), waitingPullRequest(4, repository: "app-api", hoursAgo: 2),
    ])
    #expect(items(sections, .waiting).map(\.id) == ["pr:app-api#1", "pr:app-web#2", "pr:app-ios#3", "pr:app-api#4"])
  }

  @Test func groupSortsWhereItsOldestPullRequestWould() {
    let sections = queue(authored: [
      waitingPullRequest(1, hoursAgo: 1), waitingPullRequest(2, hoursAgo: 2), waitingPullRequest(3, hoursAgo: 10),
      waitingPullRequest(7, repository: "app-api", hoursAgo: 12), waitingPullRequest(8, repository: "app-api", hoursAgo: 5),
    ])
    #expect(items(sections, .waiting).map(\.id) == ["pr:app-api#7", "repo:acme/app-web", "pr:app-api#8"])
  }

  @Test func sameRepoNameInTwoOrganizationsMakesTwoGroups() throws {
    let sections = queue(authored: (1...3).map { waitingPullRequest($0, hoursAgo: Double($0)) }
      + (4...6).map { waitingPullRequest($0, owner: "other-org", hoursAgo: Double($0)) })
    #expect(Set(items(sections, .waiting).map(\.id)) == ["repo:acme/app-web", "repo:other-org/app-web"])
    #expect(try #require(repoGroup(sections, "repo:other-org/app-web")).children.map(\.id)
      == ["pr:app-web#6", "pr:app-web#5", "pr:app-web#4"])

    let splitSections = queue(authored: (1...2).map { waitingPullRequest($0, hoursAgo: Double($0)) }
      + (4...5).map { waitingPullRequest($0, owner: "other-org", hoursAgo: Double($0)) })
    #expect(items(splitSections, .waiting).allSatisfy { $0.children.isEmpty })
  }

  @Test func titlePrefixPullRequestsSitInTheRepoGroupWithNoNestedGroup() throws {
    let sections = queue(authored: (1...3).map {
      waitingPullRequest($0, hoursAgo: Double($0), title: "chore(feature-flags): remove flag \($0)")
    } + [waitingPullRequest(9, hoursAgo: 4, title: "Fix login")])
    let groupItem = try #require(repoGroup(sections))
    #expect(items(sections, .waiting).count == 1)
    #expect(groupItem.children.count == 4)
    #expect(groupItem.children.allSatisfy { $0.children.isEmpty })
  }

  @Test func pullRequestsWithoutBaseBranchAreIndependent() throws {
    // Caches written before Tower read the base branch have none, so every PR is one unit.
    let sections = queue(authored: (1...3).map { waitingPullRequest($0, hoursAgo: Double($0), head: "same") })
    #expect(try #require(repoGroup(sections)).children.count == 3)
  }

  @Test func otherSectionsDoNotGroupByRepo() {
    let sections = queue(
      authored: (1...3).map { pullRequest(number: $0, checkState: .failure, failedCheckCount: 1) }
        + (4...6).map { pullRequest(number: $0, reviewDecision: .approved) },
      reviewRequests: (7...9).map { pullRequest(number: $0, author: "ana", requestedReviewerLogins: ["me"]) },
      tickets: (1...3).map { ticket(key: "PROJ-\($0)") })
    for kind in [SectionKind.fix, .review, .merge, .tidy] {
      #expect(items(sections, kind).count == 3)
      #expect(items(sections, kind).allSatisfy { $0.children.isEmpty })
    }
  }
}

struct StatusDotTests {
  private func row(badge: Badge?, checks: StatusStrip.Checks?, children: [QueueItem] = []) -> QueueItem {
    QueueItem(
      id: "row", title: "Row", meta: "1h", url: URL(string: "https://example.com")!, symbol: .pullRequest, badge: badge,
      sortDate: now, strip: StatusStrip(checks: checks, threads: nil, approvals: nil), children: children)
  }

  @Test(arguments: [
    (BadgeVariant.failing, StatusDot.failing),
    (.urgent, .urgent),
    (.ready, .ready),
  ])
  func badgeVariantWinsOverChecks(variant: BadgeVariant, expected: StatusDot) {
    #expect(row(badge: Badge(text: "X", variant: variant), checks: .passed).statusDot == expected)
    #expect(row(badge: Badge(text: "X", variant: variant), checks: .failed).statusDot == expected)
  }

  @Test(arguments: [
    (StatusStrip.Checks?.some(.passed), StatusDot.ready),
    (.some(.failed), .failing),
    (.some(.running), .pending),
    (nil, .pending),
  ])
  func neutralOrNoBadgeFallsBackToChecks(checks: StatusStrip.Checks?, expected: StatusDot) {
    #expect(row(badge: nil, checks: checks).statusDot == expected)
    #expect(row(badge: Badge(text: "Draft", variant: .neutral), checks: checks).statusDot == expected)
  }

  @Test func groupTakesWorstChildDot() {
    let children = [row(badge: nil, checks: .passed), row(badge: nil, checks: .failed), row(badge: nil, checks: .running)]
    #expect(row(badge: nil, checks: .passed, children: children).statusDot == .failing)
    let calmChildren = [row(badge: nil, checks: .passed), row(badge: nil, checks: .running)]
    #expect(row(badge: nil, checks: nil, children: calmChildren).statusDot == .pending)
    let passingChildren = [row(badge: nil, checks: .passed), row(badge: nil, checks: .passed)]
    #expect(row(badge: nil, checks: nil, children: passingChildren).statusDot == .ready)
  }

  @Test func draftWithFailedChecksIsFailing() {
    let sections = queue(authored: [pullRequest(isDraft: true, checkState: .failure, failedCheckCount: 1)])
    #expect(items(sections, .waiting).first?.statusDot == .failing)
  }
}

struct PanelTabTests {
  @Test func tabsSplitSectionsAndLeaveOutWatch() {
    let sections = queue(
      authored: [
        pullRequest(number: 1, reviewDecision: .approved), pullRequest(number: 2, checkState: .failure, failedCheckCount: 1),
        pullRequest(number: 3),
      ],
      reviewRequests: [pullRequest(number: 4, author: "Ana", requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 2)],
      tickets: [ticket(key: "PROJ-9")],
      pipelines: [pipeline(state: .running)])
    #expect(Core.sections(sections, in: .needsYou).map(\.kind) == [.fix, .review, .merge, .tidy])
    #expect(Core.sections(sections, in: .waiting).map(\.kind) == [.waiting])
  }

  @Test func tabTitles() {
    #expect(PanelTab.allCases.map(\.title) == ["Needs you", "Waiting"])
  }
}

struct PanelLayoutTests {
  private let allKindsQueue = queue(
    authored: [
      pullRequest(number: 1, reviewDecision: .approved), pullRequest(number: 2, checkState: .failure, failedCheckCount: 1),
      pullRequest(number: 3),
    ],
    reviewRequests: [pullRequest(number: 4, author: "Ana", requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 2)],
    tickets: [ticket(key: "PROJ-9")],
    pipelines: [pipeline(state: .running)])

  @Test func splitShowsTheSectionsOfTheTab() {
    for tab in PanelTab.allCases {
      #expect(
        displayedSections(allKindsQueue, layout: .split, tab: tab).map(\.kind)
          == Core.sections(allKindsQueue, in: tab).map(\.kind))
    }
  }

  @Test func consolidatedShowsEverySectionInUrgencyOrderOnBothTabs() {
    for tab in PanelTab.allCases {
      #expect(
        displayedSections(allKindsQueue, layout: .consolidated, tab: tab).map(\.kind)
          == [.fix, .review, .merge, .tidy, .watch, .waiting])
    }
  }

  @Test func consolidatedWithNoRowsShowsNoSections() {
    #expect(displayedSections([], layout: .consolidated, tab: .needsYou).isEmpty)
  }

  @Test func layoutTitlesAndStoredValues() {
    #expect(PanelLayout.allCases.map(\.title) == ["Split", "Consolidated"])
    #expect(PanelLayout.allCases.map(\.rawValue) == ["split", "consolidated"])
  }
}

private func strip(_ pullRequest: PullRequest) -> StatusStrip? {
  queue(authored: [pullRequest]).flatMap(\.items).first?.strip
}

struct StatusStripTests {
  @Test(arguments: [
    (CheckState.success, StatusStrip.Checks.passed),
    (.failure, .failed),
    (.error, .failed),
    (.pending, .running),
    (.expected, .running),
  ])
  func checksStateMapsFromRollup(checkState: CheckState, expectedChecks: StatusStrip.Checks) {
    #expect(strip(pullRequest(checkState: checkState, failedCheckCount: 1))?.checks == expectedChecks)
  }

  @Test func missingRollupHidesChecks() {
    #expect(strip(pullRequest(checkState: nil))?.checks == nil)
  }

  @Test func noUnresolvedThreadsHidesThreads() {
    #expect(strip(pullRequest(unresolvedThreadCount: 0))?.threads == nil)
  }

  @Test func unresolvedThreadsShowTheirCount() {
    #expect(strip(pullRequest(unresolvedThreadCount: 3))?.threads == StatusStrip.Threads(unresolvedCount: 3, isLowerBound: false))
  }

  @Test func moreThreadsThanFetchedMarksCountAsLowerBound() {
    let threads = strip(pullRequest(unresolvedThreadCount: 2, hasMoreThreadsThanFetched: true))?.threads
    #expect(threads == StatusStrip.Threads(unresolvedCount: 2, isLowerBound: true))
  }

  @Test func moreThreadsThanFetchedWithNoneUnresolvedHidesThreads() {
    #expect(strip(pullRequest(unresolvedThreadCount: 0, hasMoreThreadsThanFetched: true))?.threads == nil)
  }

  @Test func noApprovalsOfOneRequired() {
    let approvals = strip(pullRequest(approvalCount: 0, requiredApprovalCount: 1))?.approvals
    #expect(approvals == StatusStrip.Approvals(given: 0, required: 1))
  }

  @Test func oneApprovalOfTwoRequired() {
    let approvals = strip(pullRequest(approvalCount: 1, requiredApprovalCount: 2))?.approvals
    #expect(approvals == StatusStrip.Approvals(given: 1, required: 2))
  }

  @Test func approvalsOverRequiredAreCapped() {
    let approvals = strip(pullRequest(approvalCount: 3, requiredApprovalCount: 2))?.approvals
    #expect(approvals == StatusStrip.Approvals(given: 2, required: 2))
  }

  @Test func noRequiredApprovalsShowsApprovalsGiven() {
    let approvals = strip(pullRequest(approvalCount: 2, requiredApprovalCount: 0))?.approvals
    #expect(approvals == StatusStrip.Approvals(given: 2, required: 0))
  }

  @Test func noRequiredApprovalsDrawsOneSlot() {
    let approvals = strip(pullRequest(approvalCount: 3, requiredApprovalCount: 0))?.approvals
    #expect(approvals?.slotCount == 1)
  }

  @Test func requiredApprovalsDrawOneSlotEach() {
    #expect(strip(pullRequest(approvalCount: 1, requiredApprovalCount: 2))?.approvals?.slotCount == 2)
    #expect(strip(pullRequest(approvalCount: 3, requiredApprovalCount: 2))?.approvals?.slotCount == 2)
  }

  @Test func stripWithNoPartsIsEmpty() {
    #expect(StatusStrip(checks: nil, threads: nil, approvals: nil).isEmpty)
    #expect(!StatusStrip(checks: .passed, threads: nil, approvals: nil).isEmpty)
    #expect(!StatusStrip(checks: nil, threads: StatusStrip.Threads(unresolvedCount: 1, isLowerBound: false), approvals: nil).isEmpty)
    #expect(!StatusStrip(checks: nil, threads: nil, approvals: StatusStrip.Approvals(given: 1, required: 0)).isEmpty)
  }

  @Test func noRequiredApprovalsAndNoneGivenHidesApprovals() {
    #expect(strip(pullRequest(approvalCount: 0, requiredApprovalCount: 0))?.approvals == nil)
  }

  @Test func draftHidesApprovalsButKeepsChecksAndThreads() {
    let draftStrip = strip(
      pullRequest(isDraft: true, checkState: .pending, unresolvedThreadCount: 1, approvalCount: 1, requiredApprovalCount: 2))
    #expect(draftStrip == StatusStrip(checks: .running, threads: StatusStrip.Threads(unresolvedCount: 1, isLowerBound: false), approvals: nil))
  }

  @Test func onlyAuthoredPullRequestsHaveAStrip() {
    let sections = queue(
      reviewRequests: [
        pullRequest(number: 2, author: "Ana", requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 2, unresolvedThreadCount: 1),
        pullRequest(number: 3, author: "renovate", authorIsBot: true, requestedTeamSlugs: ["obs"], reviewRequestedHoursAgo: 2),
      ],
      tickets: [ticket(key: "PROJ-9")],
      pipelines: [pipeline(state: .failed), pipeline(triggerType: "webhook", state: .running)])
    let allItems = sections.flatMap(\.items)
    #expect(allItems.count == 5)
    #expect(allItems.allSatisfy { $0.strip == nil })
  }

  @Test func phraseForFullStrip() {
    let fullStrip = strip(
      pullRequest(checkState: .pending, unresolvedThreadCount: 3, approvalCount: 1, requiredApprovalCount: 2))
    #expect(fullStrip?.accessibilityPhrase == "checks running, 3 unresolved threads, 1 of 2 approvals")
  }

  @Test func phraseForPartialStrip() {
    #expect(strip(pullRequest(isDraft: true, checkState: .success))?.accessibilityPhrase == "checks passed")
  }

  @Test func phraseUsesSingularForms() {
    let singularStrip = strip(pullRequest(checkState: nil, unresolvedThreadCount: 1, approvalCount: 0, requiredApprovalCount: 1))
    #expect(singularStrip?.accessibilityPhrase == "1 unresolved thread, 0 of 1 approval")
  }

  @Test func phraseSaysAtLeastWhenThreadCountIsLowerBound() {
    let overflowStrip = strip(
      pullRequest(isDraft: true, checkState: nil, unresolvedThreadCount: 2, hasMoreThreadsThanFetched: true))
    #expect(overflowStrip?.accessibilityPhrase == "at least 2 unresolved threads")
  }

  @Test func phraseLeavesOutFailedChecks() {
    let failingStrip = strip(
      pullRequest(checkState: .failure, failedCheckCount: 2, unresolvedThreadCount: 2, approvalCount: 0, requiredApprovalCount: 1))
    #expect(failingStrip?.accessibilityPhrase == "2 unresolved threads, 0 of 1 approval")
  }

  // A failing draft sits in Waiting with a Draft badge, so only the strip can say the checks failed.
  @Test func phraseSaysFailedChecksOnDraft() {
    let failingDraftStrip = strip(
      pullRequest(isDraft: true, checkState: .failure, failedCheckCount: 2, unresolvedThreadCount: 3))
    #expect(failingDraftStrip?.accessibilityPhrase == "checks failed, 3 unresolved threads")
  }

  @Test func phraseWithNoRequiredApprovalsCountsApprovalsGiven() {
    #expect(strip(pullRequest(checkState: nil, approvalCount: 1, requiredApprovalCount: 0))?.accessibilityPhrase == "1 approval")
    #expect(strip(pullRequest(checkState: nil, approvalCount: 2, requiredApprovalCount: 0))?.accessibilityPhrase == "2 approvals")
  }
}

struct PipelineQueueTests {
  @Test func failedPipelineGoesToFix() {
    let sections = queue(pipelines: [pipeline(number: 1842, ref: "v2.14.0", refIsTag: true, triggerType: "webhook", createdHoursAgo: 0.1)])
    #expect(items(sections, .fix) == [
      QueueItem(
        id: "pipeline:gh/acme/app-web:v2.14.0:webhook", title: "v2.14.0", tag: "app-web", meta: "#1842 · tag · 6m",
        url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/1842")!, symbol: .failing,
        badge: Badge(text: "Pipeline failed", variant: .failing), sortDate: now.addingTimeInterval(-0.1 * hour),
        dismissal: .pipeline(PipelineDismissal(pipelineId: "pipeline-1842", newestWorkflowId: "workflow-1")))
    ])
  }

  @Test func branchPipelineMetaSaysBranch() {
    #expect(items(queue(pipelines: [pipeline(number: 6000, createdHoursAgo: 2)]), .fix).first?.metaTail == "#6000 · branch · 2h")
  }

  @Test func succeededPipelineGivesNoRow() {
    #expect(queue(pipelines: [pipeline(state: .succeeded)]).isEmpty)
  }

  @Test func runningPipelineGoesToWatch() {
    let sections = queue(pipelines: [pipeline(number: 1842, ref: "v2.14.0", refIsTag: true, createdHoursAgo: 0.1, state: .running)])
    #expect(sections.map(\.kind) == [.watch])
    #expect(items(sections, .watch) == [
      QueueItem(
        id: "pipeline:gh/acme/app-web:v2.14.0:api", title: "v2.14.0", tag: "app-web", meta: "#1842 · tag · 6m",
        url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/1842")!, symbol: .running,
        badge: Badge(text: "Running", variant: .neutral), sortDate: now.addingTimeInterval(-0.1 * hour))
    ])
  }

  @Test func onHoldPipelineGoesToWatchAsUrgent() {
    let watchItems = items(queue(pipelines: [pipeline(state: .onHold)]), .watch)
    #expect(watchItems.map(\.symbol) == [.approvalHold])
    #expect(watchItems.map(\.badge) == [Badge(text: "Needs approval", variant: .urgent)])
  }

  @Test func watchComesAfterTidy() {
    let sections = queue(tickets: [ticket(key: "PROJ-9")], pipelines: [pipeline(state: .running)])
    #expect(sections.map(\.kind) == [.tidy, .watch])
  }

  @Test func watchIsHiddenWhenNoPipelineIsRunningOrOnHold() {
    let sections = queue(pipelines: [pipeline(state: .failed), pipeline(triggerType: "webhook", state: .succeeded)])
    #expect(sections.map(\.kind) == [.fix])
  }

  @Test func newerSucceededPipelineClearsOlderFailure() {
    let sections = queue(pipelines: [
      pipeline(number: 2, createdHoursAgo: 1, state: .succeeded),
      pipeline(number: 1, createdHoursAgo: 2, state: .failed),
    ])
    #expect(sections.isEmpty)
  }

  @Test func newestFailurePerKeyWins() {
    let sections = queue(pipelines: [
      pipeline(number: 1, createdHoursAgo: 3),
      pipeline(number: 2, createdHoursAgo: 1),
    ])
    #expect(items(sections, .fix).map(\.metaTail) == ["#2 · branch · 1h"])
  }

  @Test func mergeOnMainDoesNotHideManualReleaseOnMain() {
    let sections = queue(pipelines: [
      pipeline(number: 2, triggerType: "webhook", createdHoursAgo: 1, state: .succeeded),
      pipeline(number: 1, triggerType: "api", createdHoursAgo: 2, state: .failed),
    ])
    #expect(items(sections, .fix).map(\.id) == ["pipeline:gh/acme/app-web:main:api"])
  }

  @Test func pipelineOlderThanOneDayIsDropped() {
    #expect(queue(pipelines: [pipeline(createdHoursAgo: 25)]).isEmpty)
  }

  @Test func pipelineWithPullRequestIsDropped() {
    #expect(queue(pipelines: [pipeline(ref: "feature/x", triggerType: "webhook", hasPullRequest: true)]).isEmpty)
  }

  @Test func newerPullRequestPipelineHidesOlderFailureOnSameKey() {
    let sections = queue(pipelines: [
      pipeline(number: 2, ref: "feature/x", triggerType: "webhook", hasPullRequest: true, createdHoursAgo: 1, state: .succeeded),
      pipeline(number: 1, ref: "feature/x", triggerType: "webhook", createdHoursAgo: 2, state: .failed),
    ])
    #expect(sections.isEmpty)
  }

  @Test func failedPipelineCountsInMenuBar() {
    let sections = queue(
      reviewRequests: [pullRequest(requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 30)],
      pipelines: [pipeline()])
    #expect(MenuBarState(sections: sections) == .failing(count: 1))
  }

  @Test func approvalHoldAddsToMenuBarUrgentCount() {
    let urgentReview = pullRequest(requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 30)
    #expect(MenuBarState(sections: queue(reviewRequests: [urgentReview])) == .urgent(count: 1))
    #expect(MenuBarState(sections: queue(reviewRequests: [urgentReview], pipelines: [pipeline(state: .onHold)])) == .urgent(count: 2))
  }

  @Test func dismissedFailedPipelineIsHidden() {
    let failed = pipeline()
    let sections = queue(pipelines: [failed], dismissedPipelines: [failed.dismissal])
    #expect(items(sections, .fix).isEmpty)
  }

  @Test func rerunWithNewNewestWorkflowShowsTheDismissedPipelineAgain() {
    let dismissed = pipeline(newestWorkflowId: "workflow-1")
    let rerun = pipeline(newestWorkflowId: "workflow-2")
    let sections = queue(pipelines: [rerun], dismissedPipelines: [dismissed.dismissal])
    #expect(items(sections, .fix).map(\.metaTail) == ["#1842 · branch · 6m"])
  }

  @Test func newPipelineOnSameBranchShowsAfterDismiss() {
    let dismissed = pipeline(number: 1, createdHoursAgo: 2)
    let newer = pipeline(number: 2, createdHoursAgo: 1)
    let sections = queue(pipelines: [newer, dismissed], dismissedPipelines: [dismissed.dismissal])
    #expect(items(sections, .fix).map(\.metaTail) == ["#2 · branch · 1h"])
  }

  @Test func dismissingNewestFailureDoesNotShowOlderFailureOnSameKey() {
    let older = pipeline(number: 1, createdHoursAgo: 2)
    let newest = pipeline(number: 2, createdHoursAgo: 1)
    #expect(queue(pipelines: [newest, older], dismissedPipelines: [newest.dismissal]).isEmpty)
  }

  @Test func onlyFailedPipelineRowsCarryADismissal() {
    let failed = pipeline(ref: "main", state: .failed)
    let sections = queue(pipelines: [
      failed, pipeline(number: 2, ref: "release", state: .running), pipeline(number: 3, ref: "hotfix", state: .onHold),
    ])
    #expect(items(sections, .fix).map(\.dismissal) == [.pipeline(failed.dismissal)])
    #expect(items(sections, .watch).map(\.dismissal) == [nil, nil])
  }

  @Test func dismissalDoesNotHideRunningOrOnHoldRows() {
    let running = pipeline(number: 2, ref: "release", state: .running)
    let onHold = pipeline(number: 3, ref: "hotfix", state: .onHold)
    let sections = queue(pipelines: [running, onHold], dismissedPipelines: [running.dismissal, onHold.dismissal])
    #expect(items(sections, .watch).count == 2)
  }

  @Test func dismissedPipelineLeavesTheMenuBarCount() {
    let dismissed = pipeline(number: 1, ref: "main")
    let shown = pipeline(number: 2, ref: "release")
    #expect(MenuBarState(sections: queue(pipelines: [dismissed, shown], dismissedPipelines: [dismissed.dismissal])) == .failing(count: 1))
    #expect(MenuBarState(sections: queue(pipelines: [dismissed], dismissedPipelines: [dismissed.dismissal])) == .normal)
  }
}

struct PrunedDismissalsTests {
  @Test func keepsDismissalOfReturnedPipelineInsideTheWindow() {
    let recent = pipeline(createdHoursAgo: 23)
    #expect(prunedDismissals([recent.dismissal], pipelines: [recent], now: now) == [recent.dismissal])
  }

  @Test func dropsDismissalOfPipelineOlderThanTheWindow() {
    let old = pipeline(createdHoursAgo: 25)
    #expect(prunedDismissals([old.dismissal], pipelines: [old], now: now).isEmpty)
  }

  @Test func dropsDismissalOfPipelineNoLongerReturned() {
    let gone = pipeline(number: 1)
    #expect(prunedDismissals([gone.dismissal], pipelines: [pipeline(number: 2)], now: now).isEmpty)
  }

  @Test func keepsDismissalWhoseNewestWorkflowChangedWhilePipelineIsReturned() {
    let dismissed = pipeline(newestWorkflowId: "workflow-1")
    let rerun = pipeline(newestWorkflowId: "workflow-2")
    #expect(prunedDismissals([dismissed.dismissal], pipelines: [rerun], now: now) == [dismissed.dismissal])
  }
}

struct ReviewDismissalTests {
  private let direct = pullRequest(
    number: 11, author: "ana", requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 30, headCommitId: "commit-1")

  // A lower number is an older request, so the group order is fixed: 8 (72h) before 9 (71h).
  private func botPullRequest(_ number: Int, repository: String = "api-config") -> PullRequest {
    pullRequest(
      repository: repository, number: number, author: "dependabot", authorIsBot: true, requestedReviewerLogins: ["me"],
      reviewRequestedHoursAgo: 80 - Double(number), headCommitId: "bot-commit-\(number)")
  }

  @Test func reviewRowCarriesItsPullRequestDismissal() {
    let reviewItem = items(queue(reviewRequests: [direct]), .review).first
    #expect(reviewItem?.dismissal == .pullRequest(direct.dismissal))
    #expect(
      direct.dismissal
        == PullRequestDismissal(
          repository: "app-web", number: 11, reviewRequestedAt: now.addingTimeInterval(-30 * hour),
          headCommitId: "commit-1"))
  }

  @Test func dismissedReviewRequestIsHidden() {
    #expect(queue(reviewRequests: [direct], dismissedPullRequests: [direct.dismissal]).isEmpty)
  }

  @Test func newReviewRequestShowsTheDismissedPullRequestAgain() {
    var requestedAgain = direct
    requestedAgain.reviewRequestedAt = now.addingTimeInterval(-1 * hour)
    let sections = queue(reviewRequests: [requestedAgain], dismissedPullRequests: [direct.dismissal])
    #expect(items(sections, .review).map(\.id) == ["pr:app-web#11"])
  }

  @Test func newCommitShowsTheDismissedPullRequestAgain() {
    var pushedAgain = direct
    pushedAgain.headCommitId = "commit-2"
    let sections = queue(reviewRequests: [pushedAgain], dismissedPullRequests: [direct.dismissal])
    #expect(items(sections, .review).map(\.id) == ["pr:app-web#11"])
  }

  @Test func botGroupRowIsNotDismissibleButItsChildrenAre() throws {
    let botItem = try #require(items(queue(reviewRequests: [botPullRequest(8), botPullRequest(9)]), .review).first)
    #expect(botItem.dismissal == nil)
    #expect(botItem.children.map(\.dismissal) == [.pullRequest(botPullRequest(8).dismissal), .pullRequest(botPullRequest(9).dismissal)])
  }

  @Test func dismissedBotPullRequestLeavesItsGroup() throws {
    let sections = queue(
      reviewRequests: [botPullRequest(7, repository: "api-notifier"), botPullRequest(8), botPullRequest(9)],
      dismissedPullRequests: [botPullRequest(7, repository: "api-notifier").dismissal])
    let botItem = try #require(items(sections, .review).first)
    #expect(botItem.title == "2 Dependabot PRs")
    #expect(botItem.metaTail == "1 repo · 3d")
    #expect(botItem.children.map(\.id) == ["pr:api-config#8", "pr:api-config#9"])
  }

  @Test func dismissingEveryBotPullRequestRemovesTheGroup() {
    let sections = queue(
      reviewRequests: [botPullRequest(8), botPullRequest(9)],
      dismissedPullRequests: [botPullRequest(8).dismissal, botPullRequest(9).dismissal])
    #expect(sections.isEmpty)
  }

  @Test func dismissedReviewRequestLeavesTheMenuBarCount() {
    let other = pullRequest(number: 12, requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 30)
    #expect(MenuBarState(sections: queue(reviewRequests: [direct, other], dismissedPullRequests: [direct.dismissal])) == .urgent(count: 1))
  }
}

struct PrunedPullRequestDismissalsTests {
  private let requested = pullRequest(number: 11, requestedReviewerLogins: ["me"], reviewRequestedHoursAgo: 2, headCommitId: "commit-1")

  @Test func keepsDismissalOfPullRequestStillRequested() {
    #expect(prunedDismissals([requested.dismissal], reviewRequests: [requested]) == [requested.dismissal])
  }

  @Test func keepsDismissalWhoseCommitChangedWhilePullRequestIsStillRequested() {
    var pushedAgain = requested
    pushedAgain.headCommitId = "commit-2"
    #expect(prunedDismissals([requested.dismissal], reviewRequests: [pushedAgain]) == [requested.dismissal])
  }

  @Test func dropsDismissalOfPullRequestNoLongerRequested() {
    #expect(prunedDismissals([requested.dismissal], reviewRequests: [pullRequest(number: 12)]).isEmpty)
  }

  @Test func matchesOnRepositoryAndNumber() {
    let otherRepository = pullRequest(repository: "api-config", number: 11)
    #expect(prunedDismissals([requested.dismissal], reviewRequests: [otherRepository]).isEmpty)
  }
}
