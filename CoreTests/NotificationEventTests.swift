import Core
import Foundation
import Testing

private let requestTime = Date(timeIntervalSince1970: 1_800_000_000)

private func pullRequest(
  owner: String = "acme",
  number: Int = 1,
  title: String = "Add login",
  checkState: CheckState? = .pending,
  approvalCount: Int = 0,
  requestedReviewerLogins: [String] = ["me"],
  requestedTeamSlugs: [String] = [],
  reviewRequestedAt: Date? = requestTime,
  viewerLatestReviewState: ReviewState? = nil,
  headCommitId: String? = "commit-1"
) -> PullRequest {
  PullRequest(
    repository: "app-web", number: number, title: title,
    url: URL(string: "https://github.com/\(owner)/app-web/pull/\(number)")!, author: "someone", authorIsBot: false,
    isDraft: false, updatedAt: requestTime, headBranch: "feature/x", reviewDecision: nil, checkState: checkState,
    failedCheckCount: checkState == .failure ? 1 : 0, additions: 0, deletions: 0,
    requestedReviewerLogins: requestedReviewerLogins, requestedTeamSlugs: requestedTeamSlugs, reviewCount: 0,
    reviewRequestedAt: reviewRequestedAt, approvalCount: approvalCount, requiredApprovalCount: 2,
    viewerLatestReviewState: viewerLatestReviewState, headCommitId: headCommitId,
    viewerReviewRequestedAt: reviewRequestedAt)
}

private func snapshot(authored: [PullRequest] = [], reviewRequests: [PullRequest] = []) -> GitHubSnapshot {
  GitHubSnapshot(
    viewerLogin: "me", authoredPullRequests: authored, reviewRequests: reviewRequests, reviewsSubmittedToday: 0,
    mergedToday: 0)
}

private func githubEvents(
  previous: GitHubSnapshot, current: GitHubSnapshot, dismissed: Set<PullRequestDismissal> = []
) -> [NotificationEvent] {
  notificationEvents(previous: previous, current: current, dismissedPullRequests: dismissed)
}

private func pipeline(
  number: Int = 1842, state: PipelineState, hasPullRequest: Bool = false, newestWorkflowId: String? = "workflow-1",
  failedWorkflowIds: [String]? = nil
) -> Pipeline {
  Pipeline(
    id: "pipeline-\(number)", projectSlug: "gh/acme/app-web", number: number, ref: "main", refIsTag: false,
    triggerType: "api", hasPullRequest: hasPullRequest, createdAt: requestTime, state: state,
    url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/\(number)")!,
    newestWorkflowId: newestWorkflowId, failedWorkflowIds: failedWorkflowIds)
}

private func pipelineEvents(
  previous: [Pipeline], current: [Pipeline], dismissed: Set<PipelineDismissal> = []
) -> [NotificationEvent] {
  notificationEvents(previous: previous, current: current, dismissedPipelines: dismissed)
}

struct AuthoredPullRequestEventTests {
  @Test func noChangeGivesNoEvents() {
    let state = snapshot(authored: [pullRequest(checkState: .success, approvalCount: 1)])
    #expect(githubEvents(previous: state, current: state).isEmpty)
  }

