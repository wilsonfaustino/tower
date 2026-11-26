import Foundation

// Team slug to the PR authors whose team review requests show. A team with no entry has no filter.
public struct TeamAuthorFilters: Hashable, Sendable {
  // Logins are lowercased.
  public var allowedAuthorsByTeam: [String: Set<String>]

  public init(allowedAuthorsByTeam: [String: Set<String>] = [:]) {
    self.allowedAuthorsByTeam = allowedAuthorsByTeam
  }

  // Parses the Settings text, one login per line. A team keeps its entry when no line is valid, so it hides every request.
  public init(rawLoginsByTeam: [String: String]) {
    allowedAuthorsByTeam = rawLoginsByTeam.mapValues { rawLogins in
      Set(
        rawLogins.split(whereSeparator: \.isNewline)
          .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
          .filter(isValidGitHubLogin))
    }
  }

  // Tower does not know which teams the viewer is on, so a team with no entry allows every author.
  // A PR that asks several filtered teams shows if any of them allows its author.
  func allows(_ pullRequest: PullRequest) -> Bool {
    let filters = pullRequest.requestedTeamSlugs.compactMap { allowedAuthorsByTeam[$0] }
    return filters.isEmpty || filters.contains { $0.contains(pullRequest.author.lowercased()) }
  }
}
