public enum MenuBarState: Equatable, Sendable {
  case normal
  case urgent(count: Int)
  case failing(count: Int)

  public init(sections: [QueueSection]) {
    let fixCount = sections.first { $0.kind == .fix }?.items.count ?? 0
    let urgentCount = sections.flatMap(\.items).flatMap { [$0] + $0.children }.filter { $0.badge?.variant == .urgent }.count
    if fixCount > 0 {
      self = .failing(count: fixCount)
    } else if urgentCount > 0 {
      self = .urgent(count: urgentCount)
    } else {
      self = .normal
    }
  }

  public var imageName: String {
    switch self {
    case .normal: "MenuBarCab"
    case .urgent: "MenuBarCabUrgent"
    case .failing: "MenuBarCabFailing"
    }
  }

  public var accessibilityLabel: String {
    switch self {
    case .normal: "Tower"
    case .urgent(let count): "Tower, \(count) urgent \(count == 1 ? "item" : "items")"
    case .failing(let count): "Tower, \(count) \(count == 1 ? "item" : "items") to fix"
    }
  }

  public var countText: String? {
    switch self {
    case .normal: nil
    case .urgent(let count), .failing(let count): String(count)
    }
  }
}
