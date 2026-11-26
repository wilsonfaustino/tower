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

enum SelectionMove: Equatable, Sendable {
  case offset(Int), first, last
}

// The first offset press picks the first row (Down) or the last row (Up). At either end the selection stays.
func nextSelectedItemId(in items: [QueueItem], after selectedItemId: String?, move: SelectionMove) -> String? {
  guard let firstItem = items.first, let lastItem = items.last else { return nil }
  switch move {
  case .first: return firstItem.id
  case .last: return lastItem.id
  case .offset(let offset):
    guard let currentIndex = items.firstIndex(where: { $0.id == selectedItemId }) else {
      return offset > 0 ? firstItem.id : lastItem.id
    }
    return items[min(max(currentIndex + offset, 0), items.count - 1)].id
  }
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

// The pinned area shows the first rows of this section, so "Needs approval" pipelines come first on screen too.
func pinnedWatchSection(in sections: [QueueSection]) -> QueueSection? {
  guard let watchSection = sections.first(where: { $0.kind == .watch }) else { return nil }
  let watchItems = watchSection.items
  let urgentFirst = watchItems.filter { $0.statusDot == .urgent } + watchItems.filter { $0.statusDot != .urgent }
  return QueueSection(kind: .watch, items: urgentFirst)
}

func pinnedWatchRows(in sections: [QueueSection]) -> [QueueItem] {
  Array(pinnedWatchSection(in: sections)?.items.prefix(pinnedWatchRowLimit) ?? [])
}

func visibleRows(in sections: [QueueSection], expandedItemIds: Set<String>) -> [QueueItem] {
  sections.flatMap(\.items).flatMap { item in
    [item] + (expandedItemIds.contains(item.id) ? item.children : [])
  }
}

// Up and Down go through the listed rows. In Split, the pinned Watch rows follow them; the status filter does not
// cover the pinned rows.
func selectableRows(
  in sections: [QueueSection], layout: PanelLayout, tab: PanelTab, expandedItemIds: Set<String>,
  statusFilter: StatusDot? = nil
) -> [QueueItem] {
  let listedSections = filteredSections(displayedSections(sections, layout: layout, tab: tab), status: statusFilter)
  let listedRows = visibleRows(in: listedSections, expandedItemIds: expandedItemIds)
  return layout == .split ? listedRows + pinnedWatchRows(in: sections) : listedRows
}

// The global shortcut opens the panel on Needs you with the first row selected, so Return opens the most urgent item.
func shortcutOpenSelection(in sections: [QueueSection], layout: PanelLayout) -> String? {
  selectableRows(in: sections, layout: layout, tab: .needsYou, expandedItemIds: []).first?.id
}

// The saved shortcut matches the physical key, as the global hot key does.
@MainActor func isSwitchPanelViewKey(_ event: NSEvent?) -> Bool {
  guard let event, event.type == .keyDown else { return false }
  return ShortcutSettings.load(.switchPanelView)?.matches(
    keyCode: event.keyCode, modifiers: keyModifiers(from: event.modifierFlags)) == true
}

// No selection counts as listed, so only a selected row that leaves the list clears the selection.
func isSelectionListed(_ selectedItemId: String?, in rows: [QueueItem]) -> Bool {
  guard let selectedItemId else { return true }
  return rows.contains { $0.id == selectedItemId }
}

// The legend names the dots of the listed rows. A group adds its own dot, the one its row shows, not its children's.
func legendStatuses(in sections: [QueueSection]) -> [StatusDot] {
  let presentStatuses = Set(sections.flatMap(\.items).map(\.statusDot))
  return StatusDot.allCases.filter(presentStatuses.contains)
}

// The chosen status filters only while the legend shows it with another status, so the list never goes empty.
func effectiveStatusFilter(_ chosenStatus: StatusDot?, legendStatuses: [StatusDot]) -> StatusDot? {
  guard let chosenStatus, legendStatuses.count > 1, legendStatuses.contains(chosenStatus) else { return nil }
  return chosenStatus
}

// A matching group keeps all its children. A section with no matching rows leaves the list.
func filteredSections(_ sections: [QueueSection], status: StatusDot?) -> [QueueSection] {
  guard let status else { return sections }
  return sections.compactMap { section in
    let matchingItems = section.items.filter { $0.statusDot == status }
    return matchingItems.isEmpty ? nil : QueueSection(kind: section.kind, items: matchingItems)
  }
}

// A filtered section header still counts every row of its section.
func sectionHeaderCount(of section: QueueSection, in unfilteredSections: [QueueSection]) -> Int {
  rowCount(of: unfilteredSections.first { $0.kind == section.kind } ?? section)
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

enum SlideKey: Sendable {
  case left, right, returnKey, escape, upArrow, downArrow, space
}

enum SlideOutcome: Equatable, Sendable {
  case show, close, dismiss, stay, passThrough
}

// Like Mail, a dismissible row slides toward the leading edge to show Dismiss, so the keys mirror in right-to-left.
// While the slide shows, keys that cancel close it on the first press and do nothing else.
func slideOutcome(
  for key: SlideKey, layoutDirection: LayoutDirection, selectedItemIsDismissible: Bool, isSlid: Bool
) -> SlideOutcome {
  let opensSlide: SlideKey = layoutDirection == .rightToLeft ? .right : .left
  guard isSlid else { return key == opensSlide && selectedItemIsDismissible ? .show : .passThrough }
  if key == opensSlide { return .stay }
  return key == .returnKey ? .dismiss : .close
}

// Horizontal scroll, in points, that a two-finger swipe must pass before the row slides.
let swipeThreshold: CGFloat = 30

// A swipe acts as the arrow key in the same direction. The scroll delta follows the content,
// so natural scrolling decides which way the fingers moved.
func swipeOutcome(
  horizontalDelta: CGFloat, verticalDelta: CGFloat, isDirectionInvertedFromDevice: Bool,
  layoutDirection: LayoutDirection, isDismissible: Bool, isSlid: Bool
) -> SlideOutcome {
  guard abs(horizontalDelta) >= swipeThreshold, abs(horizontalDelta) > abs(verticalDelta) else { return .passThrough }
  let fingerDelta = isDirectionInvertedFromDevice ? horizontalDelta : -horizontalDelta
  return slideOutcome(
    for: fingerDelta < 0 ? .left : .right, layoutDirection: layoutDirection, selectedItemIsDismissible: isDismissible,
    isSlid: isSlid)
}

enum PanelInput: Equatable, Sendable {
  case click, commandClick, returnKey, space, escape, upArrow, downArrow, copy, rightClick, dismiss, undo
  case switchPanelView, commandUpArrow, commandDownArrow
}

// The arrows act with any modifiers. With Command they go to the first or last row.
func panelInput(for key: KeyEquivalent, modifiers: EventModifiers) -> PanelInput? {
  let hasCommand = modifiers.contains(.command)
  switch key {
  case .upArrow: return hasCommand ? .commandUpArrow : .upArrow
  case .downArrow: return hasCommand ? .commandDownArrow : .downArrow
  default: return nil
  }
}

enum PanelAction: Equatable, Sendable {
  case openAndClosePanel, openInBackground, showPopover, closePopover, closePopoverAndMoveSelection(SelectionMove)
  case copyLink, showContextMenu, closePanel, ignore, dismiss, undo, switchPanelView
}

// Click, Cmd-click and Return work on every row. Space and Cmd-C act only on rows with PR details.
// Cmd-Delete acts only on dismissible rows (failed pipelines, single review requests). Right-click acts on both kinds.
func panelAction(
  for input: PanelInput, selectedItemHasDetails: Bool, isPopoverOpen: Bool, selectedItemIsDismissible: Bool = false,
  canUndo: Bool = false
) -> PanelAction {
  switch input {
  case .click, .returnKey: return .openAndClosePanel
  case .commandClick: return .openInBackground
  case .space:
    if isPopoverOpen { return .closePopover }
    return selectedItemHasDetails ? .showPopover : .ignore
  case .escape: return isPopoverOpen ? .closePopover : .closePanel
  case .upArrow: return .closePopoverAndMoveSelection(.offset(-1))
  case .downArrow: return .closePopoverAndMoveSelection(.offset(1))
  case .commandUpArrow: return .closePopoverAndMoveSelection(.first)
  case .commandDownArrow: return .closePopoverAndMoveSelection(.last)
  case .copy: return selectedItemHasDetails ? .copyLink : .ignore
  case .rightClick: return selectedItemHasDetails || selectedItemIsDismissible ? .showContextMenu : .ignore
  case .dismiss: return selectedItemIsDismissible ? .dismiss : .ignore
  case .undo: return canUndo ? .undo : .ignore
  case .switchPanelView: return .switchPanelView
  }
}

struct PanelKeyOutcome: Equatable {
  var popoverItemId: String?
  var selectionMove: SelectionMove?
  var copiesSelectedLink = false
  var dismissesSelectedItem = false
  var undoesLastDismissal = false
  var switchesPanelView = false
  var isHandled = true
}

// Esc with no popover is not handled, so it goes on to PanelWindow.cancelOperation, which closes the panel.
func panelKeyOutcome(for action: PanelAction, selectedItemId: String?, popoverItemId: String?) -> PanelKeyOutcome {
  switch action {
  case .closePopoverAndMoveSelection(let move):
    return PanelKeyOutcome(popoverItemId: nil, selectionMove: move)
  case .showPopover:
    return PanelKeyOutcome(popoverItemId: selectedItemId)
  case .closePopover:
    return PanelKeyOutcome(popoverItemId: nil)
  case .copyLink:
    return PanelKeyOutcome(popoverItemId: popoverItemId, copiesSelectedLink: true)
  // The dismissed row leaves the list, so its popover closes with it.
  case .dismiss:
    return PanelKeyOutcome(popoverItemId: nil, dismissesSelectedItem: true)
  case .undo:
    return PanelKeyOutcome(popoverItemId: popoverItemId, undoesLastDismissal: true)
  // The list changes under the popover, so it closes. The selection stays while its row is still listed.
  case .switchPanelView:
    return PanelKeyOutcome(popoverItemId: nil, switchesPanelView: true)
  case .closePanel, .ignore, .openAndClosePanel, .openInBackground, .showContextMenu:
    return PanelKeyOutcome(popoverItemId: popoverItemId, isHandled: false)
  }
}

func writeLink(_ url: URL, to pasteboard: NSPasteboard) {
  pasteboard.clearContents()
  pasteboard.setString(url.absoluteString, forType: .string)
}
