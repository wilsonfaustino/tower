import AppKit
import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
  case general
  case shortcuts
  case github
  case jira
  case circleci
  case about

  var label: String {
    switch self {
    case .general: "General"
    case .shortcuts: "Shortcuts"
    case .github: "GitHub"
    case .jira: "Jira"
    case .circleci: "CircleCI"
    case .about: "About"
    }
  }

  var symbol: SettingsSymbol {
    switch self {
    case .general: .general
    case .shortcuts: .shortcuts
    case .github: .github
    case .jira: .jira
    case .circleci: .circleci
    case .about: .about
    }
  }
}

// The Settings tabs as a toolbar, as in Copilot Runway. NSTabViewController does not animate the window to a new
// preferredContentSize, so this controller sets the window frame itself from the measured height of each tab.
@MainActor final class SettingsTabViewController: NSTabViewController {
  private let didSelectTab: (SettingsTab) -> Void
  private var contentSizes: [SettingsTab: CGSize] = [:]

  init(
    store: QueueStore, updateChecker: UpdateChecker, globalHotKey: GlobalHotKey, initialTab: SettingsTab,
    didSelectTab: @escaping (SettingsTab) -> Void
  ) {
    self.didSelectTab = didSelectTab
    super.init(nibName: nil, bundle: nil)
    tabStyle = .toolbar
    // The window keeps the title "Tower Settings" for every tab.
    canPropagateSelectedChildViewControllerTitle = false
    addTab(.general, content: SettingsGeneralTab())
    addTab(.shortcuts, content: SettingsShortcutsTab(globalHotKey: globalHotKey))
    addTab(.github, content: SettingsGitHubTab(store: store))
    addTab(.jira, content: SettingsJiraTab(store: store))
    addTab(.circleci, content: SettingsCircleCITab(store: store))
    addTab(.about, content: SettingsAboutTab(updateChecker: updateChecker))
    select(initialTab)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func select(_ tab: SettingsTab) {
    selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
  }

  private var selectedTab: SettingsTab? {
    SettingsTab.allCases.indices.contains(selectedTabViewItemIndex) ? SettingsTab.allCases[selectedTabViewItemIndex] : nil
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    fitWindowToSelectedTab()
  }

  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    // selectedTabViewItemIndex can still hold the previous tab here, so read the index of the new item.
    guard let tabViewItem else { return }
    let tabIndex = tabView.indexOfTabViewItem(tabViewItem)
    guard SettingsTab.allCases.indices.contains(tabIndex) else { return }
    didSelectTab(SettingsTab.allCases[tabIndex])
    fitWindowToSelectedTab()
  }

  private func addTab(_ tab: SettingsTab, content: some View) {
    // The ScrollView lets a tab taller than the screen scroll. It has no ideal height of its own, so the
    // content measures itself and the window follows.
    let hostingController = NSHostingController(
      rootView: ScrollView(.vertical) {
        content.onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] contentSize in
          guard let self else { return }
          contentSizes[tab] = contentSize
          if selectedTab == tab {
            fitWindowToSelectedTab()
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
    )
    // Without this, constraints from the SwiftUI size resize the window at once, without animation.
    hostingController.sizingOptions = []
    let item = NSTabViewItem(viewController: hostingController)
    item.label = tab.label
    item.image = NSImage(named: tab.symbol.rawValue)
    addTabViewItem(item)
  }

  // Keeps the top edge in place, and keeps the window inside the visible frame of its screen.
  private func fitWindowToSelectedTab() {
    guard let window = view.window, let selectedTab, let contentSize = contentSizes[selectedTab] else { return }
    let chromeHeight = window.frame.height - window.contentLayoutRect.height
    let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
    let height = min(contentSize.height + chromeHeight, visibleFrame?.height ?? .greatestFiniteMagnitude)
    var frame = window.frame
    frame.origin.y += frame.height - height
    frame.size = NSSize(width: contentSize.width, height: height)
    if let visibleFrame, frame.minY < visibleFrame.minY {
      frame.origin.y = visibleFrame.minY
    }
    guard frame != window.frame else { return }
    window.setFrame(frame, display: true, animate: window.isVisible)
  }
}
