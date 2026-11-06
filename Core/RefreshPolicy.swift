public enum SourceStatus: Equatable, Sendable {
  case idle
  case ok
  case failed(SourceFailure)
}

private let normalInterval: Duration = .seconds(300)
private let offlineRetryInterval: Duration = .seconds(120)

// Retry sooner only when every configured source is offline.
public func nextRefreshInterval(github: SourceStatus, jira: SourceStatus) -> Duration {
  let configuredStatuses = [github, jira].filter { $0 != .failed(.notConfigured) }
  let allOffline = !configuredStatuses.isEmpty && configuredStatuses.allSatisfy { $0 == .failed(.network) }
  return allOffline ? offlineRetryInterval : normalInterval
}
