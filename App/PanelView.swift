import AppKit
import Core
import SwiftUI

struct PanelView: View {
  let store: QueueStore
  let close: () -> Void
  let openSettings: () -> Void
  @State private var selectedItemId: String?
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
    .onKeyPress(.downArrow) { moveSelection(by: 1) }
    .onKeyPress(.upArrow) { moveSelection(by: -1) }
    .onKeyPress(.return) {
      guard let item = allItems.first(where: { $0.id == selectedItemId }) else { return .ignored }
      open(item)
      return .handled
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
        AuthBannerView(title: "GitHub sign-in expired", message: githubBannerMessage) {
          GitHubReconnect.open(ghPath: GhCLITokenProvider().ghPath)
        }
      }
      if store.jiraStatus == .failed(.authentication) {
        AuthBannerView(title: "Jira sign-in expired", message: jiraBannerMessage, reconnect: showSettings)
      }
      if store.circleciStatus == .failed(.authentication) {
        AuthBannerView(
          title: "CircleCI token expired", message: circleciBannerMessage, actionTitle: "Open Settings",
          reconnect: showSettings)
      }
      switch panelContent(sources: store.panelSources, hasItems: !store.sections.isEmpty) {
      case .queue:
        ForEach(store.sections) { section in
          QueueSectionView(section: section, selectedItemId: selectedItemId, open: open)
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

  private var githubBannerMessage: String {
    authBannerMessage(
      itemsLabel: "PRs", fetchedAt: store.githubFetchedAt, now: Date(),
      missingDataMessage: "Run gh auth login to show your PRs.",
      otherSources: [("Jira", store.jiraStatus), ("CircleCI", store.circleciStatus)])
  }

  private var jiraBannerMessage: String {
    authBannerMessage(
      itemsLabel: "tickets", fetchedAt: store.jiraFetchedAt, now: Date(),
      missingDataMessage: "Check your Jira email and API token in Settings.",
      otherSources: [("GitHub", store.githubStatus), ("CircleCI", store.circleciStatus)])
  }

  private var circleciBannerMessage: String {
    authBannerMessage(
      itemsLabel: "pipelines", fetchedAt: store.circleciFetchedAt, now: Date(),
      missingDataMessage: "Check your CircleCI API token in Settings.",
      otherSources: [("GitHub", store.githubStatus), ("Jira", store.jiraStatus)])
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