  @Test func higherApprovalCountGivesApprovedWithTitleAndRepository() {
    let events = githubEvents(
      previous: snapshot(authored: [pullRequest(approvalCount: 0)]),
      current: snapshot(authored: [pullRequest(approvalCount: 1)]))
    #expect(
      events == [
        NotificationEvent(
          kind: .approvalReceived, id: "approvalReceived:https://github.com/acme/app-web/pull/1:approvals=1", body: "Add login\napp-web #1",
          url: URL(string: "https://github.com/acme/app-web/pull/1")!)
      ])
    #expect(events.first?.title == "Approved")
  }

  @Test func secondApprovalGivesASecondEventWithANewId() {
    let events = githubEvents(
      previous: snapshot(authored: [pullRequest(approvalCount: 1)]),
      current: snapshot(authored: [pullRequest(approvalCount: 2)]))
    #expect(events.map(\.id) == ["approvalReceived:https://github.com/acme/app-web/pull/1:approvals=2"])
  }

  @Test func lowerApprovalCountGivesNoEvent() {
    let events = githubEvents(
      previous: snapshot(authored: [pullRequest(approvalCount: 2)]),
      current: snapshot(authored: [pullRequest(approvalCount: 1)]))
    #expect(events.isEmpty)
  }

  @Test(arguments: [CheckState.failure, .error])
  func checksThatFailGiveCIFailed(failedState: CheckState) {
    let events = githubEvents(
      previous: snapshot(authored: [pullRequest(checkState: .pending)]),
      current: snapshot(authored: [pullRequest(checkState: failedState)]))
    #expect(events.map(\.kind) == [.ciFailed])
    #expect(events.first?.id == "ciFailed:https://github.com/acme/app-web/pull/1:commit-1")
  }

  @Test func failureToErrorGivesNoSecondEvent() {
    let events = githubEvents(
      previous: snapshot(authored: [pullRequest(checkState: .failure)]),
      current: snapshot(authored: [pullRequest(checkState: .error)]))
    #expect(events.isEmpty)
  }

  @Test func checksThatPassGiveCIPassed() {
    let events = githubEvents(
      previous: snapshot(authored: [pullRequest(checkState: .failure)]),
      current: snapshot(authored: [pullRequest(checkState: .success)]))
    #expect(events.map(\.kind) == [.ciPassed])
  }

  @Test func newCommitThatFailsAfterAnOlderFailureGivesCIFailed() {
    let events = githubEvents(
      previous: snapshot(authored: [pullRequest(checkState: .failure, headCommitId: "commit-1")]),
      current: snapshot(authored: [pullRequest(checkState: .failure, headCommitId: "commit-2")]))
    #expect(events.map(\.id) == ["ciFailed:https://github.com/acme/app-web/pull/1:commit-2"])
  }

  @Test func sameRepositoryNameInAnotherOwnerIsAnotherPullRequest() {
    let events = githubEvents(
      previous: snapshot(authored: [pullRequest(owner: "acme", approvalCount: 1)]),
      current: snapshot(authored: [
        pullRequest(owner: "acme", approvalCount: 1), pullRequest(owner: "other", approvalCount: 1),
      ]))
    #expect(events.map(\.id) == ["approvalReceived:https://github.com/other/app-web/pull/1:approvals=1"])
  }

  @Test func newPullRequestCountsAsRunningBefore() {
    let events = githubEvents(
      previous: snapshot(), current: snapshot(authored: [pullRequest(checkState: .failure)]))
    #expect(events.map(\.kind) == [.ciFailed])
  }

  @Test func newPullRequestWithRunningChecksGivesNoEvent() {
    let events = githubEvents(previous: snapshot(), current: snapshot(authored: [pullRequest(checkState: nil)]))
    #expect(events.isEmpty)
  }
}

struct ReviewRequestEventTests {
  @Test func newReviewRequestGivesReviewRequested() {
    let events = githubEvents(previous: snapshot(), current: snapshot(reviewRequests: [pullRequest()]))
    #expect(events.map(\.kind) == [.reviewRequested])
    #expect(events.first?.body == "Add login\napp-web #1")
  }

  @Test func sameReviewRequestGivesNoEvent() {
    let state = snapshot(reviewRequests: [pullRequest()])
    #expect(githubEvents(previous: state, current: state).isEmpty)
  }

  @Test func newCommitOnTheSameRequestGivesNoEvent() {
    let events = githubEvents(
      previous: snapshot(reviewRequests: [pullRequest(headCommitId: "commit-1")]),
      current: snapshot(reviewRequests: [pullRequest(headCommitId: "commit-2")]))
    #expect(events.isEmpty)
  }

  @Test func newRequestTimeOnTheSamePullRequestGivesANewEvent() {
    let events = githubEvents(
      previous: snapshot(reviewRequests: [pullRequest(reviewRequestedAt: requestTime)]),
      current: snapshot(reviewRequests: [pullRequest(reviewRequestedAt: requestTime.addingTimeInterval(60))]))
    #expect(events.map(\.kind) == [.reviewRequested])
  }

  @Test func teamRequestCounts() {
    let teamRequest = pullRequest(requestedReviewerLogins: [], requestedTeamSlugs: ["web"])
    let events = githubEvents(previous: snapshot(), current: snapshot(reviewRequests: [teamRequest]))
    #expect(events.map(\.kind) == [.reviewRequested])
  }

  @Test func teamRequestTheViewerAlreadyApprovedGivesNoEvent() {
    let approvedTeamRequest = pullRequest(
      requestedReviewerLogins: [], requestedTeamSlugs: ["web"], viewerLatestReviewState: .approved)
    let events = githubEvents(previous: snapshot(), current: snapshot(reviewRequests: [approvedTeamRequest]))
    #expect(events.isEmpty)
  }

