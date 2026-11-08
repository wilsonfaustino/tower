import Core
import Testing

struct SectionKindTests {
  @Test func titlesFollowTheQueueOrder() {
    #expect(SectionKind.allCases.map(\.title) == ["Fix", "Review", "Merge", "Tidy", "Watch", "Waiting"])
  }
}
