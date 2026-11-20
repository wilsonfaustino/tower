import AppKit
import Core
import Observation

// Runs the Homebrew update for the Update button and relaunches the app when a newer version is on disk.
@MainActor
@Observable
final class AppUpdater {
  enum State {
    case unknown, preparing, unavailable, ready, checking, updating, failed, noNewVersion
  }

  private(set) var state = State.unknown
  @ObservationIgnored private(set) var brewPath: String?
  @ObservationIgnored private let findBrews: () -> [String]

  init(findBrews: @escaping () -> [String] = { BrewUpgrade.findBrews() }) {
    self.findBrews = findBrews
  }

  // Runs once per launch. .preparing is set before the first await, so a second control on screen cannot start a second check.
  func prepareIfNeeded() async {
    guard state == .unknown else { return }
    state = .preparing
    // Demo mode never runs brew, so the Update button cannot install a real version.
    guard !DemoLaunch.isActive else {
      state = .unavailable
      return
    }
    var hasUnfinishedCheck = false
    for candidateBrewPath in findBrews() {
      switch await BrewUpgrade.isInstalledByCask(brewPath: candidateBrewPath, caskFullName: BrewUpgrade.caskFullName) {
      case true:
        brewPath = candidateBrewPath
        state = .ready
        return
      case false: continue
      case nil: hasUnfinishedCheck = true
      }
    }
    // A brew that did not finish may own the cask; the next time the controls appear, they ask again.
    state = hasUnfinishedCheck ? .unknown : .unavailable
  }

  var statusMessage: String? {
    switch state {
    case .failed: "Update failed."
    case .noNewVersion: "No new version yet."
    default: nil
    }
  }

  func update() async {
    guard [.ready, .failed, .noNewVersion].contains(state), let brewPath else { return }
    state = .checking
    guard await BrewUpgrade.updateHomebrew(brewPath: brewPath) == .succeeded else {
      state = .failed
      return
    }
    state = .updating
    guard await BrewUpgrade.upgrade(brewPath: brewPath, caskFullName: BrewUpgrade.caskFullName) == .succeeded else {
      state = .failed
      return
    }
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    guard BrewUpgrade.installedVersionIsNewer(bundleURL: Bundle.main.bundleURL, currentVersion: currentVersion) else {
      state = .noNewVersion
      return
    }
    let relauncher = Process()
    relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
    relauncher.arguments = BrewUpgrade.relaunchArguments(
      processIdentifier: ProcessInfo.processInfo.processIdentifier,
      bundlePath: Bundle.main.bundlePath
    )
    do {
      try relauncher.run()
    } catch {
      state = .failed
      return
    }
    NSApplication.shared.terminate(nil)
  }
}