  @Test func approvedTeamRequestThatOpensAgainWithTheSameTimeGivesNoEvent() {
    let teamRequest = pullRequest(requestedReviewerLogins: [], requestedTeamSlugs: ["web"], viewerLatestReviewState: .approved)
    var reopenedRequest = teamRequest
    reopenedRequest.viewerLatestReviewState = .dismissed
    let events = githubEvents(
      previous: snapshot(reviewRequests: [teamRequest]), current: snapshot(reviewRequests: [reopenedRequest]))
    #expect(events.isEmpty)
  }

  @Test func viewerRequestTimeWinsOverTheNewestRequestTime() {
    let firstRequest = pullRequest(reviewRequestedAt: requestTime)
    var laterRequestToSomeoneElse = firstRequest
    laterRequestToSomeoneElse.reviewRequestedAt = requestTime.addingTimeInterval(60)
    laterRequestToSomeoneElse.viewerReviewRequestedAt = requestTime
    var previousRequest = firstRequest
    previousRequest.viewerReviewRequestedAt = requestTime
    let events = githubEvents(
      previous: snapshot(reviewRequests: [previousRequest]), current: snapshot(reviewRequests: [laterRequestToSomeoneElse]))
    #expect(events.isEmpty)
  }

  @Test func earlierRequestTimeAfterADirectRequestGoesAwayGivesNoEvent() {
    let events = githubEvents(
      previous: snapshot(reviewRequests: [pullRequest(reviewRequestedAt: requestTime.addingTimeInterval(60))]),
      current: snapshot(reviewRequests: [pullRequest(reviewRequestedAt: requestTime)]))
    #expect(events.isEmpty)
  }

  @Test func olderTeamRequestLeftAfterTheDirectRequestGoesAwayGivesNoEvent() {
    var directRequest = pullRequest(reviewRequestedAt: requestTime.addingTimeInterval(60))
    directRequest.viewerReviewRequestedAt = requestTime
    var teamRequestLeft = directRequest
    teamRequestLeft.requestedReviewerLogins = []
    teamRequestLeft.requestedTeamSlugs = ["web"]
    teamRequestLeft.viewerReviewRequestedAt = requestTime.addingTimeInterval(60)
    let events = githubEvents(
      previous: snapshot(reviewRequests: [directRequest]), current: snapshot(reviewRequests: [teamRequestLeft]))
    #expect(events.isEmpty)
  }

  @Test func newRequestAfterAViewerTimeOutsideTheWindowGivesAnEvent() {
    var requestOutsideWindow = pullRequest()
    requestOutsideWindow.viewerReviewRequestedAt = nil
    let events = githubEvents(
      previous: snapshot(reviewRequests: [requestOutsideWindow]),
      current: snapshot(reviewRequests: [pullRequest(reviewRequestedAt: requestTime.addingTimeInterval(60))]))
    #expect(events.map(\.kind) == [.reviewRequested])
  }

  @Test func viewerRequestOutsideTheFetchedWindowGivesNoEvent() {
    var requestOutsideWindow = pullRequest()
    requestOutsideWindow.viewerReviewRequestedAt = nil
    requestOutsideWindow.reviewRequestedAt = requestTime.addingTimeInterval(60)
    let events = githubEvents(
      previous: snapshot(reviewRequests: [pullRequest()]), current: snapshot(reviewRequests: [requestOutsideWindow]))
    #expect(events.isEmpty)
  }

  @Test func dismissedReviewRequestGivesNoEvent() {
    let request = pullRequest()
    let events = githubEvents(
      previous: snapshot(), current: snapshot(reviewRequests: [request]), dismissed: [request.dismissal])
    #expect(events.isEmpty)
  }
}

struct PipelineEventTests {
  @Test func noChangeGivesNoEvents() {
    let pipelines = [pipeline(state: .failed)]
    #expect(pipelineEvents(previous: pipelines, current: pipelines).isEmpty)
  }

