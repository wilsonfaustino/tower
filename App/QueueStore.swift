import AppKit
import Core
import Foundation
import Observation

enum JiraSettingsKeys {
  static let siteURL = "jiraSiteURL"
  static let email = "jiraEmail"

  static func load(
    defaults: UserDefaults = .standard, readToken: (String) -> String? = KeychainStore.read(account:)
  ) -> JiraSettings? {
    guard
      let siteText = defaults.string(forKey: siteURL), let site = URL(string: siteText), site.host() != nil,
      let email = defaults.string(forKey: email), !email.isEmpty,
      let token = readToken(KeychainStore.jiraTokenAccount), !token.isEmpty
    else { return nil }
    return JiraSettings(siteURL: site, email: email, apiToken: token)
  }
}

enum CircleCISettingsKeys {
  static let projectSlugs = "circleciProjectSlugs"

  static func load(
    defaults: UserDefaults = .standard, readToken: (String) -> String? = KeychainStore.read(account:)
  ) -> CircleCISettings? {
    let slugs = (defaults.string(forKey: projectSlugs) ?? "").split(whereSeparator: \.isNewline).map(String.init)
    guard let token = readToken(KeychainStore.circleciTokenAccount), !token.isEmpty else { return nil }
    let settings = CircleCISettings(apiToken: token, projectSlugs: slugs)
    return settings.projectSlugs.isEmpty ? nil : settings
  }
}

enum GitHubSettingsKeys {
  static let organizations = "githubOrganizations"

  static func loadOrganizations(defaults: UserDefaults = .standard) -> [String] {
    (defaults.string(forKey: organizations) ?? "").split(whereSeparator: \.isNewline).map(String.init)
  }
}

@MainActor @Observable final class QueueStore {
  private(set) var sections: [QueueSection] = []
  // Settable inside the module so App tests can drive the menu bar icon without a refresh.
  var menuBarState: MenuBarState = .normal
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

  private let tokenProvider: any GitHubTokenProvider
  private let transport: any HTTPTransport
  private let cache: SourceCache
  private let loadJiraSettings: () -> JiraSettings?
  private let loadCircleCISettings: () -> CircleCISettings?
  private let loadGitHubOrganizations: () -> [String]
  private var pollingTask: Task<Void, Never>?
  private var activationObserver: NSObjectProtocol?

  init(
    tokenProvider: any GitHubTokenProvider = GhCLITokenProvider(),
    transport: any HTTPTransport = URLSessionTransport(),
    cacheDirectory: URL = URL.applicationSupportDirectory.appendingPathComponent("Tower", isDirectory: true),
    loadJiraSettings: @escaping () -> JiraSettings? = { JiraSettingsKeys.load() },
    loadCircleCISettings: @escaping () -> CircleCISettings? = { CircleCISettingsKeys.load() },
    loadGitHubOrganizations: @escaping () -> [String] = { GitHubSettingsKeys.loadOrganizations() }
  ) {
    self.tokenProvider = tokenProvider
    self.transport = transport
    cache = SourceCache(directory: cacheDirectory)
    self.loadJiraSettings = loadJiraSettings
    self.loadCircleCISettings = loadCircleCISettings
    self.loadGitHubOrganizations = loadGitHubOrganizations
  }

  var todaySummary: (reviews: Int, merges: Int)? {
    githubSnapshot.map { ($0.reviewsSubmittedToday, $0.mergedToday) }
  }

  func start() {
    guard pollingTask == nil else { return }
    loadCache()
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

  func loadCache() {
    if let cached = cache.load(GitHubSnapshot.self, name: "github") {
      githubSnapshot = cached.value
      githubFetchedAt = cached.fetchedAt
    }
    if let cached = cache.load([JiraTicket].self, name: "jira") {
      jiraTickets = cached.value
      jiraFetchedAt = cached.fetchedAt
    }
    // Without CircleCI settings, an old cache would show a stale fetch age.
    if loadCircleCISettings() != nil, let cached = cache.load([Pipeline].self, name: "circleci") {
      pipelines = cached.value
      circleciFetchedAt = cached.fetchedAt
    }
    rebuild()
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
      || circleciStatus == .failed(.authentication)
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    let now = Date()
    let githubClient = GitHubClient(tokenProvider: tokenProvider, transport: transport, owners: loadGitHubOrganizations())
    let jiraClient = JiraClient(settings: loadJiraSettings(), transport: transport)
    let circleciClient = CircleCIClient(settings: loadCircleCISettings(), transport: transport)
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
      if failure == .notConfigured {
        pipelines = nil
        circleciFetchedAt = nil
      }
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
