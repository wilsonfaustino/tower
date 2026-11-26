#if DEBUG
import Foundation

// Fixed fake data for the Debug-only `-demo <scenario>` launch argument. No value comes from a real
// account. Release builds do not compile this file.
public struct DemoScenario: Sendable {
  public enum Name: String, CaseIterable, Sendable {
    case typical
    case longList = "long-list"
    case clearSkies = "clear-skies"
    case offline
    case authFailure = "auth-failure"
    case notify
    case update

    // An unknown or empty value gives typical.
    public init(launchValue: String) {
      self = Name(rawValue: launchValue) ?? .typical
    }
  }

  public static let viewerLogin = "demo-user"

  public let name: Name
  public let githubSnapshot: GitHubSnapshot?
  public let jiraTickets: [JiraTicket]?
  public let pipelines: [Pipeline]?
  public let githubStatus: SourceStatus
  public let jiraStatus: SourceStatus
  public let circleciStatus: SourceStatus
  // The data the first refresh changes to. Only notify has it, so a refresh posts one notification of each kind.
  public let changedGitHubSnapshot: GitHubSnapshot?
  public let changedPipelines: [Pipeline]?
  // A fake newer release. Only update has it, so the panel and Settings show the update notice without a network call.
  public let availableVersion: String?

  public init(name: Name, now: Date) {
    self.name = name
    let factory = DemoFactory(now: now)
    switch name {
    case .typical, .authFailure, .notify, .update:
      githubSnapshot = factory.snapshot(authored: factory.typicalAuthored, reviews: factory.typicalReviews)
      jiraTickets = factory.typicalTickets
      pipelines = factory.typicalPipelines
    case .longList:
      githubSnapshot = factory.snapshot(
        authored: factory.typicalAuthored, reviews: factory.typicalReviews + factory.manyBotReviews + factory.manyTeamReviews)
      jiraTickets = factory.typicalTickets
      pipelines = factory.typicalPipelines + factory.olderRunningPipelines
    case .clearSkies:
      githubSnapshot = factory.snapshot(authored: [], reviews: [], reviewsSubmittedToday: 4, mergedToday: 2)
      jiraTickets = []
      pipelines = []
    case .offline:
      githubSnapshot = nil
      jiraTickets = nil
      pipelines = nil
    }
    switch name {
    case .offline:
      githubStatus = .failed(.network)
      jiraStatus = .failed(.network)
      circleciStatus = .failed(.network)
    case .authFailure:
      githubStatus = .failed(.authentication)
      jiraStatus = .ok
      circleciStatus = .ok
    case .typical, .longList, .clearSkies, .notify, .update:
      githubStatus = .ok
      jiraStatus = .ok
      circleciStatus = .ok
    }
    if name == .notify {
      changedGitHubSnapshot = factory.snapshot(
        authored: factory.notifyChangedAuthored, reviews: factory.typicalReviews + [factory.notifyNewReview])
      changedPipelines = factory.notifyChangedPipelines
    } else {
      changedGitHubSnapshot = nil
      changedPipelines = nil
    }
    availableVersion = name == .update ? "1.0.0" : nil
  }

  // The value after -demo. nil without -demo, and empty when -demo is the last argument.
  public static func launchValue(arguments: [String]) -> String? {
    guard let flagIndex = arguments.firstIndex(of: "-demo") else { return nil }
    let valueIndex = flagIndex + 1
    return arguments.indices.contains(valueIndex) ? arguments[valueIndex] : ""
  }
}

private struct DemoFactory {
  let now: Date