  @Test func failedPipelineGivesCIFailedWithRefAndProject() {
    let events = pipelineEvents(previous: [pipeline(state: .running)], current: [pipeline(state: .failed)])
    #expect(
      events == [
        NotificationEvent(
          kind: .ciFailed, id: "ciFailed:pipeline:pipeline-1842:workflow-1", body: "main\napp-web #1842",
          url: URL(string: "https://app.circleci.com/pipelines/github/acme/app-web/1842")!)
      ])
  }

  @Test func succeededPipelineGivesCIPassed() {
    let events = pipelineEvents(previous: [pipeline(state: .running)], current: [pipeline(state: .succeeded)])
    #expect(events.map(\.kind) == [.ciPassed])
  }

  @Test func onHoldPipelineGivesCINeedsApproval() {
    let events = pipelineEvents(previous: [pipeline(state: .running)], current: [pipeline(state: .onHold)])
    #expect(events.map(\.kind) == [.ciNeedsApproval])
  }

  @Test func pipelineBackToRunningGivesNoEvent() {
    let events = pipelineEvents(previous: [pipeline(state: .failed)], current: [pipeline(state: .running)])
    #expect(events.isEmpty)
  }

  @Test func rerunThatFailsAfterAnOlderFailureGivesCIFailed() {
    let events = pipelineEvents(
      previous: [pipeline(state: .failed, newestWorkflowId: "build-1", failedWorkflowIds: ["build-1"])],
      current: [pipeline(state: .failed, newestWorkflowId: "build-2", failedWorkflowIds: ["build-2"])])
    #expect(events.map(\.id) == ["ciFailed:pipeline:pipeline-1842:build-2"])
  }

  @Test func workflowsThatFailOnDifferentRefreshesGetDifferentIds() {
    let firstFailure = pipelineEvents(
      previous: [pipeline(state: .running, newestWorkflowId: "deploy-1")],
      current: [pipeline(state: .failed, newestWorkflowId: "deploy-1", failedWorkflowIds: ["build-1"])])
    let secondFailure = pipelineEvents(
      previous: [pipeline(state: .failed, newestWorkflowId: "deploy-1", failedWorkflowIds: ["build-1"])],
      current: [pipeline(state: .failed, newestWorkflowId: "deploy-1", failedWorkflowIds: ["build-1", "deploy-1"])])
    #expect(firstFailure.map(\.id) == ["ciFailed:pipeline:pipeline-1842:build-1"])
    #expect(secondFailure.map(\.id) == ["ciFailed:pipeline:pipeline-1842:deploy-1"])
  }

  @Test func rerunOfAnotherWorkflowWhileOneStaysFailedGivesNoEvent() {
    let events = pipelineEvents(
      previous: [pipeline(state: .failed, newestWorkflowId: "build-1", failedWorkflowIds: ["build-1"])],
      current: [pipeline(state: .failed, newestWorkflowId: "deploy-2", failedWorkflowIds: ["build-1"])])
    #expect(events.isEmpty)
  }

  @Test func canceledPipelineGivesNoEvent() {
    let events = pipelineEvents(previous: [pipeline(state: .running)], current: [pipeline(state: .canceled)])
    #expect(events.isEmpty)
  }

  @Test func newPipelineThatAlreadyFailedCountsAsRunningBefore() {
    let events = pipelineEvents(previous: [], current: [pipeline(state: .failed)])
    #expect(events.map(\.kind) == [.ciFailed])
  }

  // GitHub checks already post CI failed and CI passed for a PR, so only the on-hold state counts.
  @Test(arguments: [PipelineState.failed, .succeeded, .canceled])
  func pipelineWithAPullRequestGivesNoFinishedEvent(state: PipelineState) {
    let events = pipelineEvents(
      previous: [pipeline(state: .running, hasPullRequest: true)], current: [pipeline(state: state, hasPullRequest: true)])
    #expect(events.isEmpty)
  }

  @Test func newPipelineWithAPullRequestAlreadyOnHoldGivesCINeedsApproval() {
    let events = pipelineEvents(previous: [], current: [pipeline(state: .onHold, hasPullRequest: true)])
    #expect(events.map(\.kind) == [.ciNeedsApproval])
  }

  @Test func onHoldPipelineWithAPullRequestGivesCINeedsApproval() {
    let events = pipelineEvents(
      previous: [pipeline(state: .running, hasPullRequest: true)], current: [pipeline(state: .onHold, hasPullRequest: true)])
    #expect(events.map(\.kind) == [.ciNeedsApproval])
  }

  @Test func dismissedPipelineGivesNoEvent() {
    let failedPipeline = pipeline(state: .failed)
    let events = pipelineEvents(
      previous: [pipeline(state: .running)], current: [failedPipeline], dismissed: [failedPipeline.dismissal])
    #expect(events.isEmpty)
  }
}
