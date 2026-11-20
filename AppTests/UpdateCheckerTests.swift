import Core
import Foundation
import Testing

@testable import Tower

private struct FetchFailure: Error {}

// Tests that build a controller get a checker that never reaches GitHub.
@MainActor func makeOfflineUpdateChecker(
  fetchNewerVersion: @escaping @Sendable (String) async throws -> String? = { _ in throw URLError(.notConnectedToInternet) }
) -> UpdateChecker {
  let checker = UpdateChecker(currentVersion: "0.4.0", fetchNewerVersion: fetchNewerVersion)
  checker.demoScenario = nil
  return checker
}

@MainActor struct UpdateCheckerTests {
  private func makeChecker(
    currentVersion: String? = "0.4.0", fetchNewerVersion: @escaping @Sendable (String) async throws -> String?
  ) -> UpdateChecker {
    let checker = UpdateChecker(currentVersion: currentVersion, fetchNewerVersion: fetchNewerVersion)
    checker.demoScenario = nil
    return checker
  }

  @Test func newerReleaseSetsTheAvailableVersion() async {
    let checker = makeChecker { _ in "0.5.0" }
    #expect(await checker.checkNow() == .newer("0.5.0"))
    #expect(checker.availableVersion == "0.5.0")
  }

  @Test func checkSendsTheRunningVersion() async {
    let checker = makeChecker { currentVersion in currentVersion == "0.4.0" ? "0.5.0" : nil }
    #expect(await checker.checkNow() == .newer("0.5.0"))
  }

  @Test func currentReleaseClearsTheAvailableVersion() async {
    let isReleased = LockedFlag()
    let checker = makeChecker { _ in isReleased.value ? nil : "0.5.0" }
    _ = await checker.checkNow()
    isReleased.value = true
    #expect(await checker.checkNow() == .upToDate("0.4.0"))
    #expect(checker.availableVersion == nil)
  }

  @Test func failedCheckKeepsTheLastResult() async {
    let shouldFail = LockedFlag()
    let checker = makeChecker { _ in
      if shouldFail.value { throw FetchFailure() }
      return "0.5.0"
    }
    _ = await checker.checkNow()
    shouldFail.value = true
    #expect(await checker.checkNow() == .failed)
    #expect(checker.availableVersion == "0.5.0")
  }

  @Test func missingBundleVersionFailsWithoutAFetch() async {
    let fetchCount = LockedCounter()
    let checker = makeChecker(currentVersion: nil) { _ in
      fetchCount.increment()
      return "0.5.0"
    }
    #expect(await checker.checkNow() == .failed)
    #expect(fetchCount.value == 0)
  }

  @Test func demoModeMakesNoNetworkCall() async {
    let fetchCount = LockedCounter()
    let checker = makeChecker { _ in
      fetchCount.increment()
      return "0.5.0"
    }
    checker.demoScenario = DemoScenario(name: .update, now: .now)
    checker.start()
    #expect(checker.availableVersion == "1.0.0")
    #expect(await checker.checkNow() == .newer("1.0.0"))
    checker.demoScenario = DemoScenario(name: .typical, now: .now)
    #expect(await checker.checkNow() == .upToDate("0.4.0"))
    checker.demoScenario = DemoScenario(name: .offline, now: .now)
    #expect(await checker.checkNow() == .failed)
    #expect(fetchCount.value == 0)
  }

  @Test func overlappingChecksShareOneFetch() async {
    let fetchCount = LockedCounter()
    let (releaseGate, openGate) = AsyncStream<Void>.makeStream()
    let checker = makeChecker { _ in
      fetchCount.increment()
      for await _ in releaseGate {}
      return "0.5.0"
    }
    let firstCheck = Task { await checker.checkNow() }
    while fetchCount.value < 1 { await Task.yield() }
    // checkNow joins the pending check before its first suspension, in the same main actor turn that sets the flag.
    let secondStarted = LockedFlag()
    let secondCheck = Task {
      secondStarted.value = true
      return await checker.checkNow()
    }
    while !secondStarted.value { await Task.yield() }
    openGate.finish()
    #expect(await [firstCheck.value, secondCheck.value] == [.newer("0.5.0"), .newer("0.5.0")])
    #expect(fetchCount.value == 1)
    _ = await checker.checkNow()
    #expect(fetchCount.value == 2)
  }
}

final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue = false
  var value: Bool {
    get { lock.withLock { storedValue } }
    set { lock.withLock { storedValue = newValue } }
  }
}

final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func increment() { lock.withLock { count += 1 } }
}
