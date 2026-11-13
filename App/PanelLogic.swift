import AppKit
import Core
import SwiftUI

extension QueueStore {
  func githubBannerMessage(now: Date) -> String {
    authBannerMessage(
      itemsLabel: "PRs", fetchedAt: githubFetchedAt, now: now,
      missingDataMessage: "Run gh auth login to show your PRs.",
      otherSources: [("Jira", jiraStatus), ("CircleCI", circleciStatus)])
  }

  func jiraBannerMessage(now: Date) -> String {
    authBannerMessage(
      itemsLabel: "tickets", fetchedAt: jiraFetchedAt, now: now,
      missingDataMessage: "Check your Jira email and API token in Settings.",
      otherSources: [("GitHub", githubStatus), ("CircleCI", circleciStatus)])
  }

  func circleciBannerMessage(now: Date) -> String {
    authBannerMessage(
      itemsLabel: "pipelines", fetchedAt: circleciFetchedAt, now: now,
      missingDataMessage: "Check your CircleCI API token in Settings.",
      otherSources: [("GitHub", githubStatus), ("Jira", jiraStatus)])
  }
}

func authBannerMessage(
  itemsLabel: String, fetchedAt: Date?, now: Date, missingDataMessage: String,
  otherSources: [(name: String, status: SourceStatus)]
) -> String {
  guard let fetchedAt else { return missingDataMessage }
  let minutes = max(1, Int(now.timeIntervalSince(fetchedAt) / 60))
  return "Showing \(itemsLabel) from \(minutes) min ago.\(currentSentence(sources: otherSources))"
}

// Names the other sources that fetched on the last refresh, like " GitHub and Jira are current."
func currentSentence(sources: [(name: String, status: SourceStatus)]) -> String {
  let names = sources.filter { $0.status == .ok }.map(\.name)
  guard !names.isEmpty else { return "" }
  return " \(names.joined(separator: " and ")) \(names.count == 1 ? "is" : "are") current."
}

// The first press picks the first row (Down) or the last row (Up). At either end the selection stays.
func nextSelectedItemId(in items: [QueueItem], after selectedItemId: String?, offset: Int) -> String? {
  guard !items.isEmpty else { return nil }
  let nextIndex: Int
  if let currentIndex = items.firstIndex(where: { $0.id == selectedItemId }) {
    nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
  } else {
    nextIndex = offset > 0 ? 0 : items.count - 1
  }
  return items[nextIndex].id
}

// A group counts as its children, so the label matches the rows the owner can expand to.
func tabItemCount(in sections: [QueueSection], tab: PanelTab) -> Int {
  Core.sections(sections, in: tab).reduce(0) { $0 + rowCount(of: $1) }
}

func rowCount(of section: QueueSection) -> Int {
  section.items.reduce(0) { $0 + max($1.children.count, 1) }
}

// Cmd-1 and Cmd-2 pick the tab in the order the segmented control shows them.
func panelTab(forShortcut characters: String) -> PanelTab? {
  guard let digit = Int(characters), PanelTab.allCases.indices.contains(digit - 1) else { return nil }
  return PanelTab.allCases[digit - 1]
}

func toggledExpansion(of groupId: String, in expandedItemIds: Set<String>) -> Set<String> {
  expandedItemIds.contains(groupId) ? expandedItemIds.subtracting([groupId]) : expandedItemIds.union([groupId])
}

let pinnedWatchRowLimit = 2

func pinnedWatchRows(in sections: [QueueSection]) -> [QueueItem] {
  let watchItems = sections.first { $0.kind == .watch }?.items ?? []
  let urgentFirst = watchItems.filter { $0.statusDot == .urgent } + watchItems.filter { $0.statusDot != .urgent }
  return Array(urgentFirst.prefix(pinnedWatchRowLimit))
}

func visibleRows(in sections: [QueueSection], expandedItemIds: Set<String>) -> [QueueItem] {
  sections.flatMap(\.items).flatMap { item in
    [item] + (expandedItemIds.contains(item.id) ? item.children : [])
  }
}

