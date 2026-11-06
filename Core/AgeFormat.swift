import Foundation

public func shortAge(from date: Date, now: Date) -> String {
  let elapsedMinutes = Int(now.timeIntervalSince(date) / 60)
  if elapsedMinutes < 1 { return "now" }
  if elapsedMinutes < 60 { return "\(elapsedMinutes)m" }
  let elapsedHours = elapsedMinutes / 60
  if elapsedHours < 24 { return "\(elapsedHours)h" }
  return "\(elapsedHours / 24)d"
}
