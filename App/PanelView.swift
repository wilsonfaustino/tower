import AppKit
import Core
import SwiftUI

struct PanelView: View {
  let store: QueueStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openSettings) private var openSettings
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
    .onAppear { isListFocused = true }
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
      Button(action: showSettings) {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.borderless)
      .help("Settings")
    }
    .padding(.horizontal, Theme.Spacing.l)
    .padding(.vertical, Theme.Spacing.m)
  }

  @ViewBuilder private var content: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      if store.githubStatus == .failed(.authentication) {
        AuthBannerView(title: "GitHub sign-in expired", message: githubBannerMessage) {
          GitHubReconnect.open(ghPath: store.tokenProvider.ghPath)
        }
      }
      if store.jiraStatus == .failed(.authentication) {
        AuthBannerView(title: "Jira sign-in expired", message: jiraBannerMessage, reconnect: showSettings)
      }
      if !store.hasAnyData {
        if [store.githubStatus, store.jiraStatus].contains(.failed(.network)) {
          StateMessageView(
            symbol: "wifi.slash", title: "Can't reach GitHub or Jira", message: "Tower retries every 2 minutes.",
            actionTitle: "Try now") { Task { await store.refresh() } }
        } else if store.githubStatus == .idle {
          ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.xl)
        }
      } else if store.sections.isEmpty {
        StateMessageView(
          symbol: "checkmark.seal", title: "Clear skies", message: "Nothing needs you right now.",
          footnote: store.todaySummary.map { "Today: \($0.reviews) reviews · \($0.merges) merges" })
      } else {
        ForEach(store.sections) { section in
          QueueSectionView(section: section, selectedItemId: selectedItemId, open: open)
        }
      }
    }
  }

  private var githubBannerMessage: String {
    guard let fetchedAt = store.githubFetchedAt else { return "Run gh auth login to show your PRs." }
    let minutes = max(1, Int(Date().timeIntervalSince(fetchedAt) / 60))
    let jiraSentence = store.jiraStatus == .ok ? " Jira is current." : ""
    return "Showing PRs from \(minutes) min ago.\(jiraSentence)"
  }

  private var jiraBannerMessage: String {
    guard let fetchedAt = store.jiraFetchedAt else { return "Check your Jira email and API token in Settings." }
    let minutes = max(1, Int(Date().timeIntervalSince(fetchedAt) / 60))
    let githubSentence = store.githubStatus == .ok ? " GitHub is current." : ""
    return "Showing tickets from \(minutes) min ago.\(githubSentence)"
  }

  // An agent app is not active while the panel shows, so bring it forward or Settings opens behind other windows.
  private func showSettings() {
    dismiss()
    NSApp.activate()
    openSettings()
  }

  private func subtitle(now: Date) -> String {
    let configuredStatuses = [store.githubStatus, store.jiraStatus].filter { $0 != .failed(.notConfigured) }
    if !configuredStatuses.isEmpty && configuredStatuses.allSatisfy({ $0 == .failed(.network) }) { return "Offline" }
    if store.githubStatus == .failed(.authentication), let fetchedAt = store.githubFetchedAt {
      return "PRs from \(shortAge(from: fetchedAt, now: now)) ago"
    }
    if store.jiraStatus == .failed(.authentication), let fetchedAt = store.jiraFetchedAt {
      return "Tickets from \(shortAge(from: fetchedAt, now: now)) ago"
    }
    guard let fetchedAt = [store.githubFetchedAt, store.jiraFetchedAt].compactMap({ $0 }).min() else { return "Updating" }
    let age = shortAge(from: fetchedAt, now: now)
    return age == "now" ? "Updated just now" : "Updated \(age) ago"
  }

  private var allItems: [QueueItem] { store.sections.flatMap(\.items) }

  private func moveSelection(by offset: Int) -> KeyPress.Result {
    let items = allItems
    guard !items.isEmpty else { return .ignored }
    let currentIndex = items.firstIndex { $0.id == selectedItemId }
    let nextIndex: Int
    if let currentIndex {
      nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
    } else {
      nextIndex = offset > 0 ? 0 : items.count - 1
    }
    selectedItemId = items[nextIndex].id
    return .handled
  }

  private func open(_ item: QueueItem) {
    NSWorkspace.shared.open(item.url)
    // Cmd-click opens the item and keeps the panel open.
    if !NSEvent.modifierFlags.contains(.command) { dismiss() }
  }
}
