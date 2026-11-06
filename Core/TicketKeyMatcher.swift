import Foundation

// Whole-token match: no letter or digit may touch the key on either side,
// so "PROJ-14" does not match "proj-143" or "XPROJ-14".
public func ticketKey(_ key: String, matches text: String) -> Bool {
  let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: key) + "(?![A-Za-z0-9])"
  return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}
