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
  // JSON for team slug to its allowed PR author logins.
  static let teamAuthorFilters = "githubTeamAuthorFilters"
  static let reviewRequestScope = "githubReviewRequestScope"

  static func loadOrganizations(defaults: UserDefaults = .standard) -> [String] {
    (defaults.string(forKey: organizations) ?? "").split(whereSeparator: \.isNewline).map(String.init)
  }

  static func loadReviewRequestScope(defaults: UserDefaults) -> ReviewRequestScope {
    defaults.string(forKey: reviewRequestScope).flatMap(ReviewRequestScope.init(rawValue:)) ?? .directAndTeam
  }

  static func loadTeamAuthorLogins(defaults: UserDefaults) -> [String: [String]] {
    guard let data = defaults.data(forKey: teamAuthorFilters) else { return [:] }
    return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
  }

  static func saveTeamAuthorLogins(_ loginsByTeam: [String: [String]], defaults: UserDefaults) {
    defaults.set(try? JSONEncoder().encode(loginsByTeam), forKey: teamAuthorFilters)
  }

  // Returns the sorted logins with the typed login added, or nil when the typed text is not a valid login.
  static func logins(_ logins: [String], adding typedLogin: String) -> [String]? {
    let login = typedLogin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard isValidGitHubUserLogin(login) else { return nil }
    return Set(logins).union([login]).sorted()
  }
}

enum PanelSettingsKeys {
  static let layout = "panelLayout"
}

enum DismissalKeys {
  static let dismissedPipelines = "dismissedPipelines"
  static let dismissedPullRequests = "dismissedPullRequests"

  static func load<Element: Codable & Hashable>(_ key: String, defaults: UserDefaults) -> Set<Element> {
    guard let data = defaults.data(forKey: key) else { return [] }
    return (try? JSONDecoder().decode(Set<Element>.self, from: data)) ?? []
  }

  static func save<Element: Codable & Hashable>(_ dismissals: Set<Element>, key: String, defaults: UserDefaults) {
    defaults.set(try? JSONEncoder().encode(dismissals), forKey: key)
  }
}

// The last dismissal, which the undo bar and Cmd-Z can take back. The id tells one dismissal of a row from the next.
struct UndoableDismissal: Equatable {
  let id = UUID()
  let dismissal: Dismissal
  let title: String
  let expiresAt: Date
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
  private var isRefreshQueued = false
  private(set) var jiraTickets: [JiraTicket]?
  private(set) var pipelines: [Pipeline]?
  private(set) var dismissedPipelines: Set<PipelineDismissal>
  private(set) var dismissedPullRequests: Set<PullRequestDismissal>
  private(set) var lastDismissal: UndoableDismissal?
  // Team slug to sorted, lowercased PR author logins. A team with no entry has no filter. An empty list hides
  // every request to that team.
  var teamAuthorLogins: [String: [String]] {
    didSet {
      saveTeamAuthorLogins()
      rebuild()
    }
  }
  // The next refresh sends the search for the new scope. Until then the cached requests are filtered to it.
  var reviewRequestScope: ReviewRequestScope {
    didSet {
      saveReviewRequestScope()
      rebuild()
    }
  }
  let undoDuration: Duration
  private var undoExpiryTask: Task<Void, Never>?

  private let tokenProvider: any GitHubTokenProvider
  private let transport: any HTTPTransport
  private let cache: SourceCache
  private let loadJiraSettings: () -> JiraSettings?
  private let loadCircleCISettings: () -> CircleCISettings?
  private let loadGitHubOrganizations: () -> [String]
  private let notifier: (any Notifier)?
  private let loadEnabledNotificationKinds: () -> Set<NotificationEventKind>
  // Set only by a successful fetch in this app run, never by the cache, so launch does not post old changes.
  // Each baseline keeps the settings it was fetched with. New settings start a new baseline that posts nothing.
  private var githubNotificationBaseline:
    (snapshot: GitHubSnapshot, organizations: [String], reviewRequestScope: ReviewRequestScope)?
  private var circleciNotificationBaseline: (pipelines: [Pipeline], settings: CircleCISettings?)?
  private let defaults: UserDefaults
  private var pollingTask: Task<Void, Never>?
  #if DEBUG
    // Settable inside the module so App tests can check that demo mode posts nothing.
    var demoScenario = DemoLaunch.scenario
  #endif
  #if DEBUG
    private var hasPostedDemoChanges = false
  #endif
  private var activationObserver: NSObjectProtocol?

