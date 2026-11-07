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
public func panelContent(sources: [PanelSource], hasItems: Bool) -> PanelContent {
  if hasItems { return .queue }
  let sourcesWithoutData = sources.filter { $0.isConfigured && !$0.hasData }.map(\.status)
  if sourcesWithoutData.contains(.failed(.network)) { return .offline }
  for case .failed(.unexpected(let message)) in sourcesWithoutData { return .failed(message) }
  if sourcesWithoutData.contains(.idle) { return .loading }
  if sourcesWithoutData.contains(.failed(.authentication)) { return .bannerOnly }
  return .empty
}

// Source order sets which stale label wins on an authentication failure.
public func panelSubtitle(sources: [PanelSource], now: Date) -> String {
  for source in sources where source.status == .failed(.authentication) {
    if let fetchedAt = source.fetchedAt {
      return "\(source.staleLabel) from \(shortAge(from: fetchedAt, now: now)) ago"
    }
  }
  let configuredStatuses = sources.filter(\.isConfigured).map(\.status)
  if configuredStatuses.contains(.failed(.network)) { return "Offline" }
  if configuredStatuses.contains(where: { if case .failed = $0 { true } else { false } }) { return "Update failed" }
  guard let oldestFetch = sources.compactMap(\.fetchedAt).min() else { return "Updating" }
  let age = shortAge(from: oldestFetch, now: now)
  return age == "now" ? "Updated just now" : "Updated \(age) ago"
}
