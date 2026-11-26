import AppKit
import Core
import SwiftUI

struct PanelView: View {
  let store: QueueStore
  let updateChecker: UpdateChecker
  let close: () -> Void
  // Nil opens Settings on the last tab shown.
  let openSettings: (SettingsTab?) -> Void
  // The global shortcut opens the panel with the first row selected. A click opens it with no selection.
  var selectsFirstRow = false
  @State private var hasSelectedFirstRow = false
  @State private var selectionScrollRequest = 0
  @State private var selectedItemId: String?
  @State private var popoverItemId: String?
  @State private var selectedTab = PanelTab.needsYou
  // The legend status the owner clicked. It filters the list only while `statusFilter` says so.
  @State private var chosenStatusFilter: StatusDot?
  @AppStorage(PanelSettingsKeys.layout) private var layout = PanelLayout.split
  @State private var expandedItemIds: Set<String> = []
  @State private var contentHeight: CGFloat = 0
  @State private var pinnedHeight: CGFloat = 0
  // The divider and padding above the pinned rows, which show only while the list scrolls.
  @State private var pinnedEdgeHeight: CGFloat = 0
  @State private var tabPickerHeight: CGFloat = 0
  @State private var updateNoticeHeight: CGFloat = 0
  @FocusState private var isListFocused: Bool
  // The selected row that shows Dismiss. Only the selected row can slide, so one row at most shows it.
  @State private var slidItemId: String?
  @State private var slidDismissal: Dismissal?
  @State private var hoveredItemId: String?
  @State private var scrollMonitor: Any?
  @State private var swipeDelta = CGSize.zero
  @State private var hasSwipeActed = false
  @Environment(\.layoutDirection) private var layoutDirection