// Up and Down go through the tab rows, then the pinned Watch rows.
func selectableRows(in sections: [QueueSection], tab: PanelTab, expandedItemIds: Set<String>) -> [QueueItem] {
  visibleRows(in: Core.sections(sections, in: tab), expandedItemIds: expandedItemIds) + pinnedWatchRows(in: sections)
}

enum DisclosureDirection: Sendable {
  case left, right
}

enum DisclosureOutcome: Equatable, Sendable {
  case expand(String), collapse(String), selectGroup(String), ignore
}

func disclosureOutcome(
  for direction: DisclosureDirection, selectedItemId: String?, in sections: [QueueSection],
  expandedItemIds: Set<String>
) -> DisclosureOutcome {
  guard let selectedItemId else { return .ignore }
  for item in sections.flatMap(\.items) where !item.children.isEmpty {
    let isExpanded = expandedItemIds.contains(item.id)
    if item.id == selectedItemId {
      switch direction {
      case .right: return isExpanded ? .ignore : .expand(item.id)
      case .left: return isExpanded ? .collapse(item.id) : .ignore
      }
    }
    if isExpanded, item.children.contains(where: { $0.id == selectedItemId }) {
      return direction == .left ? .selectGroup(item.id) : .ignore
    }
  }
  return .ignore
}

enum PanelInput: Sendable {
  case click, commandClick, returnKey, space, escape, upArrow, downArrow, copy, rightClick, dismiss
}

enum PanelAction: Equatable, Sendable {
  case openAndClosePanel, openInBackground, showPopover, closePopover, closePopoverAndMoveSelection(offset: Int)
  case copyLink, showContextMenu, closePanel, ignore, dismiss
}

// Click, Cmd-click and Return work on every row. Space and Cmd-C act only on rows with PR details.
// Cmd-Delete acts only on dismissible rows (failed pipelines). Right-click acts on both kinds.
func panelAction(
  for input: PanelInput, selectedItemHasDetails: Bool, isPopoverOpen: Bool, selectedItemIsDismissible: Bool = false
) -> PanelAction {
  switch input {
  case .click, .returnKey: return .openAndClosePanel
  case .commandClick: return .openInBackground
  case .space:
    if isPopoverOpen { return .closePopover }
    return selectedItemHasDetails ? .showPopover : .ignore
  case .escape: return isPopoverOpen ? .closePopover : .closePanel
  case .upArrow: return .closePopoverAndMoveSelection(offset: -1)
  case .downArrow: return .closePopoverAndMoveSelection(offset: 1)
  case .copy: return selectedItemHasDetails ? .copyLink : .ignore
  case .rightClick: return selectedItemHasDetails || selectedItemIsDismissible ? .showContextMenu : .ignore
  case .dismiss: return selectedItemIsDismissible ? .dismiss : .ignore
  }
}

struct PanelKeyOutcome: Equatable {
  var popoverItemId: String?
  var selectionOffset: Int?
  var copiesSelectedLink = false
  var dismissesSelectedItem = false
  var isHandled = true
}

// Esc with no popover is not handled, so it goes on to PanelWindow.cancelOperation, which closes the panel.
func panelKeyOutcome(for action: PanelAction, selectedItemId: String?, popoverItemId: String?) -> PanelKeyOutcome {
  switch action {
  case .closePopoverAndMoveSelection(let offset):
    return PanelKeyOutcome(popoverItemId: nil, selectionOffset: offset)
  case .showPopover:
    return PanelKeyOutcome(popoverItemId: selectedItemId)
  case .closePopover:
    return PanelKeyOutcome(popoverItemId: nil)
  case .copyLink:
    return PanelKeyOutcome(popoverItemId: popoverItemId, copiesSelectedLink: true)
  case .dismiss:
    return PanelKeyOutcome(popoverItemId: popoverItemId, dismissesSelectedItem: true)
  case .closePanel, .ignore, .openAndClosePanel, .openInBackground, .showContextMenu:
    return PanelKeyOutcome(popoverItemId: popoverItemId, isHandled: false)
  }
}

func writeLink(_ url: URL, to pasteboard: NSPasteboard) {
  pasteboard.clearContents()
  pasteboard.setString(url.absoluteString, forType: .string)
}
