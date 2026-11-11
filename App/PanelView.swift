import AppKit
import Core
import SwiftUI

struct PanelView: View {
  let store: QueueStore
  let close: () -> Void
  let openSettings: () -> Void
  @State private var selectedItemId: String?
  @State private var popoverItemId: String?
  @State private var contentHeight: CGFloat = 0
  @FocusState private var isListFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          content
            .padding(Theme.Spacing.s)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(max(contentHeight, 1), Theme.Metrics.panelMaxHeight))
        .onChange(of: selectedItemId) { _, newValue in
          if let newValue { proxy.scrollTo(newValue) }
        }
        // Gives keyboard focus back to the list, with the same row selected, when the popover closes.
        .onChange(of: popoverItemId) { _, newValue in
          if newValue == nil { isListFocused = true }
        }
      }
    }
    .frame(width: Theme.Metrics.panelWidth)
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
      guard let item = allItems.first(where: { $0.id == selectedItemId }) else { return .ignored }
      open(item)
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

  @ViewBuilder private var content: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      if store.githubStatus == .failed(.authentication) {
        AuthBannerView(title: "GitHub sign-in expired", message: store.githubBannerMessage(now: Date())) {
          GitHubReconnect.open(ghPath: GhCLITokenProvider().ghPath)
        }
      }
      if store.jiraStatus == .failed(.authentication) {
        AuthBannerView(title: "Jira sign-in expired", message: store.jiraBannerMessage(now: Date()), reconnect: showSettings)
      }
      if store.circleciStatus == .failed(.authentication) {
        AuthBannerView(
          title: "CircleCI token expired", message: store.circleciBannerMessage(now: Date()), actionTitle: "Open Settings",
          reconnect: showSettings)
      }
      switch panelContent(sources: store.panelSources, hasItems: !store.sections.isEmpty) {
      case .queue:
        ForEach(store.sections) { section in
          QueueSectionView(
            section: section, selectedItemId: selectedItemId, popoverItemId: $popoverItemId, open: open,
            showDetails: showDetails, copyLink: { writeLink($0.url, to: .general) }, dismiss: store.dismiss,
            handlePopoverInput: handle)
        }
      case .empty:
        StateMessageView(
          symbol: "checkmark.seal", title: "Clear skies", message: "Nothing needs you right now.",
          footnote: store.todaySummary.map { todaySummaryText(reviews: $0.reviews, merges: $0.merges) })
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

  private var allItems: [QueueItem] { store.sections.flatMap(\.items) }

  private func moveSelection(by offset: Int) -> KeyPress.Result {
    guard let nextItemId = nextSelectedItemId(in: allItems, after: selectedItemId, offset: offset) else { return .ignored }
    selectedItemId = nextItemId
    return .handled
  }

  private func handle(_ input: PanelInput) -> KeyPress.Result {
    let selectedItem = allItems.first(where: { $0.id == selectedItemId })
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
