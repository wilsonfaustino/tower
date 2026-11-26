import Foundation

// Team, as "org/team", to the PR authors whose team review requests show. A team with no entry has no filter.
public struct TeamAuthorFilters: Hashable, Sendable {
  // Logins are lowercased.
  public var allowedAuthorsByTeam: [String: Set<String>]

  public init(allowedAuthorsByTeam: [String: Set<String>] = [:]) {
    self.allowedAuthorsByTeam = allowedAuthorsByTeam
  }

  // Tower does not know which teams the viewer is on, so a team with no entry has no say. A PR with no filtered
  // team shows.
  // A PR that asks several filtered teams shows if any of them allows its author.
  func allows(_ pullRequest: PullRequest) -> Bool {
    let filters = pullRequest.requestedTeamSlugs.compactMap { allowedAuthorsByTeam[$0] }
    return filters.isEmpty || filters.contains { $0.contains(pullRequest.author.lowercased()) }
  }
}