  init(
    tokenProvider: any GitHubTokenProvider = GhCLITokenProvider(),
    transport: any HTTPTransport = URLSessionTransport(),
    cacheDirectory: URL = URL.applicationSupportDirectory.appendingPathComponent("Tower", isDirectory: true),
    loadJiraSettings: @escaping () -> JiraSettings? = { JiraSettingsKeys.load() },
    loadCircleCISettings: @escaping () -> CircleCISettings? = { CircleCISettingsKeys.load() },
    loadGitHubOrganizations: @escaping () -> [String] = { GitHubSettingsKeys.loadOrganizations() },
    notifier: (any Notifier)? = nil,
    loadEnabledNotificationKinds: @escaping () -> Set<NotificationEventKind> = { NotificationSettingsKeys.enabledKinds() },
    defaults: UserDefaults = .standard,
    undoDuration: Duration = .seconds(5)
  ) {
    self.tokenProvider = tokenProvider
    self.transport = transport
    cache = SourceCache(directory: cacheDirectory)
    self.loadJiraSettings = loadJiraSettings
    self.loadCircleCISettings = loadCircleCISettings
    self.loadGitHubOrganizations = loadGitHubOrganizations
    self.notifier = notifier
    self.loadEnabledNotificationKinds = loadEnabledNotificationKinds
    self.defaults = defaults
    self.undoDuration = undoDuration
    dismissedPipelines = DismissalKeys.load(DismissalKeys.dismissedPipelines, defaults: defaults)
    dismissedPullRequests = DismissalKeys.load(DismissalKeys.dismissedPullRequests, defaults: defaults)
    teamAuthorLogins = GitHubSettingsKeys.loadTeamAuthorLogins(defaults: defaults)
    reviewRequestScope = GitHubSettingsKeys.loadReviewRequestScope(defaults: defaults)
  }

  // A team with a filter stays listed when no request for it is open, so its filter can still change.
  var filterableTeamSlugs: [String] {
    let requestedTeamSlugs = (githubSnapshot?.reviewRequests ?? []).flatMap(\.requestedTeamSlugs)
    return Set(requestedTeamSlugs).union(teamAuthorLogins.keys).sorted()
  }

  private var teamAuthorFilters: TeamAuthorFilters {
    TeamAuthorFilters(allowedAuthorsByTeam: teamAuthorLogins.mapValues(Set.init))
  }

  var todaySummary: (reviews: Int, merges: Int)? {
    githubSnapshot.map { ($0.reviewsSubmittedToday, $0.mergedToday) }
  }

  func start() {
    #if DEBUG
      if let demoScenario {
        applyDemo(demoScenario)
        return
      }
    #endif
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
    // Without settings, an old cache would show stale data and a stale fetch age.
    if loadJiraSettings() != nil, let cached = cache.load([JiraTicket].self, name: "jira") {
      jiraTickets = cached.value
      jiraFetchedAt = cached.fetchedAt
    }
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
    #if DEBUG
      if let demoScenario {
        applyDemo(demoScenario)
        applyDemoChanges(demoScenario)
        return
      }
    #endif
    // A refresh asked for during a fetch can carry new settings, so it runs once that fetch ends.
    guard !isRefreshing else {
      isRefreshQueued = true
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }
    repeat {
      isRefreshQueued = false
      await fetchSources()
    } while isRefreshQueued
  }

