import Core
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3600

private func pullRequest(
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
  viewerLatestReviewState: ReviewState? = nil
) -> PullRequest {
  PullRequest(
    repository: repository, number: number, title: title,
    url: URL(string: "https://github.com/acme/\(repository)/pull/\(number)")!,
    author: author, authorIsBot: authorIsBot, isDraft: isDraft, updatedAt: now.addingTimeInterval(-updatedHoursAgo * hour),
    headBranch: headBranch, reviewDecision: reviewDecision, checkState: checkState,
    failedCheckCount: failedCheckCount, additions: additions, deletions: deletions,
    requestedReviewerLogins: requestedReviewerLogins, requestedTeamSlugs: requestedTeamSlugs,
    reviewCount: reviewCount,
    reviewRequestedAt: reviewRequestedHoursAgo.map { now.addingTimeInterval(-$0 * hour) },
    unresolvedThreadCount: unresolvedThreadCount, hasMoreThreadsThanFetched: hasMoreThreadsThanFetched,
    approvalCount: approvalCount, requiredApprovalCount: requiredApprovalCount, viewerLatestReviewState: viewerLatestReviewState)
}

private func ticket(key: String, statusName: String = "In Progress", updatedHoursAgo: Double = 72) -> JiraTicket {
  JiraTicket(
    key: key, summary: "Ticket \(key)", statusName: statusName,
    updatedAt: now.addingTimeInterval(-updatedHoursAgo * hour),
    url: URL(string: "https://acme.atlassian.net/browse/\(key)")!)
}

private func pipeline(
  projectSlug: String = "gh/acme/app-web",
  number: Int = 1842,
  ref: String = "main",
  refIsTag: Bool = false,
  triggerType: String = "api",
  hasPullRequest: Bool = false,
  createdHoursAgo: Double = 0.1,
  state: PipelineState = .failed
) -> Pipeline {
  Pipeline(
    projectSlug: projectSlug, number: number, ref: ref, refIsTag: refIsTag, triggerType: triggerType,
    hasPullRequest: hasPullRequest, createdAt: now.addingTimeInterval(-createdHoursAgo * hour), state: state,
    url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/\(number)")!)
}

private func queue(
  authored: [PullRequest] = [], reviewRequests: [PullRequest] = [], tickets: [JiraTicket] = [], pipelines: [Pipeline] = []
) -> [QueueSection] {
  buildQueue(
    QueueInput(
      viewerLogin: "me", authoredPullRequests: authored, reviewRequests: reviewRequests, jiraTickets: tickets,
      pipelines: pipelines),
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
  }

  @Test func openPullRequestWithoutApprovalGoesToWaiting() {
    let sections = queue(authored: [
      pullRequest(repository: "app-api", number: 45, updatedHoursAgo: 3, reviewDecision: .reviewRequired, checkState: nil)
    ])
    let waitingItems = items(sections, .waiting)
    #expect(sections.map(\.kind) == [.waiting])
    #expect(waitingItems.first?.meta == "app-api · 3h")
    #expect(waitingItems.first?.reference == "#45")
    #expect(waitingItems.first?.symbol == .waiting)
    #expect(waitingItems.first?.badge == nil)
  }

  @Test func changesRequestedPullRequestShowsBadgeInWaiting() {
    let sections = queue(authored: [pullRequest(reviewDecision: .changesRequested)])
    #expect(items(sections, .waiting).first?.badge == Badge(text: "Changes requested", variant: .urgent))
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
    #expect(botItem.meta == "2 repos · 3d")
    #expect(botItem.reference == nil)
    #expect(botItem.badge == Badge(text: "Bot", variant: .neutral))
    #expect(botItem.url == URL(string: "https://github.com/pulls?q=is%3Apr%20is%3Aopen%20review-requested%3A%40me%20author%3Aapp%2Fdependabot"))
    #expect(botItem.symbol == .review)
  }

  @Test func singleBotReviewRequestUsesSingular() {
    let sections = queue(reviewRequests: [
      pullRequest(author: "renovate", authorIsBot: true, requestedTeamSlugs: ["obs"], reviewRequestedHoursAgo: 2)
    ])
    #expect(items(sections, .review).first?.title == "1 Renovate PR")
    #expect(items(sections, .review).first?.meta == "1 repo · 2h")
  }

  @Test func teamReviewRequestShowsTeamInMeta() {
    let sections = queue(reviewRequests: [
      pullRequest(number: 2179, author: "Ana", requestedTeamSlugs: ["web-core"], reviewRequestedHoursAgo: 30)
    ])
    #expect(items(sections, .review).first?.meta == "app-web · Ana · team web-core · 1d")
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
    let sections = queue(tickets: [ticket(key: "PROJ-1432", updatedHoursAgo: 72)])
    let tidyItem = items(sections, .tidy).first
    #expect(tidyItem?.badge == Badge(text: "No PR", variant: .neutral))
    #expect(tidyItem?.meta == "PROJ-1432 · In Progress · 3d")
    #expect(tidyItem?.symbol == .noPullRequest)
  }

  @Test func ticketWithUnreviewedPullRequestShowsNoReviewer() {
    let sections = queue(
      authored: [pullRequest(headBranch: "proj-1440-export")],
      tickets: [ticket(key: "PROJ-1440", statusName: "In Review")])
    let tidyItem = items(sections, .tidy).first
    #expect(tidyItem?.badge == Badge(text: "No reviewer", variant: .neutral))
    #expect(tidyItem?.symbol == .noReviewer)
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
        id: "pipeline:gh/acme/app-web:v2.14.0:webhook", title: "app-web v2.14.0", meta: "#1842 · tag · 6m",
        url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/1842")!, symbol: .failing,
        badge: Badge(text: "Pipeline failed", variant: .failing), sortDate: now.addingTimeInterval(-0.1 * hour))
    ])
  }

  @Test func branchPipelineMetaSaysBranch() {
    #expect(items(queue(pipelines: [pipeline(number: 6000, createdHoursAgo: 2)]), .fix).first?.meta == "#6000 · branch · 2h")
  }

  @Test func succeededPipelineGivesNoRow() {
    #expect(queue(pipelines: [pipeline(state: .succeeded)]).isEmpty)
  }

  @Test func runningPipelineGoesToWatch() {
    let sections = queue(pipelines: [pipeline(number: 1842, ref: "v2.14.0", refIsTag: true, createdHoursAgo: 0.1, state: .running)])
    #expect(sections.map(\.kind) == [.watch])
    #expect(items(sections, .watch) == [
      QueueItem(
        id: "pipeline:gh/acme/app-web:v2.14.0:api", title: "app-web v2.14.0", meta: "#1842 · tag · 6m",
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
    #expect(items(sections, .fix).map(\.meta) == ["#2 · branch · 1h"])
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
}
