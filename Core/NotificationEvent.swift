import Foundation

public enum NotificationEventKind: String, CaseIterable, Sendable {
  case approvalReceived, reviewRequested, ciFailed, ciPassed, ciNeedsApproval

  public var title: String {
    switch self {
    case .approvalReceived: "Approved"
    case .reviewRequested: "Review requested"
    case .ciFailed: "CI failed"
    case .ciPassed: "CI passed"
    case .ciNeedsApproval: "CI needs approval"
    }
  }
}

public struct NotificationEvent: Equatable, Sendable {
  public var kind: NotificationEventKind
  // Built from the kind, the item and the new state, so the same event always gets the same id.
  public var id: String
  public var body: String
  public var url: URL

  public var title: String { kind.title }

  public init(kind: NotificationEventKind, id: String, body: String, url: URL) {
    self.kind = kind
    self.id = id
    self.body = body
    self.url = url
  }
}

// Events between two successful GitHub fetches. A PR that is new in the current snapshot counts as running before.
public func notificationEvents(
  previous: GitHubSnapshot, current: GitHubSnapshot, dismissedPullRequests: Set<PullRequestDismissal>
) -> [NotificationEvent] {
  var events: [NotificationEvent] = []
  let previousAuthoredByURL = Dictionary(previous.authoredPullRequests.map { ($0.url, $0) }) { first, _ in first }
  for pullRequest in current.authoredPullRequests {
    let previousPullRequest = previousAuthoredByURL[pullRequest.url]
    if pullRequest.approvalCount > previousPullRequest?.approvalCount ?? 0 {
      events.append(pullRequest.event(.approvalReceived, state: "approvals=\(pullRequest.approvalCount)"))
    }
    // A new commit starts a new check run, so a result on an older commit does not count.
    let previousChecks = previousPullRequest?.headCommitId == pullRequest.headCommitId ? previousPullRequest : nil
    let wasFailing = previousChecks?.isFailing ?? false
    let wasPassing = previousChecks?.checkState == .success
    if pullRequest.isFailing && !wasFailing {
      events.append(pullRequest.event(.ciFailed, state: pullRequest.headCommitId ?? ""))
    } else if pullRequest.checkState == .success && !wasPassing {
      events.append(pullRequest.event(.ciPassed, state: pullRequest.headCommitId ?? ""))
    }
  }
  // Every previous request counts, so a stale approval that reopens an old request posts nothing.
  let previousNewestRequestTimes = Dictionary(previous.reviewRequests.map { ($0.url, $0.reviewRequestedAt) }) {
    first, _ in first
  }
  for pullRequest in current.reviewRequests
  where isOpenReviewRequest(pullRequest, viewerLogin: current.viewerLogin)
    && !dismissedPullRequests.contains(pullRequest.dismissal)
  {
    // On a known PR only a request to the viewer that is newer than every request the previous fetch saw counts.
    // An older one, for example a team request left after a direct request goes away, is not a new request.
    if let previousNewestTime = previousNewestRequestTimes[pullRequest.url] {
      guard let currentTime = pullRequest.viewerReviewRequestedAt, previousNewestTime.map({ currentTime > $0 }) ?? true
      else { continue }
    }
    let requestTime = pullRequest.viewerReviewRequestedAt ?? pullRequest.reviewRequestedAt
    events.append(pullRequest.event(.reviewRequested, state: requestTime.map { "\($0.timeIntervalSince1970)" } ?? ""))
  }
  return events
}

// Events between two successful CircleCI fetches. A pipeline that is new in the current list counts as running before.
// A pipeline with a PR gives only CI needs approval: GitHub checks already post CI failed and CI passed for it.
public func notificationEvents(
  previous: [Pipeline], current: [Pipeline], dismissedPipelines: Set<PipelineDismissal>
) -> [NotificationEvent] {
  let previousById = Dictionary(previous.map { ($0.id, $0) }) { first, _ in first }
  return current.compactMap { pipeline in
    guard !pipeline.hasPullRequest || pipeline.state == .onHold, !dismissedPipelines.contains(pipeline.dismissal) else {
      return nil
    }
    let previousPipeline = previousById[pipeline.id]
    // A state Tower never read is not a known "before", as at launch.
    guard previousPipeline?.workflowStateIsUnknown != true else { return nil }
    let previousState = previousPipeline?.state ?? .running
    // A rerun that fails again between two refreshes stays failed, so a newly failed workflow counts as a change.
    let newlyFailedWorkflowIds = Set(pipeline.failedWorkflowIds ?? [])
      .subtracting(previousPipeline?.failedWorkflowIds ?? []).sorted()
    guard pipeline.state != previousState || (pipeline.state == .failed && !newlyFailedWorkflowIds.isEmpty) else {
      return nil
    }
    let kind: NotificationEventKind
    switch pipeline.state {
    case .failed: kind = .ciFailed
    case .succeeded: kind = .ciPassed
    case .onHold: kind = .ciNeedsApproval
    case .running, .canceled: return nil
    }
    let repository = pipeline.projectSlug.split(separator: "/").last.map(String.init) ?? pipeline.projectSlug
    // Two workflows that fail on different refreshes get different ids, so the second does not replace the first.
    let state =
      kind == .ciFailed && !newlyFailedWorkflowIds.isEmpty
      ? newlyFailedWorkflowIds.joined(separator: ",") : pipeline.newestWorkflowId ?? ""
    return NotificationEvent(
      kind: kind, id: "\(kind.rawValue):pipeline:\(pipeline.id):\(state)",
      body: "\(pipeline.ref)\n\(repository) #\(pipeline.number)", url: pipeline.url)
  }
}

// The baseline for the next pipeline diff. A pipeline whose workflow read failed keeps its last known entry,
// so the next good read of the same state is not a change.
public func notificationBaseline(previous: [Pipeline], current: [Pipeline]) -> [Pipeline] {
  let previousById = Dictionary(previous.map { ($0.id, $0) }) { first, _ in first }
  return current.map { pipeline in
    guard pipeline.workflowStateIsUnknown, let previousPipeline = previousById[pipeline.id] else { return pipeline }
    return previousPipeline
  }
}

extension PullRequest {
  fileprivate func event(_ kind: NotificationEventKind, state: String) -> NotificationEvent {
    NotificationEvent(
      kind: kind, id: "\(kind.rawValue):\(url.absoluteString):\(state)", body: "\(title)\n\(repository) #\(number)", url: url)
  }
}
