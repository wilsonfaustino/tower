import Core
import Foundation
import Observation

enum UpdateCheckResult: Equatable {
  case newer(String)
  case upToDate(String)
  case failed
}

// Asks GitHub for the latest release at launch and then once a day. The panel and Settings > About show
// the newer version. A failed check keeps the last result and shows nothing.
@MainActor @Observable final class UpdateChecker {
  static let checkInterval: Duration = .seconds(24 * 60 * 60)

  private(set) var availableVersion: String?
  let appUpdater = AppUpdater()
  @ObservationIgnored private let currentVersion: String?
  @ObservationIgnored private let fetchNewerVersion: @Sendable (String) async throws -> String?
  @ObservationIgnored private var checkingTask: Task<Void, Never>?
  #if DEBUG
    // Settable inside the module so App tests can check that demo mode makes no network call.
    @ObservationIgnored var demoScenario = DemoLaunch.scenario
  #endif

  init(
    currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
    fetchNewerVersion: @escaping @Sendable (String) async throws -> String? = {
      try await ReleaseCheck.fetchNewerVersion(currentVersion: $0)
    }
  ) {
    self.currentVersion = currentVersion
    self.fetchNewerVersion = fetchNewerVersion
  }

  func start() {
    #if DEBUG
      if let demoScenario {
        availableVersion = demoScenario.availableVersion
        return
      }
    #endif
    guard checkingTask == nil else { return }
    checkingTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        _ = await self.checkNow()
        try? await Task.sleep(for: Self.checkInterval)
      }
    }
  }

  // The menu item calls this directly, so it skips the once-a-day wait.
  func checkNow() async -> UpdateCheckResult {
    #if DEBUG
      // Demo mode makes no network calls.
      if let demoScenario { return demoScenario.availableVersion.map { .newer($0) } ?? .failed }
    #endif
    guard let currentVersion else { return .failed }
    do {
      let newerVersion = try await fetchNewerVersion(currentVersion)
      availableVersion = newerVersion
      return newerVersion.map { .newer($0) } ?? .upToDate(currentVersion)
    } catch {
      // Offline, rate limited or no release yet: keep the last result.
      return .failed
    }
  }
}
