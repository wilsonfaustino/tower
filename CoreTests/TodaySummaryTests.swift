import Core
import Testing

struct TodaySummaryTests {
  @Test func pluralCounts() {
    #expect(todaySummaryText(reviews: 4, merges: 2) == "Today: 4 reviews · 2 merges")
  }

  @Test func singularCounts() {
    #expect(todaySummaryText(reviews: 1, merges: 1) == "Today: 1 review · 1 merge")
  }

  @Test func zeroCountsArePlural() {
    #expect(todaySummaryText(reviews: 0, merges: 0) == "Today: 0 reviews · 0 merges")
  }
}
