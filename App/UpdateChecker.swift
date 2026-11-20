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
  @ObservationIgnored private var inFlightCheck: Task<UpdateCheckResult, Never>?
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
      while !Task.isCancelled, self != nil {
        _ = await self?.checkNow()
        try? await Task.sleep(for: Self.checkInterval)
      }
    }
  }

  // The menu item calls this directly, so it skips the once-a-day wait. A check that starts while another
  // runs gets the same result, so a slow older response cannot overwrite a newer one.
  func checkNow() async -> UpdateCheckResult {
    #if DEBUG
      // Demo mode makes no network calls.
      if let demoScenario { return demoResult(demoScenario) }
    #endif
    if let inFlightCheck { return await inFlightCheck.value }
    let check = Task { await fetchResult() }
    inFlightCheck = check
    let result = await check.value
    inFlightCheck = nil
    return result
  }

  #if DEBUG
    private func demoResult(_ demoScenario: DemoScenario) -> UpdateCheckResult {
      if let availableVersion = demoScenario.availableVersion { return .newer(availableVersion) }
      guard demoScenario.name != .offline, let currentVersion else { return .failed }
      return .upToDate(currentVersion)
    }
  #endif

  private func fetchResult() async -> UpdateCheckResult {
    guard let currentVersion else { return .failed }
    do {
      let newerVersion = try await fetchNewerVersion(currentVersion)
      availableVersion = newerVersion
      return newerVersion.map { .newer($0) } ?? .upToDate(currentVersion)
    } catch {
      // Offline, rate limited, no release yet or a tag that does not parse: keep the last result.
      return .failed
    }
  }
}
