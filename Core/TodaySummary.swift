public func todaySummaryText(reviews: Int, merges: Int) -> String {
  "Today: \(reviews) \(reviews == 1 ? "review" : "reviews") · \(merges) \(merges == 1 ? "merge" : "merges")"
}
