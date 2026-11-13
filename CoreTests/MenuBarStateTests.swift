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

struct MenuBarStateAccessibilityTests {
  @Test func normalLabelIsAppName() {
    #expect(MenuBarState.normal.accessibilityLabel == "Tower")
  }

  @Test func urgentLabelCountsItems() {
    #expect(MenuBarState.urgent(count: 1).accessibilityLabel == "Tower, 1 urgent item")
    #expect(MenuBarState.urgent(count: 21).accessibilityLabel == "Tower, 21 urgent items")
  }

  @Test func failingLabelCountsItems() {
    #expect(MenuBarState.failing(count: 1).accessibilityLabel == "Tower, 1 item to fix")
    #expect(MenuBarState.failing(count: 3).accessibilityLabel == "Tower, 3 items to fix")
  }
}

@Suite struct MenuBarGroupTests {
  @Test func urgentChildInsideGroupCounts() {
    let url = URL(string: "https://example.com")!
    let child = QueueItem(
      id: "c", title: "c", meta: "1h", url: url, symbol: .waiting, badge: Badge(text: "Changes requested", variant: .urgent),
      sortDate: .distantPast)
    let group = QueueItem(id: "g", title: "g", meta: "1h", url: url, symbol: .waiting, badge: nil, sortDate: .distantPast, children: [child])
    #expect(MenuBarState(sections: [QueueSection(kind: .waiting, items: [group])]) == .urgent(count: 1))
  }
}