  var body: some View {
    VStack(spacing: 0) {
      header
      if let availableVersion = updateChecker.availableVersion {
        updateNotice(version: availableVersion)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { updateNoticeHeight = $0 }
      }
      if showsTabs {
        tabPicker.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabPickerHeight = $0 }
      }
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          content
            .padding(Theme.Spacing.s)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .background(OverlayScroller())
        }
        .frame(height: min(max(contentHeight, 1), max(scrollAreaMaxHeight - pinnedEdgeHeight, 1)))
        .overlay(alignment: .bottom) { undoBar }
        .onChange(of: selectedItemId) { _, newValue in
          if let newValue { proxy.scrollTo(newValue) }
        }
        .onChange(of: selectionScrollRequest) {
          if let selectedItemId { proxy.scrollTo(selectedItemId) }
        }
        // The kept selection can sit lower in the other view, so the list scrolls to it again. The scroll waits a
        // main actor turn, so the rows of the new view are laid out first.
        .onChange(of: layout) {
          guard let selectedItemId else { return }
          Task { @MainActor in proxy.scrollTo(selectedItemId) }
        }
        // Gives keyboard focus back to the list, with the same row selected, when the popover closes.
        .onChange(of: popoverItemId) { _, newValue in
          if newValue == nil { isListFocused = true }
        }
      }
      if showsQueue {
        VStack(spacing: 0) {
          // Rows scroll under this edge, so it needs the same divider as the edge under the tabs.
          if isListScrolling {
            Divider()
          }
          pinnedContent
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pinnedHeight = $0 }
            .padding(.top, isListScrolling ? Theme.Spacing.s : 0)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pinnedEdgeHeight = $0 - pinnedHeight }
      }
    }
    .frame(width: Theme.Metrics.panelWidth)
    .onChange(of: selectedTab) {
      clearSelection()
      chosenStatusFilter = nil
    }
    .onChange(of: selectedItemId) { _, newValue in
      if slidItemId != newValue { slidItemId = nil }
    }
    // A refresh can remove the slid row, or a rerun can keep its id with another dismissal or none.
    // Clearing here keeps it closed if the row comes back.
    .onChange(of: isSlidRowListed) { _, isListed in
      if !isListed { slidItemId = nil }
    }
    // On a first launch the queue can still be loading when the shortcut opens the panel.
    .onChange(of: showsQueue) { selectFirstRowIfOpenedByShortcut() }
    // The selection stays while its row is still listed in the new view.
    .onChange(of: layout) {
      popoverItemId = nil
      chosenStatusFilter = nil
      isListFocused = true
    }
    // A refresh, dismiss or undo can take the chosen status out of the legend. Forgetting it then means
    // the status does not filter again by itself when it comes back.
    .onChange(of: legendStatusList) { _, statuses in
      chosenStatusFilter = effectiveStatusFilter(chosenStatusFilter, legendStatuses: statuses)
    }
    // The filter, a refresh or a dismissal can hide the selected row. Its popover closes with it.
    .onChange(of: isSelectedRowListed) { _, isListed in
      if !isListed { clearSelection() }
    }
    .focusable()
    .focusEffectDisabled()
    .focused($isListFocused)
    .onAppear {
      isListFocused = true
      selectFirstRowIfOpenedByShortcut()
      // The panel may open without activating the app, so the activation refresh can miss the Reconnect return.
      if store.hasAuthenticationFailure { Task { await store.refresh() } }
      scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
        let (phase, delta, isDirectionInverted) = (
          event.phase, CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
          event.isDirectionInvertedFromDevice
        )
        let isUsed = MainActor.assumeIsolated {
          handleSwipe(phase: phase, delta: delta, isDirectionInvertedFromDevice: isDirectionInverted)
        }
        return isUsed ? nil : event
      }
    }
    .onDisappear {
      if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
      scrollMonitor = nil
    }
    .onKeyPress(keys: [.downArrow]) { press in handleSlide(.downArrow) ?? handleKey(press) }
    .onKeyPress(keys: [.upArrow]) { press in handleSlide(.upArrow) ?? handleKey(press) }
    .onKeyPress(.return) {
      if let result = handleSlide(.returnKey) { return result }
      guard let item = selectableItems.first(where: { $0.id == selectedItemId }) else { return .ignored }
      activate(item)
      return .handled
    }
    .onKeyPress(.rightArrow) { handleSlide(.right) ?? handleDisclosure(.right) }
    .onKeyPress(.leftArrow) { handleSlide(.left) ?? handleDisclosure(.left) }
    .onKeyPress(keys: ["1", "2"]) { press in
      guard press.modifiers.contains(.command), showsTabs, let tab = panelTab(forShortcut: press.characters) else {
        return .ignored
      }
      selectedTab = tab
      return .handled
    }
    .onKeyPress(.space) { handleSlide(.space) ?? handle(.space) }
    .onKeyPress(.escape) { handleSlide(.escape) ?? handle(.escape) }
    .onKeyPress(keys: ["c"]) { press in
      guard press.modifiers.contains(.command) else { return .ignored }
      return handle(.copy)
    }
    .onKeyPress(keys: [.delete]) { press in
      guard press.modifiers.contains(.command) else { return .ignored }
      return handle(.dismiss)
    }
    .onKeyPress(phases: .down) { _ in
      isSwitchPanelViewKey(NSApp.currentEvent) ? handle(.switchPanelView) : .ignored
    }
    .onKeyPress(keys: panelCharacterKeys) { handleKey($0) }
    .onKeyPress(keys: ["z"]) { press in
      // Only Cmd (Caps Lock aside), so Shift-Cmd-Z (redo) does not undo.
      guard press.modifiers.subtracting(.capsLock) == .command else { return .ignored }
      return handle(.undo)
    }
  }

  // The id gives each dismissal a new bar, so its countdown starts again.
  @ViewBuilder private var undoBar: some View {
    if let lastDismissal = store.lastDismissal {
      UndoBarView(
        title: lastDismissal.title, expiresAt: lastDismissal.expiresAt, duration: store.undoDuration,
        undo: store.undoLastDismissal)
      .id(lastDismissal.id)
      .padding(Theme.Spacing.s)
    }
  }

  // The tabs, pinned rows and legend share the max height, so the whole panel keeps its cap.
  // It leaves out the edge above the pinned rows, so the edge that scrolling adds cannot keep the list scrolling.
  private var scrollAreaMaxHeight: CGFloat {
    // The picker and notice heights keep their last value after they hide, so count them only while they show.
    let noticeHeight = updateChecker.availableVersion == nil ? 0 : updateNoticeHeight
    return max(Theme.Metrics.panelMaxHeight - (showsTabs ? tabPickerHeight : 0) - noticeHeight - pinnedHeight, 1)
  }

  private var isListScrolling: Bool { contentHeight > scrollAreaMaxHeight }

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
        if store.isRefreshing {
          ProgressView().controlSize(.small)
        } else {
          Image(PanelSymbol.refresh.rawValue)
        }
      }
      .buttonStyle(.borderless)
      .disabled(store.isRefreshing)
      .help("Refresh")
      .accessibilityLabel("Refresh")
      .accessibilityValue(store.isRefreshing ? "Refreshing…" : "")
      Button { showSettings() } label: {
        Image(PanelSymbol.settings.rawValue)
      }
      .buttonStyle(.borderless)
      .help("Settings")
      .accessibilityLabel("Settings")
    }
    .padding(.horizontal, Theme.Spacing.l)
    .padding(.vertical, Theme.Spacing.m)
  }

  private func updateNotice(version: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      HStack(spacing: Theme.Spacing.s) {
        Text("Version \(version) is available.")
          .font(Theme.Fonts.rowMeta)
          .foregroundStyle(Theme.textSecondary)
        Spacer()
        UpdateControls(appUpdater: updateChecker.appUpdater)
      }
      UpdateStatusRow(appUpdater: updateChecker.appUpdater)
    }
    .padding(.horizontal, Theme.Spacing.l)
    .padding(.bottom, Theme.Spacing.m)
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

  @ViewBuilder private var queueContent: some View {
    if listedSections.isEmpty {
      if layout == .split && selectedTab == .waiting {
        StateMessageView(symbol: .nothingWaiting, title: "Nothing waiting", message: "Nothing waiting on others.")
      } else {
        StateMessageView(
          symbol: .clearSkies, title: "Clear skies", message: "Nothing needs you right now.",
          footnote: store.todaySummary.map { todaySummaryText(reviews: $0.reviews, merges: $0.merges) })
      }
    } else {
      ForEach(listedSections) { section in
        sectionView(section, headerCount: sectionHeaderCount(of: section, in: unfilteredListedSections))
      }
    }
  }

  // In Split, Watch rows sit below the scroll view on both tabs, so running pipelines stay in sight.
  // In Consolidated, Watch is in the list, so only the legend stays here.
  private var pinnedContent: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      if layout == .split, let watchSection = pinnedWatchSection(in: store.sections) {
        sectionView(watchSection, visibleItemLimit: pinnedWatchRowLimit)
      }
      if !legendStatusList.isEmpty {
        StatusLegendView(statuses: legendStatusList, activeStatus: statusFilter, choose: chooseStatusFilter)
      }
    }
    .padding(.horizontal, Theme.Spacing.s)
    .padding(.bottom, Theme.Spacing.s)
  }

  private func sectionView(
    _ section: QueueSection, visibleItemLimit: Int = .max, headerCount: Int? = nil
  ) -> some View {
    QueueSectionView(
      section: section, selectedItemId: selectedItemId, expandedItemIds: expandedItemIds, slidItemId: slidItemId,
      visibleItemLimit: visibleItemLimit, headerCount: headerCount, popoverItemId: $popoverItemId, open: activate,
      openInBrowser: open, showDetails: showDetails, copyLink: { writeLink($0.url, to: .general) }, dismiss: dismiss,
      hover: trackHover, handlePopoverInput: handle, handlePopoverSlideKey: { handleSlide($0) ?? .ignored })
  }

  private var panelState: PanelContent {
    panelContent(sources: store.panelSources, hasItems: !store.sections.isEmpty)
  }

  private var showsQueue: Bool { panelState == .queue || panelState == .empty }

  private var showsTabs: Bool { showsQueue && layout == .split }

  @ViewBuilder private var content: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      if store.githubStatus == .failed(.authentication) {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          AuthBannerView(title: "GitHub sign-in expired", message: store.githubBannerMessage(now: context.date)) {
            if !DemoLaunch.isActive { GitHubReconnect.open(ghPath: GhCLITokenProvider().ghPath) }
          }
        }
      }
      if store.jiraStatus == .failed(.authentication) {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          AuthBannerView(
            title: "Jira sign-in expired", message: store.jiraBannerMessage(now: context.date),
            reconnect: { showSettings() })
        }
      }
      if store.circleciStatus == .failed(.authentication) {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          AuthBannerView(
            title: "CircleCI token expired", message: store.circleciBannerMessage(now: context.date),
            actionTitle: "Open Settings", reconnect: { showSettings() })
        }
      }
      switch panelState {
      case .queue, .empty:
        queueContent
      case .offline:
        StateMessageView(
          symbol: .offline,
          title: offlineTitle(sources: [
            ("GitHub", store.githubStatus), ("Jira", store.jiraStatus), ("CircleCI", store.circleciStatus),
          ]),
          message: "Tower retries every 2 minutes.",
          actionTitle: "Try now") { Task { await store.refresh() } }
      case .failed(let message):
        StateMessageView(
          symbol: .updateFailed, title: "Update failed", message: message,
          actionTitle: "Try now") { Task { await store.refresh() } }
      case .loading:
        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.xl)
      case .bannerOnly:
        EmptyView()
      }
    }
  }

  private func showSettings(tab: SettingsTab? = nil) {
    close()
    openSettings(tab)
  }

  private func subtitle(now: Date) -> String {
    panelSubtitle(sources: store.panelSources, now: now)
  }

  private var selectableItems: [QueueItem] {
    guard showsQueue else { return [] }
    return selectableRows(
      in: store.sections, layout: layout, tab: selectedTab, expandedItemIds: expandedItemIds,
      statusFilter: statusFilter)
  }

  private var unfilteredListedSections: [QueueSection] {
    displayedSections(store.sections, layout: layout, tab: selectedTab)
  }

  private var legendStatusList: [StatusDot] { legendStatuses(in: unfilteredListedSections) }

  private var statusFilter: StatusDot? {
    effectiveStatusFilter(chosenStatusFilter, legendStatuses: legendStatusList)
  }

  private var listedSections: [QueueSection] { filteredSections(unfilteredListedSections, status: statusFilter) }

  // A second click on the active status shows every row again.
  private func chooseStatusFilter(_ status: StatusDot) {
    chosenStatusFilter = chosenStatusFilter == status ? nil : status
    isListFocused = true
  }

  private func selectFirstRowIfOpenedByShortcut() {
    guard selectsFirstRow, !hasSelectedFirstRow, showsQueue else { return }
    hasSelectedFirstRow = true
    selectedItemId = shortcutOpenSelection(in: store.sections, layout: layout)
  }

  private func clearSelection() {
    selectedItemId = nil
    popoverItemId = nil
    isListFocused = true
  }

  private func moveSelection(_ move: SelectionMove) -> KeyPress.Result {
    guard let nextItemId = nextSelectedItemId(in: selectableItems, after: selectedItemId, move: move) else {
      return .ignored
    }
    // The row can be selected but scrolled out of view, so a move that keeps it still scrolls to it.
    if nextItemId == selectedItemId { selectionScrollRequest += 1 }
    selectedItemId = nextItemId
    return .handled
  }

  private func handleDisclosure(_ direction: DisclosureDirection) -> KeyPress.Result {
    let outcome = disclosureOutcome(
      for: direction, selectedItemId: selectedItemId,
      in: listedSections, expandedItemIds: expandedItemIds)
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
      selectedItemIsDismissible: selectedItem?.dismissal != nil, canUndo: store.lastDismissal != nil,
      statusFilter: statusFilter, legendStatuses: legendStatusList)
    let outcome = panelKeyOutcome(for: action, selectedItemId: selectedItemId, popoverItemId: popoverItemId)
    popoverItemId = outcome.popoverItemId
    if outcome.copiesSelectedLink, let selectedItem { writeLink(selectedItem.url, to: .general) }
    if outcome.dismissesSelectedItem, let selectedItem { dismiss(selectedItem) }
    if outcome.undoesLastDismissal { store.undoLastDismissal() }
    if outcome.refreshes { Task { await store.refresh() } }
    if let step = outcome.statusFilterStep {
      chosenStatusFilter = steppedStatusFilter(statusFilter, step: step, legendStatuses: legendStatusList)
    }
    if outcome.opensShortcutSettings { showSettings(tab: .shortcuts) }
    // The filter resets in the same update as the layout, so the old filter cannot hide the selected row.
    if outcome.switchesPanelView {
      chosenStatusFilter = nil
      layout = layout.toggled
    }
    if let move = outcome.selectionMove { return moveSelection(move) }
    return outcome.isHandled ? .handled : .ignored
  }

  private func handleKey(_ press: KeyPress) -> KeyPress.Result {
    guard let input = panelInput(for: press.key, modifiers: press.modifiers) else { return .ignored }
    return handle(input)
  }

  // Nil lets the key do what it does today.
  private func handleSlide(_ key: SlideKey) -> KeyPress.Result? {
    let selectedItem = selectableItems.first { $0.id == selectedItemId }
    let outcome = slideOutcome(
      for: key, layoutDirection: layoutDirection, selectedItemIsDismissible: selectedItem?.dismissal != nil,
      isSlid: slidItemId != nil)
    switch outcome {
    case .show: if let selectedItem { showSlide(on: selectedItem) }
    case .close: slidItemId = nil
    case .dismiss: if let selectedItem { dismiss(selectedItem) }
    case .stay: break
    case .passThrough: return nil
    }
    return .handled
  }

  // The popover closes, so it does not cover the slid row.
  private func showSlide(on item: QueueItem) {
    selectedItemId = item.id
    slidItemId = item.id
    slidDismissal = item.dismissal
    popoverItemId = nil
  }

  private var isSelectedRowListed: Bool { isSelectionListed(selectedItemId, in: selectableItems) }

  private var isSlidRowListed: Bool {
    guard let slidItemId else { return false }
    return selectableItems.contains { $0.id == slidItemId && $0.dismissal == slidDismissal }
  }

  private func dismiss(_ item: QueueItem) {
    slidItemId = nil
    store.dismiss(item)
  }

  private func trackHover(_ item: QueueItem, isHovering: Bool) {
    if isHovering {
      hoveredItemId = item.id
    } else if hoveredItemId == item.id {
      hoveredItemId = nil
    }
  }

  // A two-finger swipe arrives as scroll events with a phase. Each swipe acts once, on the row under the pointer,
  // and momentum after the fingers lift is ignored. False sends the event on to the scroll view.
  private func handleSwipe(phase: NSEvent.Phase, delta: CGSize, isDirectionInvertedFromDevice: Bool) -> Bool {
    switch phase {
    case .began:
      swipeDelta = .zero
      hasSwipeActed = false
    case .changed: break
    default: return false
    }
    guard !hasSwipeActed, let hoveredItem = selectableItems.first(where: { $0.id == hoveredItemId }) else {
      return false
    }
    swipeDelta.width += delta.width
    swipeDelta.height += delta.height
    let outcome = swipeOutcome(
      horizontalDelta: swipeDelta.width, verticalDelta: swipeDelta.height,
      isDirectionInvertedFromDevice: isDirectionInvertedFromDevice, layoutDirection: layoutDirection,
      isDismissible: hoveredItem.dismissal != nil, isSlid: slidItemId == hoveredItem.id)
    switch outcome {
    case .show: showSlide(on: hoveredItem)
    case .close: slidItemId = nil
    case .dismiss, .stay, .passThrough: return false
    }
    hasSwipeActed = true
    return true
  }

  private func showDetails(_ item: QueueItem) {
    slidItemId = nil
    selectedItemId = item.id
    popoverItemId = item.id
  }

  // Click and Return toggle a group row and open any other row. Cmd-click opens a group's search.
  private func activate(_ item: QueueItem) {
    guard !item.children.isEmpty, !NSEvent.modifierFlags.contains(.command) else { return open(item) }
    selectedItemId = item.id
    expandedItemIds = toggledExpansion(of: item.id, in: expandedItemIds)
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
