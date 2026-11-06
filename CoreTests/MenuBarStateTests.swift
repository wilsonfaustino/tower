import Core
import Foundation
import Testing

private func item(_ id: String, _ variant: BadgeVariant) -> QueueItem {
  QueueItem(
    id: id, title: id, meta: "", url: URL(string: "https://example.com")!, symbol: .review,
    badge: Badge(text: "", variant: variant), sortDate: .distantPast)
}

struct MenuBarStateTests {
  @Test func noSectionsIsNormal() {
    let state = MenuBarState(sections: [])
    #expect(state == .normal)
    #expect(state.imageName == "MenuBarCab")
    #expect(state.countText == nil)
  }

  @Test func urgentItemsWithoutFixAreUrgent() {
    let state = MenuBarState(sections: [
      QueueSection(kind: .review, items: [item("a", .urgent), item("b", .urgent), item("c", .neutral)])
    ])
    #expect(state == .urgent(count: 2))
    #expect(state.imageName == "MenuBarCabUrgent")
    #expect(state.countText == "2")
  }

  @Test func fixItemsWinOverUrgent() {
    let state = MenuBarState(sections: [
      QueueSection(kind: .fix, items: [item("a", .failing)]),
      QueueSection(kind: .review, items: [item("b", .urgent), item("c", .urgent)]),
    ])
    #expect(state == .failing(count: 1))
    #expect(state.imageName == "MenuBarCabFailing")
    #expect(state.countText == "1")
  }
}
