import Foundation
import ServiceManagement
import Testing

@testable import Tower

private struct LoginItemFailure: LocalizedError {
  var errorDescription: String? { "Operation not permitted" }
}

private final class StubLoginItem: LoginItem {
  var status: SMAppService.Status
  var failure: Error?
  private(set) var calls: [String] = []

  init(status: SMAppService.Status, failure: Error? = nil) {
    self.status = status
    self.failure = failure
  }

  func register() throws {
    calls.append("register")
    if let failure { throw failure }
    status = .enabled
  }

  func unregister() throws {
    calls.append("unregister")
    if let failure { throw failure }
    status = .notRegistered
  }
}

struct LaunchAtLoginTests {
  @Test func turningOnRegistersTower() {
    let loginItem = StubLoginItem(status: .notRegistered)
    #expect(setLaunchAtLogin(true, loginItem: loginItem) == nil)
    #expect(loginItem.calls == ["register"])
  }

  @Test func turningOffUnregistersTower() {
    let loginItem = StubLoginItem(status: .enabled)
    #expect(setLaunchAtLogin(false, loginItem: loginItem) == nil)
    #expect(loginItem.calls == ["unregister"])
  }

  @Test func failureReturnsTheErrorText() {
    let loginItem = StubLoginItem(status: .notRegistered, failure: LoginItemFailure())
    #expect(setLaunchAtLogin(true, loginItem: loginItem) == "Can’t change login item: Operation not permitted")
  }

  @Test(arguments: [
    (SMAppService.Status.enabled, true),
    (.requiresApproval, true),
    (.notRegistered, false),
    (.notFound, false),
  ])
  func toggleIsOnWhenTowerIsRegistered(status: SMAppService.Status, isOn: Bool) {
    #expect(launchAtLoginIsOn(status: status) == isOn)
  }

  @Test func approvalTextShowsOnlyWhenMacOSNeedsApproval() {
    #expect(launchAtLoginStatusText(status: .requiresApproval) == "Approve Tower in System Settings > General > Login Items.")
    #expect(launchAtLoginStatusText(status: .enabled) == nil)
    #expect(launchAtLoginStatusText(status: .notRegistered) == nil)
  }
}

@MainActor struct LaunchAtLoginModelTests {
  @Test func readsTheStatusOnInit() {
    let model = LaunchAtLoginModel(loginItem: StubLoginItem(status: .enabled))
    #expect(model.isOn)
    #expect(model.caption == nil)
  }

  @Test func turningOnRegistersAndReadsTheNewStatus() {
    let loginItem = StubLoginItem(status: .notRegistered)
    let model = LaunchAtLoginModel(loginItem: loginItem)
    model.isOn = true
    #expect(loginItem.calls == ["register"])
    #expect(model.isOn)
    #expect(model.caption == nil)
  }

  @Test func failureKeepsTheToggleOffAndShowsTheError() {
    let model = LaunchAtLoginModel(loginItem: StubLoginItem(status: .notRegistered, failure: LoginItemFailure()))
    model.isOn = true
    #expect(!model.isOn)
    #expect(model.caption == "Can’t change login item: Operation not permitted")
  }

  @Test func captionAsksForApprovalWhenMacOSNeedsIt() {
    let model = LaunchAtLoginModel(loginItem: StubLoginItem(status: .requiresApproval))
    #expect(model.isOn)
    #expect(model.caption == "Approve Tower in System Settings > General > Login Items.")
  }
}
