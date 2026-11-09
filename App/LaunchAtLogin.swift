import Observation
import ServiceManagement

protocol LoginItem {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
}

extension SMAppService: LoginItem {}

// Returns the error text when macOS rejects the change, or nil when it succeeds.
func setLaunchAtLogin(_ isOn: Bool, loginItem: LoginItem = SMAppService.mainApp) -> String? {
  do {
    if isOn {
      try loginItem.register()
    } else {
      try loginItem.unregister()
    }
    return nil
  } catch {
    return "Can’t change login item: \(error.localizedDescription)"
  }
}

// A registered item that waits for approval still counts as on, so the toggle matches System Settings.
func launchAtLoginIsOn(status: SMAppService.Status) -> Bool {
  status == .enabled || status == .requiresApproval
}

func launchAtLoginStatusText(status: SMAppService.Status) -> String? {
  status == .requiresApproval ? "Approve Tower in System Settings > General > Login Items." : nil
}

// Settings binds the toggle to isOn. Each change reads the status back, so a failed change leaves the toggle off.
@MainActor @Observable final class LaunchAtLoginModel {
  private let loginItem: LoginItem
  private(set) var status: SMAppService.Status
  private(set) var error: String?

  init(loginItem: LoginItem = SMAppService.mainApp) {
    self.loginItem = loginItem
    status = loginItem.status
  }

  var isOn: Bool {
    get { launchAtLoginIsOn(status: status) }
    set {
      error = setLaunchAtLogin(newValue, loginItem: loginItem)
      status = loginItem.status
    }
  }

  // Reads a change made in System Settings while Tower's Settings window stays open.
  func refresh() {
    error = nil
    status = loginItem.status
  }

  // macOS can reject register() and still need approval, so the error and the approval hint can show together.
  var caption: String? {
    let lines = [error, launchAtLoginStatusText(status: status)].compactMap { $0 }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }
}
