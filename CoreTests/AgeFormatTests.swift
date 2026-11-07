import Core
import Foundation
import Testing

private let ageCases: [(elapsedSeconds: Double, expected: String)] = [
  (30, "now"),
  (25 * 60, "25m"),
  (4 * 3600, "5h"),
  (26 * 3600, "1d"),
  (3 * 86400, "3d"),
]

struct AgeFormatTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test(arguments: ageCases)
  func shortAgeFormatsElapsedTime(ageCase: (elapsedSeconds: Double, expected: String)) {
    #expect(shortAge(from: now.addingTimeInterval(-ageCase.elapsedSeconds), now: now) == ageCase.expected)
  }
}
