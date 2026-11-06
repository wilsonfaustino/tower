import Foundation

public enum PanelContent: Equatable, Sendable {
  case loading
  case offline
  case failed(String)
  case bannerOnly
  case empty
  case queue
}

// "Clear skies" shows only when every configured source has data, so a failed
// source never reads as "nothing needs you".
public func panelContent(
  github: SourceStatus, jira: SourceStatus, githubHasData: Bool, jiraHasData: Bool, hasItems: Bool
) -> PanelContent {
  if hasItems { return .queue }
  let sourcesWithoutData = [(github, githubHasData), (jira, jiraHasData)]
    .filter { status, hasData in status != .failed(.notConfigured) && !hasData }
    .map(\.0)
  if sourcesWithoutData.contains(.failed(.network)) { return .offline }
  for case .failed(.unexpected(let message)) in sourcesWithoutData { return .failed(message) }
  if sourcesWithoutData.contains(.idle) { return .loading }
  if sourcesWithoutData.contains(.failed(.authentication)) { return .bannerOnly }
  return .empty
}

public func panelSubtitle(
  github: SourceStatus, jira: SourceStatus, githubFetchedAt: Date?, jiraFetchedAt: Date?, now: Date
) -> String {
  if github == .failed(.authentication), let githubFetchedAt {
    return "PRs from \(shortAge(from: githubFetchedAt, now: now)) ago"
  }
  if jira == .failed(.authentication), let jiraFetchedAt {
    return "Tickets from \(shortAge(from: jiraFetchedAt, now: now)) ago"
  }
  let configuredStatuses = [github, jira].filter { $0 != .failed(.notConfigured) }
  if configuredStatuses.contains(.failed(.network)) { return "Offline" }
  if configuredStatuses.contains(where: { if case .failed = $0 { true } else { false } }) { return "Update failed" }
  guard let oldestFetch = [githubFetchedAt, jiraFetchedAt].compactMap({ $0 }).min() else { return "Updating" }
  let age = shortAge(from: oldestFetch, now: now)
  return age == "now" ? "Updated just now" : "Updated \(age) ago"
}
