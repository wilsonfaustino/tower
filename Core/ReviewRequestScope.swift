import Foundation

// Which review requests Tower asks GitHub for. Direct only keeps team requests out of the capped search.
public enum ReviewRequestScope: String, Sendable {
  case directAndTeam
  case directOnly

  var searchQualifier: String {
    switch self {
    case .directAndTeam: "review-requested:@me"
    case .directOnly: "user-review-requested:@me"
    }
  }
}
