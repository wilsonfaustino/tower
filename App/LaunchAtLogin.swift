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
