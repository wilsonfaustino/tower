import Foundation

public enum SourceStatus: Equatable, Sendable {
  case idle
  case ok
  case failed(SourceFailure)
}

public struct PanelSource: Equatable, Sendable {
  public let status: SourceStatus
  public let hasData: Bool
  public let fetchedAt: Date?
  public let staleLabel: String

  public init(status: SourceStatus, hasData: Bool, fetchedAt: Date?, staleLabel: String) {
    self.status = status
    self.hasData = hasData
    self.fetchedAt = fetchedAt
    self.staleLabel = staleLabel
  }

  var isConfigured: Bool { status != .failed(.notConfigured) }
}

private let normalInterval: Duration = .seconds(300)
private let offlineRetryInterval: Duration = .seconds(120)

// Retry sooner only when every configured source is offline.
public func nextRefreshInterval(sources: [PanelSource]) -> Duration {
  let configuredStatuses = sources.filter(\.isConfigured).map(\.status)
  let allOffline = !configuredStatuses.isEmpty && configuredStatuses.allSatisfy { $0 == .failed(.network) }
  return allOffline ? offlineRetryInterval : normalInterval
}
