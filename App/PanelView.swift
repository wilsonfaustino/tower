import AppKit
import Core
import SwiftUI

struct PanelView: View {
  let store: QueueStore
  let close: () -> Void
  let openSettings: () -> Void
  @State private var selectedItemId: String?
  @State private var popoverItemId: String?
  @State private var selectedTab = PanelTab.needsYou
  @State private var expandedItemIds: Set<String> = []
  @State private var contentHeight: CGFloat = 0
  @State private var pinnedHeight: CGFloat = 0
  @State private var tabPickerHeight: CGFloat = 0
  @FocusState private var isListFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      if showsTabs {
        tabPicker.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabPickerHeight = $0 }
      }
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          content
            .padding(Theme.Spacing.s)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        // The tabs, pinned rows and legend share the max height, so the whole panel keeps its cap.
        .frame(
          height: min(max(contentHeight, 1), max(Theme.Metrics.panelMaxHeight - tabPickerHeight - pinnedHeight, 1)))
        .onChange(of: selectedItemId) { _, newValue in
          if let newValue { proxy.scrollTo(newValue) }
        }
        // Gives keyboard focus back to the list, with the same row selected, when the popover closes.
        .onChange(of: popoverItemId) { _, newValue in
          if newValue == nil { isListFocused = true }
        }
      }
      if showsTabs {
        pinnedContent
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pinnedHeight = $0 }
      }
    }
    .frame(width: Theme.Metrics.panelWidth)
    .onChange(of: selectedTab) {
      selectedItemId = nil
      popoverItemId = nil
      isListFocused = true
    }
    .focusable()
    .focusEffectDisabled()
    .focused($isListFocused)
    .onAppear {
      isListFocused = true
      // The panel may open without activating the app, so the activation refresh can miss the Reconnect return.
      if store.hasAuthenticationFailure { Task { await store.refresh() } }
    }
    .onKeyPress(.downArrow) { handle(.downArrow) }
    .onKeyPress(.upArrow) { handle(.upArrow) }
    .onKeyPress(.return) {
      guard let item = selectableItems.first(where: { $0.id == selectedItemId }) else { return .ignored }
      activate(item)
      return .handled
    }
    .onKeyPress(.rightArrow) { handleDisclosure(.right) }
    .onKeyPress(.leftArrow) { handleDisclosure(.left) }
    .onKeyPress(keys: ["1", "2"]) { press in
      guard press.modifiers.contains(.command), showsTabs else { return .ignored }
      selectedTab = press.characters == "1" ? .needsYou : .waiting
      return .handled
    }
    .onKeyPress(.space) { handle(.space) }
    .onKeyPress(.escape) { handle(.escape) }
    .onKeyPress(keys: ["c"]) { press in
      guard press.modifiers.contains(.command) else { return .ignored }
      return handle(.copy)
    }
    .onKeyPress(keys: [.delete]) { press in
      guard press.modifiers.contains(.command) else { return .ignored }
      return handle(.dismiss)
    }
  }

  private var header: some View {
    HStack(spacing: Theme.Spacing.s) {
      VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
        Text("Tower").font(Theme.Fonts.panelTitle).foregroundStyle(Theme.textPrimary)
        TimelineView(.periodic(from: .now, by: 30)) { context in
          Text(subtitle(now: context.date)).font(Theme.Fonts.rowMeta).foregroundStyle(Theme.textSecondary)
        }
      }
      Spacer()
      Button {
        Task { await store.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .disabled(store.isRefreshing)
      .help("Refresh")
      .accessibilityLabel("Refresh")
      Button(action: showSettings) {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.borderless)
      .help("Settings")
      .accessibilityLabel("Settings")
    }
    .padding(.horizontal, Theme.Spacing.l)
    .padding(.vertical, Theme.Spacing.m)
  }

  private var tabPicker: some View {
    Picker("Tab", selection: $selectedTab) {
      ForEach(PanelTab.allCases, id: \.self) { tab in
        Text("\(tab.title) \(tabItemCount(in: store.sections, tab: tab))").tag(tab)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .padding(.horizontal, Theme.Spacing.l)
    .padding(.bottom, Theme.Spacing.s)
  }

  @ViewBuilder private var tabContent: some View {
    let tabSections = sections(store.sections, in: selectedTab)
    if tabSections.isEmpty {
      switch selectedTab {
      case .needsYou:
        StateMessageView(
          symbol: "checkmark.seal", title: "Clear skies", message: "Nothing needs you right now.",
          footnote: store.todaySummary.map { todaySummaryText(reviews: $0.reviews, merges: $0.merges) })
      case .waiting:
        StateMessageView(symbol: "hourglass", title: "Nothing waiting", message: "Nothing waiting on others.")
      }
    } else {
      ForEach(tabSections) { section in
        sectionView(section)
      }
    }
  }

  // Watch rows sit below the scroll view on both tabs, so running pipelines stay in sight.
  private var pinnedContent: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      if let watchSection = store.sections.first(where: { $0.kind == .watch }) {
        sectionView(watchSection, visibleItemLimit: pinnedWatchRowLimit)
      }
      if !selectableItems.isEmpty {
        StatusLegendView()
      }
    }
    .padding(.horizontal, Theme.Spacing.s)
    .padding(.bottom, Theme.Spacing.s)
  }

  private func sectionView(_ section: QueueSection, visibleItemLimit: Int = .max) -> some View {
    QueueSectionView(
      section: section, selectedItemId: selectedItemId, expandedItemIds: expandedItemIds,
      visibleItemLimit: visibleItemLimit, popoverItemId: $popoverItemId, open: activate, showDetails: showDetails,
      copyLink: { writeLink($0.url, to: .general) }, dismiss: store.dismiss, handlePopoverInput: handle)
  }

  private var panelState: PanelContent {
    panelContent(sources: store.panelSources, hasItems: !store.sections.isEmpty)
  }

  private var showsTabs: Bool { panelState == .queue || panelState == .empty }

  @ViewBuilder private var content: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      if store.githubStatus == .failed(.authentication) {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          AuthBannerView(title: "GitHub sign-in expired", message: store.githubBannerMessage(now: context.date)) {
            GitHubReconnect.open(ghPath: GhCLITokenProvider().ghPath)
          }
        }
      }
      if store.jiraStatus == .failed(.authentication) {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          AuthBannerView(
            title: "Jira sign-in expired", message: store.jiraBannerMessage(now: context.date), reconnect: showSettings)
        }
      }
      if store.circleciStatus == .failed(.authentication) {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          AuthBannerView(
            title: "CircleCI token expired", message: store.circleciBannerMessage(now: context.date),
            actionTitle: "Open Settings", reconnect: showSettings)
        }
      }
      switch panelState {
      case .queue, .empty:
        tabContent
      case .offline:
        StateMessageView(
          symbol: "wifi.slash",
          title: offlineTitle(sources: [
            ("GitHub", store.githubStatus), ("Jira", store.jiraStatus), ("CircleCI", store.circleciStatus),
          ]),
          message: "Tower retries every 2 minutes.",
          actionTitle: "Try now") { Task { await store.refresh() } }
      case .failed(let message):
        StateMessageView(
          symbol: "exclamationmark.triangle", title: "Update failed", message: message,
          actionTitle: "Try now") { Task { await store.refresh() } }
      case .loading:
        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.xl)
      case .bannerOnly:
        EmptyView()
      }
    }
  }

  private func showSettings() {
    close()
    openSettings()
  }

  private func subtitle(now: Date) -> String {
    panelSubtitle(sources: store.panelSources, now: now)
  }

  private var selectableItems: [QueueItem] {
    guard showsTabs else { return [] }
    return selectableRows(in: store.sections, tab: selectedTab, expandedItemIds: expandedItemIds)
  }

  private func moveSelection(by offset: Int) -> KeyPress.Result {
    guard let nextItemId = nextSelectedItemId(in: selectableItems, after: selectedItemId, offset: offset) else {
      return .ignored
    }
    selectedItemId = nextItemId
    return .handled
  }

  private func handleDisclosure(_ direction: DisclosureDirection) -> KeyPress.Result {
    let outcome = disclosureOutcome(
      for: direction, selectedItemId: selectedItemId, in: sections(store.sections, in: selectedTab),
      expandedItemIds: expandedItemIds)
    switch outcome {
    case .expand(let groupId): expandedItemIds.insert(groupId)
    case .collapse(let groupId): expandedItemIds.remove(groupId)
    case .selectGroup(let groupId): selectedItemId = groupId
    case .ignore: return .ignored
    }
    popoverItemId = nil
    return .handled
  }

  private func handle(_ input: PanelInput) -> KeyPress.Result {
    let selectedItem = selectableItems.first(where: { $0.id == selectedItemId })
    let action = panelAction(
      for: input, selectedItemHasDetails: selectedItem?.details != nil, isPopoverOpen: popoverItemId != nil,
      selectedItemIsDismissible: selectedItem?.dismissal != nil)
    let outcome = panelKeyOutcome(for: action, selectedItemId: selectedItemId, popoverItemId: popoverItemId)
    popoverItemId = outcome.popoverItemId
    if outcome.copiesSelectedLink, let selectedItem { writeLink(selectedItem.url, to: .general) }
    if outcome.dismissesSelectedItem, let selectedItem { store.dismiss(selectedItem) }
    if let offset = outcome.selectionOffset { return moveSelection(by: offset) }
    return outcome.isHandled ? .handled : .ignored
  }

  private func showDetails(_ item: QueueItem) {
    selectedItemId = item.id
    popoverItemId = item.id
  }

  // Click and Return toggle a group row and open any other row. Cmd-click opens a group's search.
  private func activate(_ item: QueueItem) {
    guard !item.children.isEmpty, !NSEvent.modifierFlags.contains(.command) else { return open(item) }
    selectedItemId = item.id
    if expandedItemIds.contains(item.id) {
      expandedItemIds.remove(item.id)
    } else {
      expandedItemIds.insert(item.id)
    }
  }

  private func open(_ item: QueueItem) {
    // Cmd-click opens the item in the background, so the panel keeps key status and stays open.
    guard NSEvent.modifierFlags.contains(.command) else {
      NSWorkspace.shared.open(item.url)
      close()
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.open(item.url, configuration: configuration)
  }
}

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
