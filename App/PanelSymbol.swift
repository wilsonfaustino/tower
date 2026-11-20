// Custom SF Symbols in Assets.xcassets, converted from Phosphor Bold (MIT license) with SwiftDraw.
enum PanelSymbol: String, CaseIterable {
  case refresh = "ph-arrow-clockwise"
  case settings = "ph-gear-six"
  case openArrow = "ph-arrow-up-right"
  case disclosure = "ph-caret-right"
  case threads = "ph-chat-circle"
  case approvalGiven = "ph-check-circle-fill"
  case approvalMissing = "ph-circle"
  case approvalErase = "ph-circle-fill"
  case clearSkies = "ph-seal-check"
  case nothingWaiting = "ph-airplane-in-flight"
  case offline = "ph-wifi-slash"
  case updateFailed = "ph-warning"
  case tokenMissing = "ph-key"
  case trash = "ph-trash"
}

// Symbols for the status item context menu, from the same asset catalog.
enum MenuSymbol: String, CaseIterable {
  case refresh = "ph-arrow-clockwise"
  case settings = "ph-gear"
  case checkForUpdates = "ph-arrow-circle-down"
  case quit = "ph-power"
}

// Symbols for the Settings window, from the same asset catalog.
enum SettingsSymbol: String, CaseIterable {
  case general = "ph-gear"
  // Drawn for the Settings design canvas in the Phosphor style, not part of the Phosphor set.
  case github = "settings-github"
  case jira = "settings-jira"
  case circleci = "settings-circleci"
  case about = "ph-info"
  case connected = "ph-check-circle-fill"
  case notSetUp = "ph-minus-circle"
  case failed = "ph-warning"
  case star = "ph-star"
  case coffee = "ph-coffee"
  case openArrow = "ph-arrow-up-right"
}
