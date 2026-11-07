import AppKit
import Core
import Foundation
import Observation

enum JiraSettingsKeys {
  static let siteURL = "jiraSiteURL"
  static let email = "jiraEmail"

  static func load() -> JiraSettings? {
    let defaults = UserDefaults.standard
    guard
      let siteText = defaults.string(forKey: siteURL), let site = URL(string: siteText), site.host() != nil,
      let email = defaults.string(forKey: email), !email.isEmpty,
      let token = KeychainStore.read(account: KeychainStore.jiraTokenAccount), !token.isEmpty
    else { return nil }
    return JiraSettings(siteURL: site, email: email, apiToken: token)
  }
}

enum CircleCISettingsKeys {
  static let projectSlugs = "circleciProjectSlugs"

  static func load() -> CircleCISettings? {
    let slugs = (UserDefaults.standard.string(forKey: projectSlugs) ?? "")
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard let token = KeychainStore.read(account: KeychainStore.circleciTokenAccount), !token.isEmpty, !slugs.isEmpty
    else { return nil }
    return CircleCISettings(apiToken: token, projectSlugs: slugs)
  }
}

@MainActor @Observable final class QueueStore {
  private(set) var sections: [QueueSection] = []
  private(set) var menuBarState: MenuBarState = .normal
  private(set) var githubStatus: SourceStatus = .idle
  private(set) var jiraStatus: SourceStatus = .idle
  private(set) var circleciStatus: SourceStatus = .idle
  private(set) var githubSnapshot: GitHubSnapshot?
  private(set) var githubFetchedAt: Date?
  private(set) var jiraFetchedAt: Date?
  private(set) var circleciFetchedAt: Date?
  private(set) var isRefreshing = false
  private(set) var jiraTickets: [JiraTicket]?
  private(set) var pipelines: [Pipeline]?

  let tokenProvider = GhCLITokenProvider()
  private let transport = URLSessionTransport()
  private let cache = SourceCache(
    directory: URL.applicationSupportDirectory.appendingPathComponent("Tower", isDirectory: true))
  private var pollingTask: Task<Void, Never>?
  private var activationObserver: NSObjectProtocol?

  var todaySummary: (reviews: Int, merges: Int)? {
    githubSnapshot.map { ($0.reviewsSubmittedToday, $0.mergedToday) }
  }

  func start() {
    guard pollingTask == nil else { return }
    if let cached = cache.load(GitHubSnapshot.self, name: "github") {
      githubSnapshot = cached.value
      githubFetchedAt = cached.fetchedAt
    }
    if let cached = cache.load([JiraTicket].self, name: "jira") {
      jiraTickets = cached.value
      jiraFetchedAt = cached.fetchedAt
    }
    if let cached = cache.load([Pipeline].self, name: "circleci") {
      pipelines = cached.value
      circleciFetchedAt = cached.fetchedAt
    }
    rebuild()
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.refresh()
        try? await Task.sleep(for: nextRefreshInterval(sources: self.panelSources))
      }
    }
    // Reconnect sends the owner to Terminal or Settings. Refresh when Tower comes back.
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.hasAuthenticationFailure else { return }
        Task { await self.refresh() }
      }
    }
  }

  // GitHub comes first, then Jira, then CircleCI, so the earlier stale label wins in the subtitle.
  var panelSources: [PanelSource] {
    [
      PanelSource(status: githubStatus, hasData: githubSnapshot != nil, fetchedAt: githubFetchedAt, staleLabel: "PRs"),
      PanelSource(status: jiraStatus, hasData: jiraTickets != nil, fetchedAt: jiraFetchedAt, staleLabel: "Tickets"),
      PanelSource(status: circleciStatus, hasData: pipelines != nil, fetchedAt: circleciFetchedAt, staleLabel: "Pipelines"),
    ]
  }

  var hasAuthenticationFailure: Bool {
    githubStatus == .failed(.authentication) || jiraStatus == .failed(.authentication)
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    let now = Date()
    let githubClient = GitHubClient(tokenProvider: tokenProvider, transport: transport)
    let jiraClient = JiraClient(settings: JiraSettingsKeys.load(), transport: transport)
    let circleciClient = CircleCIClient(settings: CircleCISettingsKeys.load(), transport: transport)
    async let githubResult = Result { () async throws(SourceFailure) -> GitHubSnapshot in try await githubClient.fetch(now: now) }
    async let jiraResult = Result { () async throws(SourceFailure) -> [JiraTicket] in try await jiraClient.fetch() }
    async let circleciResult = Result { () async throws(SourceFailure) -> [Pipeline] in try await circleciClient.fetch(now: now) }

    switch await githubResult {
    case .success(let snapshot):
      githubSnapshot = snapshot
      githubFetchedAt = now
      githubStatus = .ok
      try? cache.save(Cached(value: snapshot, fetchedAt: now), name: "github")
    case .failure(let failure):
      githubStatus = .failed(failure)
    }
    switch await jiraResult {
    case .success(let tickets):
      jiraTickets = tickets
      jiraFetchedAt = now
      jiraStatus = .ok
      try? cache.save(Cached(value: tickets, fetchedAt: now), name: "jira")
    case .failure(let failure):
      jiraStatus = .failed(failure)
      if failure == .notConfigured { jiraTickets = nil }
    }
    switch await circleciResult {
    case .success(let fetchedPipelines):
      pipelines = fetchedPipelines
      circleciFetchedAt = now
      circleciStatus = .ok
      try? cache.save(Cached(value: fetchedPipelines, fetchedAt: now), name: "circleci")
    case .failure(let failure):
      circleciStatus = .failed(failure)
      if failure == .notConfigured { pipelines = nil }
    }
    rebuild()
  }

  private func rebuild() {
    let input = QueueInput(
      viewerLogin: githubSnapshot?.viewerLogin ?? "",
      authoredPullRequests: githubSnapshot?.authoredPullRequests ?? [],
      reviewRequests: githubSnapshot?.reviewRequests ?? [],
      jiraTickets: jiraTickets ?? [],
      pipelines: pipelines ?? [])
    sections = buildQueue(input, now: Date())
    menuBarState = MenuBarState(sections: sections)
  }
}

extension Result where Failure == SourceFailure {
  init(catching body: () async throws(SourceFailure) -> Success) async {
    do {
      self = .success(try await body())
    } catch {
      self = .failure(error)
    }
  }
}