  func ago(hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

  func snapshot(
    authored: [PullRequest], reviews: [PullRequest], reviewsSubmittedToday: Int = 1, mergedToday: Int = 0
  ) -> GitHubSnapshot {
    GitHubSnapshot(
      viewerLogin: DemoScenario.viewerLogin, authoredPullRequests: authored, reviewRequests: reviews,
      reviewsSubmittedToday: reviewsSubmittedToday, mergedToday: mergedToday,
      recentlyMergedPullRequests: [MergedPullRequest(title: "DEMO-12 Ship the beacon count", headBranch: "demo-12-beacon")])
  }

  func pullRequest(
    _ repository: String, _ number: Int, _ title: String, author: String = DemoScenario.viewerLogin,
    isBot: Bool = false, isDraft: Bool = false, hoursAgo: Double, branch: String = "feature", base: String = "main",
    decision: ReviewDecision? = .reviewRequired, checks: CheckState? = .success, failedChecks: Int = 0,
    reviewers: [String] = ["teammate"], teams: [String] = [], reviewCount: Int = 0, threads: Int = 0,
    approvals: Int = 0, requiredApprovals: Int = 1
  ) -> PullRequest {
    PullRequest(
      repository: repository, number: number, title: title,
      url: URL(string: "https://github.com/\(repository)/pull/\(number)")!, author: author, authorIsBot: isBot,
      isDraft: isDraft, updatedAt: ago(hours: hoursAgo), headBranch: branch, reviewDecision: decision,
      checkState: checks, failedCheckCount: failedChecks, additions: 120 + number % 300, deletions: 12 + number % 90,
      requestedReviewerLogins: reviewers, requestedTeamSlugs: teams, reviewCount: reviewCount,
      reviewRequestedAt: ago(hours: hoursAgo), unresolvedThreadCount: threads, approvalCount: approvals,
      requiredApprovalCount: requiredApprovals, baseBranch: base)
  }

  var typicalAuthored: [PullRequest] {
    [
      // Fix
      pullRequest("demo-org/api", 412, "Fix flaky date parser in sync job", hoursAgo: 3, checks: .failure, failedChecks: 2, threads: 2, approvals: 1, requiredApprovals: 2),
      // Merge
      pullRequest("demo-org/tower", 63, "Release workflow and Homebrew cask", hoursAgo: 2, decision: .approved, approvals: 2, requiredApprovals: 2),
      // Waiting: passed, running and failed checks, changes requested, drafts, and an infra repo group with a stack
      pullRequest("demo-org/web", 220, "Add keyboard navigation to the queue", hoursAgo: 5, branch: "demo-41-keyboard", threads: 1),
      pullRequest("demo-org/web", 221, "Cache avatars on disk", hoursAgo: 4, checks: .pending),
      pullRequest("demo-org/api", 415, "Rename the billing webhook fields", hoursAgo: 26, decision: .changesRequested, threads: 3),
      pullRequest("demo-org/tower", 66, "Menu bar beacon count", isDraft: true, hoursAgo: 6, reviewers: []),
      pullRequest("demo-org/tower", 67, "Try a denser row layout", isDraft: true, hoursAgo: 8, checks: .failure, failedChecks: 1, reviewers: []),
      pullRequest("demo-org/infra", 90, "chore: bump terraform to 1.9", hoursAgo: 30, branch: "terraform-1.9"),
      pullRequest("demo-org/infra", 91, "chore: pin the runner image", hoursAgo: 31, branch: "pin-runner", base: "terraform-1.9", checks: .pending),
      pullRequest("demo-org/infra", 92, "chore: drop the old NAT gateway", hoursAgo: 32, checks: .failure, failedChecks: 1),
      pullRequest("demo-org/infra", 93, "chore: try spot runners", isDraft: true, hoursAgo: 33, reviewers: []),
      pullRequest("demo-org/infra", 94, "chore: rotate the deploy keys", hoursAgo: 34, decision: .changesRequested, threads: 1),
      // Tidy: no reviewer for DEMO-38
      pullRequest("demo-org/api", 418, "DEMO-38 Cache CircleCI pipelines", hoursAgo: 5, branch: "demo-38-cache", reviewers: []),
    ]
  }

  var typicalReviews: [PullRequest] {
    [
      pullRequest("demo-org/api", 128, "Add keychain migration for Jira token", author: "alice", hoursAgo: 30, reviewers: [DemoScenario.viewerLogin]),
      pullRequest("demo-org/web", 301, "Move settings into a sheet", author: "bruno", hoursAgo: 3, reviewers: [], teams: ["demo-org/frontend"]),
      pullRequest("demo-org/api", 501, "build(deps): bump flask from 2.3.3 to 3.1.3", author: "dependabot[bot]", isBot: true, hoursAgo: 200, reviewers: [DemoScenario.viewerLogin]),
      pullRequest("demo-org/web", 502, "build(deps): bump vite from 5.4.0 to 6.0.1", author: "dependabot[bot]", isBot: true, hoursAgo: 120, reviewers: [DemoScenario.viewerLogin]),
      pullRequest("demo-org/infra", 503, "chore(deps): bump urllib3 from 2.0.7 to 2.7.0", author: "dependabot[bot]", isBot: true, hoursAgo: 90, reviewers: [DemoScenario.viewerLogin]),
    ]
  }

  var manyBotReviews: [PullRequest] {
    let packages = ["idna", "starlette", "python-multipart", "pyjwt", "ujson", "ddtrace", "setuptools", "aiohttp", "certifi", "jinja2", "pydantic", "httpx", "uvicorn", "boto3"]
    return packages.enumerated().map { index, package in
      pullRequest(
        "demo-org/service-\(index % 4)", 600 + index, "chore(deps): bump \(package) from 1.\(index).0 to 2.0.\(index)",
        author: "dependabot[bot]", isBot: true, hoursAgo: Double(48 + index * 20), reviewers: [DemoScenario.viewerLogin])
    }
  }

  var manyTeamReviews: [PullRequest] {
    let titles = ["Split the sync worker", "Add retry budget to the HTTP client", "Log slow GraphQL queries", "Remove the legacy importer", "Show stale data age in the header", "Paginate Jira search", "Batch keychain reads", "Trim the release notes script"]
    return titles.enumerated().map { index, title in
      pullRequest("demo-org/platform", 700 + index, title, author: "carol", hoursAgo: Double(2 + index * 3), reviewers: [], teams: ["demo-org/platform"])
    }
  }

  var typicalTickets: [JiraTicket] {
    [
      JiraTicket(key: "DEMO-41", summary: "Keyboard navigation", statusName: "In Progress", updatedAt: ago(hours: 5), url: URL(string: "https://demo.atlassian.net/browse/DEMO-41")!, issueTypeName: "Story"),
      JiraTicket(key: "DEMO-45", summary: "Tidy settings layout", statusName: "In Progress", updatedAt: ago(hours: 48), url: URL(string: "https://demo.atlassian.net/browse/DEMO-45")!, issueTypeName: "Bug"),
      JiraTicket(key: "DEMO-38", summary: "Cache CircleCI pipelines", statusName: "In Progress", updatedAt: ago(hours: 5), url: URL(string: "https://demo.atlassian.net/browse/DEMO-38")!, issueTypeName: "Task"),
    ]
  }

  var typicalPipelines: [Pipeline] {
    [
      pipeline("demo-org/tower", 880, ref: "main", state: .failed, hoursAgo: 0.7),
      pipeline("demo-org/tower", 881, ref: "release", state: .onHold, hoursAgo: 0.2),
      pipeline("demo-org/api", 1204, ref: "feat/today-summary", state: .running, hoursAgo: 0.05),
    ]
  }

  // Older than the on-hold pipeline, so by date Watch lists both before it, and the pinned area must move it up.
  var olderRunningPipelines: [Pipeline] {
    [
      pipeline("demo-org/web", 512, ref: "feat/search", state: .running, hoursAgo: 1.5),
      pipeline("demo-org/web", 513, ref: "fix/login", state: .running, hoursAgo: 1.2),
    ]
  }

  // Typical data after one refresh: api#412 gets an approval, web#221 fails, infra#91 passes.
  var notifyChangedAuthored: [PullRequest] {
    typicalAuthored.map { pullRequest in
      var changedPullRequest = pullRequest
      switch (pullRequest.repository, pullRequest.number) {
      case ("demo-org/api", 412): changedPullRequest.approvalCount += 1
      case ("demo-org/web", 221):
        changedPullRequest.checkState = .failure
        changedPullRequest.failedCheckCount = 1
      case ("demo-org/infra", 91): changedPullRequest.checkState = .success
      default: break
      }
      return changedPullRequest
    }
  }

  var notifyNewReview: PullRequest {
    var newReview = pullRequest(
      "demo-org/web", 330, "Show notifications for CI results", author: "dana", hoursAgo: 0,
      reviewers: [DemoScenario.viewerLogin])
    newReview.viewerReviewRequestedAt = newReview.reviewRequestedAt
    return newReview
  }

  // api#1204 stops at an approval job.
  var notifyChangedPipelines: [Pipeline] {
    typicalPipelines.map { pipeline in
      var changedPipeline = pipeline
      if pipeline.number == 1204 { changedPipeline.state = .onHold }
      return changedPipeline
    }
  }

  func pipeline(_ project: String, _ number: Int, ref: String, state: PipelineState, hoursAgo: Double) -> Pipeline {
    Pipeline(
      id: "demo-\(number)", projectSlug: "gh/\(project)", number: number, ref: ref, refIsTag: false,
      triggerType: "webhook", hasPullRequest: false, createdAt: ago(hours: hoursAgo), state: state,
      url: URL(string: "https://app.circleci.com/pipelines/gh/\(project)/\(number)")!, newestWorkflowId: nil)
  }
}
#endif