  private func fetchSources() async {
    let now = Date()
    let githubOrganizations = loadGitHubOrganizations()
    let reviewRequestScope = reviewRequestScope
    let circleciSettings = loadCircleCISettings()
    let githubClient = GitHubClient(
      tokenProvider: tokenProvider, transport: transport, owners: githubOrganizations,
      reviewRequestScope: reviewRequestScope)
    let jiraClient = JiraClient(settings: loadJiraSettings(), transport: transport)
    let circleciClient = CircleCIClient(settings: circleciSettings, transport: transport)
    async let githubResult = Result { () async throws(SourceFailure) -> GitHubSnapshot in try await githubClient.fetch(now: now) }
    async let jiraResult = Result { () async throws(SourceFailure) -> [JiraTicket] in try await jiraClient.fetch() }
    async let circleciResult = Result { () async throws(SourceFailure) -> [Pipeline] in try await circleciClient.fetch(now: now) }

    switch await githubResult {
    case .success(let snapshot):
      githubSnapshot = snapshot
      githubFetchedAt = now
      githubStatus = .ok
      try? cache.save(Cached(value: snapshot, fetchedAt: now), name: "github")
      // Only a successful fetch prunes, so a failed one does not drop every dismissal. A direct only fetch leaves out
      // team requests, so it does not prune either.
      let keptPullRequestDismissals =
        reviewRequestScope == .directAndTeam
        ? prunedDismissals(dismissedPullRequests, reviewRequests: snapshot.reviewRequests) : dismissedPullRequests
      if keptPullRequestDismissals != dismissedPullRequests {
        dismissedPullRequests = keptPullRequestDismissals
        DismissalKeys.save(keptPullRequestDismissals, key: DismissalKeys.dismissedPullRequests, defaults: defaults)
      }
      if self.reviewRequestScope != reviewRequestScope {
        // The scope changed during the fetch. The next refresh sets a new baseline for the new scope.
        githubNotificationBaseline = nil
      } else if let baseline = githubNotificationBaseline, baseline.organizations == githubOrganizations,
        baseline.reviewRequestScope == reviewRequestScope, baseline.snapshot.viewerLogin == snapshot.viewerLogin
      {
        post(
          notificationEvents(
            previous: baseline.snapshot, current: snapshot, dismissedPullRequests: dismissedPullRequests,
            teamAuthorFilters: teamAuthorFilters, reviewRequestScope: reviewRequestScope))
        githubNotificationBaseline = (
          keepingMissingPullRequests(of: baseline.snapshot, in: snapshot), githubOrganizations, reviewRequestScope
        )
      } else {
        githubNotificationBaseline = (snapshot, githubOrganizations, reviewRequestScope)
      }
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
      if failure == .notConfigured {
        jiraTickets = nil
        jiraFetchedAt = nil
        cache.remove(name: "jira")
      }
    }
    switch await circleciResult {
    case .success(let fetchedPipelines):
      pipelines = fetchedPipelines
      circleciFetchedAt = now
      circleciStatus = .ok
      try? cache.save(Cached(value: fetchedPipelines, fetchedAt: now), name: "circleci")
      // Only a successful fetch prunes, so a failed one does not drop every dismissal.
      let keptDismissals = prunedDismissals(dismissedPipelines, pipelines: fetchedPipelines, now: now)
      if keptDismissals != dismissedPipelines {
        dismissedPipelines = keptDismissals
        DismissalKeys.save(keptDismissals, key: DismissalKeys.dismissedPipelines, defaults: defaults)
      }
      // The token picks the account whose pipelines "mine" returns, so a new token is a new baseline too.
      let previousBaseline = circleciNotificationBaseline.flatMap { $0.settings == circleciSettings ? $0.pipelines : nil }
      if let previousBaseline {
        post(notificationEvents(previous: previousBaseline, current: fetchedPipelines, dismissedPipelines: dismissedPipelines))
      }
      circleciNotificationBaseline = (
        notificationBaseline(previous: previousBaseline ?? [], current: fetchedPipelines), circleciSettings
      )
    case .failure(let failure):
      circleciStatus = .failed(failure)
      if failure == .notConfigured {
        pipelines = nil
        circleciFetchedAt = nil
        // A later setup starts a new baseline, so its first fetch posts nothing.
        circleciNotificationBaseline = nil
      }
    }
    rebuild()
  }

  // GraphQL can drop a PR from one response with an error. Its last known state stays, so its return posts nothing.
  private func keepingMissingPullRequests(of previous: GitHubSnapshot, in current: GitHubSnapshot) -> GitHubSnapshot {
    var baseline = current
    let authoredURLs = Set(current.authoredPullRequests.map(\.url))
    baseline.authoredPullRequests += previous.authoredPullRequests.filter { !authoredURLs.contains($0.url) }
    let requestedURLs = Set(current.reviewRequests.map(\.url))
    baseline.reviewRequests += previous.reviewRequests.filter { !requestedURLs.contains($0.url) }
    return baseline
  }

  private func post(_ events: [NotificationEvent]) {
    guard let notifier, !events.isEmpty else { return }
    let enabledKinds = loadEnabledNotificationKinds()
    for event in events where enabledKinds.contains(event.kind) {
      notifier.post(event)
    }
  }

  func dismiss(_ item: QueueItem) {
    guard let dismissal = item.dismissal else { return }
    switch dismissal {
    case .pipeline(let pipelineDismissal): dismissedPipelines.insert(pipelineDismissal)
    case .pullRequest(let pullRequestDismissal): dismissedPullRequests.insert(pullRequestDismissal)
    }
    let undoableDismissal = UndoableDismissal(
      dismissal: dismissal, title: item.title, expiresAt: Date().addingTimeInterval(undoDuration.timeInterval))
    lastDismissal = undoableDismissal
    // The store owns the deadline, so closing the panel does not keep an old undo alive.
    undoExpiryTask?.cancel()
    undoExpiryTask = Task { [weak self, undoDuration] in
      guard (try? await Task.sleep(for: undoDuration)) != nil else { return }
      self?.expireUndo(undoableDismissal)
    }
    saveDismissals()
  }

  func undoLastDismissal() {
    guard let lastDismissal else { return }
    switch lastDismissal.dismissal {
    case .pipeline(let pipelineDismissal): dismissedPipelines.remove(pipelineDismissal)
    case .pullRequest(let pullRequestDismissal): dismissedPullRequests.remove(pullRequestDismissal)
    }
    self.lastDismissal = nil
    undoExpiryTask?.cancel()
    saveDismissals()
  }

  // Called when the undo deadline passes. A newer dismissal keeps its own undo.
  func expireUndo(_ undoableDismissal: UndoableDismissal) {
    if lastDismissal == undoableDismissal { lastDismissal = nil }
  }

  private func saveDismissals() {
    #if DEBUG
      if demoScenario != nil {
        rebuild()
        return
      }
    #endif
    DismissalKeys.save(dismissedPipelines, key: DismissalKeys.dismissedPipelines, defaults: defaults)
    DismissalKeys.save(dismissedPullRequests, key: DismissalKeys.dismissedPullRequests, defaults: defaults)
    rebuild()
  }

  private func saveTeamAuthorLogins() {
    #if DEBUG
      if demoScenario != nil { return }
    #endif
    GitHubSettingsKeys.saveTeamAuthorLogins(teamAuthorLogins, defaults: defaults)
  }

  private func saveReviewRequestScope() {
    #if DEBUG
      if demoScenario != nil { return }
    #endif
    defaults.set(reviewRequestScope.rawValue, forKey: GitHubSettingsKeys.reviewRequestScope)
  }

  #if DEBUG
    // The notify scenario shows its changed data from the first refresh on. Only that refresh posts.
    private func applyDemoChanges(_ scenario: DemoScenario) {
      guard let previousSnapshot = scenario.githubSnapshot, let changedSnapshot = scenario.changedGitHubSnapshot,
        let previousPipelines = scenario.pipelines, let changedPipelines = scenario.changedPipelines
      else { return }
      if !hasPostedDemoChanges {
        hasPostedDemoChanges = true
        post(
          notificationEvents(
            previous: previousSnapshot, current: changedSnapshot, dismissedPullRequests: dismissedPullRequests,
            teamAuthorFilters: teamAuthorFilters, reviewRequestScope: reviewRequestScope))
        post(notificationEvents(previous: previousPipelines, current: changedPipelines, dismissedPipelines: dismissedPipelines))
      }
      githubSnapshot = changedSnapshot
      pipelines = changedPipelines
      rebuild()
    }

    // Demo data never touches the cache, the network or saved dismissals.
    private func applyDemo(_ scenario: DemoScenario) {
      let now = Date()
      githubSnapshot = scenario.githubSnapshot
      jiraTickets = scenario.jiraTickets
      pipelines = scenario.pipelines
      githubFetchedAt = scenario.githubSnapshot.map { _ in now }
      jiraFetchedAt = scenario.jiraTickets.map { _ in now }
      circleciFetchedAt = scenario.pipelines.map { _ in now }
      githubStatus = scenario.githubStatus
      jiraStatus = scenario.jiraStatus
      circleciStatus = scenario.circleciStatus
      rebuild()
    }
  #endif

  private func rebuild() {
    let input = QueueInput(
      viewerLogin: githubSnapshot?.viewerLogin ?? "",
      authoredPullRequests: githubSnapshot?.authoredPullRequests ?? [],
      reviewRequests: githubSnapshot?.reviewRequests ?? [],
      jiraTickets: jiraTickets ?? [],
      pipelines: pipelines ?? [], dismissedPipelines: dismissedPipelines, dismissedPullRequests: dismissedPullRequests,
      mergedPullRequests: githubSnapshot?.recentlyMergedPullRequests ?? [], teamAuthorFilters: teamAuthorFilters,
      reviewRequestScope: reviewRequestScope)
    sections = buildQueue(input, now: Date())
    menuBarState = MenuBarState(sections: sections)
  }
}

extension Duration {
  var timeInterval: TimeInterval {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
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
