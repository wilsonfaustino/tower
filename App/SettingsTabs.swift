import Core
import SwiftUI

// One tab of the Settings window, as in Copilot Runway: right-aligned labels on the left, the controls on the
// right, and a divider line between groups.
struct SettingsTabLayout<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    Grid(alignment: .topLeading, horizontalSpacing: Theme.Spacing.l, verticalSpacing: Theme.Spacing.m) {
      content
    }
    .padding(EdgeInsets(top: 20, leading: 16, bottom: 24, trailing: 28))
    .frame(width: Theme.Metrics.settingsWidth, alignment: .topLeading)
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct SettingsRow<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  var body: some View {
    GridRow {
      Text(label)
        .frame(width: Theme.Metrics.settingsLabelWidth, alignment: .trailing)
      VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct SettingsDivider: View {
  var body: some View {
    Divider().gridCellColumns(2)
  }
}

struct SettingsStatusRowView: View {
  let row: SettingsStatusRow

  var body: some View {
    HStack(spacing: Theme.Spacing.s) {
      Group {
        switch row.kind {
        case .checking:
          ProgressView().controlSize(.small)
        case .connected:
          Image(SettingsSymbol.connected.rawValue).foregroundStyle(Theme.statusText(.ready))
        case .notSetUp:
          Image(SettingsSymbol.notSetUp.rawValue).foregroundStyle(Theme.textSecondary)
        case .failed:
          Image(SettingsSymbol.failed.rawValue).foregroundStyle(Theme.statusText(.failing))
        }
      }
      .accessibilityHidden(true)
      Text(row.text)
        .foregroundStyle(row.kind == .failed ? Theme.statusText(.failing) : Theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct SettingsTextEditor: View {
  @Binding var text: String

  var body: some View {
    TextEditor(text: $text)
      .font(.body.monospaced())
      .scrollContentBackground(.hidden)
      .padding(Theme.Spacing.xs)
      .frame(minHeight: 60)
      .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.Spacing.xs))
      .overlay(RoundedRectangle(cornerRadius: Theme.Spacing.xs).strokeBorder(Color(nsColor: .separatorColor)))
  }
}

private let tokenSaveCaption = "Saved to the Keychain when you press Return, change tabs or close the window."

// Demo mode shows this fake token and never reads or writes the Keychain, so agents can open Settings without a prompt.
private let demoToken = "demo-token"

private func initialToken(account: String) -> String {
  DemoLaunch.isActive ? demoToken : KeychainStore.read(account: account) ?? ""
}

struct SettingsGeneralTab: View {
  @AppStorage(PanelSettingsKeys.layout) private var panelLayout = PanelLayout.split

  var body: some View {
    SettingsTabLayout {
      LaunchAtLoginSection()
      SettingsDivider()
      NotificationsSection()
      SettingsDivider()
      SettingsRow(label: "Panel view") {
        Picker("Panel view", selection: $panelLayout) {
          ForEach(PanelLayout.allCases, id: \.self) { layout in
            Text(layout.title).tag(layout)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        SettingsCaption(text: panelLayoutCaption)
      }
    }
  }

  private var panelLayoutCaption: String {
    switch panelLayout {
    case .split: "Needs you and Waiting show as tabs. Watch stays below them."
    case .consolidated: "All sections show on one page in urgency order, with no tabs."
    }
  }
}

struct SettingsGitHubTab: View {
  let store: QueueStore

  var body: some View {
    SettingsTabLayout {
      SettingsRow(label: "Status") {
        SettingsStatusRowView(
          row: settingsStatusRow(
            source: "GitHub", status: store.githubStatus, testStatus: nil, isTesting: false,
            connectedText: settingsGitHubStatusText(status: .ok, viewerLogin: store.githubSnapshot?.viewerLogin)))
        SettingsCaption(text: "Tower reads the GitHub token from the gh CLI. It stores no GitHub token.")
      }
      SettingsDivider()
      GitHubOrganizationsField()
      SettingsDivider()
      SettingsRow(label: "Review requests") {
        Picker("Review requests", selection: reviewRequestScope) {
          Text("Direct and team").tag(ReviewRequestScope.directAndTeam)
          Text("Direct only").tag(ReviewRequestScope.directOnly)
        }
        .labelsHidden()
        .fixedSize()
        SettingsCaption(text: "Direct only shows PRs that ask you by name. Use it for busy repos.")
      }
      GitHubTeamFiltersField(store: store)
    }
  }

  // A new scope sends a new search, so it refreshes at once.
  private var reviewRequestScope: Binding<ReviewRequestScope> {
    Binding {
      store.reviewRequestScope
    } set: { scope in
      store.reviewRequestScope = scope
      Task { await store.refresh() }
    }
  }
}

struct SettingsJiraTab: View {
  let store: QueueStore
  @AppStorage(JiraSettingsKeys.siteURL) private var jiraSiteURL = ""
  @AppStorage(JiraSettingsKeys.email) private var jiraEmail = ""
  @State private var jiraToken = initialToken(account: KeychainStore.jiraTokenAccount)
  @State private var tokenSaveError: String?
  @State private var testStatus: SourceStatus?
  @State private var isTesting = false

  var body: some View {
    SettingsTabLayout {
      SettingsRow(label: "Status") {
        HStack(alignment: .center) {
          SettingsStatusRowView(
            row: settingsStatusRow(
              source: "Jira", status: store.jiraStatus, testStatus: testStatus, isTesting: isTesting,
              connectedText: "Connected"))
          Spacer()
          Button("Test connection", action: testConnection)
            .controlSize(.small)
            .disabled(isTesting || DemoLaunch.isActive)
        }
      }
      SettingsDivider()
      SettingsRow(label: "Site URL") {
        TextField("Site URL", text: $jiraSiteURL, prompt: Text("https://acme.atlassian.net"))
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
        SettingsCaption(text: jiraSiteURLHint(jiraSiteURL))
      }
      SettingsRow(label: "Email") {
        TextField("Email", text: $jiraEmail)
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
      }
      SettingsRow(label: "API token") {
        SecureField("API token", text: $jiraToken)
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
          .onSubmit(saveToken)
        SettingsCaption(text: tokenSaveError)
        SettingsCaption(text: tokenSaveCaption)
      }
    }
    .onChange(of: store.jiraStatus) { testStatus = nil }
    .onDisappear(perform: saveToken)
  }

  private func saveToken() {
    guard !DemoLaunch.isActive else { return }
    tokenSaveError = saveTrimmedToken(jiraToken, account: KeychainStore.jiraTokenAccount)
  }

  private func testConnection() {
    saveToken()
    isTesting = true
    Task {
      do throws(SourceFailure) {
        _ = try await JiraClient(settings: JiraSettingsKeys.load(), transport: URLSessionTransport()).fetch()
        testStatus = .ok
        await store.refresh()
      } catch {
        testStatus = .failed(error)
      }
      isTesting = false
    }
  }
}

struct SettingsCircleCITab: View {
  let store: QueueStore
  @AppStorage(CircleCISettingsKeys.projectSlugs) private var circleciProjectSlugs = ""
  @State private var circleciToken = initialToken(account: KeychainStore.circleciTokenAccount)
  @State private var tokenSaveError: String?
  @State private var testStatus: SourceStatus?
  @State private var isTesting = false

  var body: some View {
    SettingsTabLayout {
      SettingsRow(label: "Status") {
        HStack(alignment: .center) {
          SettingsStatusRowView(
            row: settingsStatusRow(
              source: "CircleCI", status: store.circleciStatus, testStatus: testStatus, isTesting: isTesting,
              connectedText: circleciConnectedText(projectCount: circleciProjectCount)))
          Spacer()
          Button("Test connection", action: testConnection)
            .controlSize(.small)
            .disabled(isTesting || DemoLaunch.isActive)
        }
      }
      SettingsDivider()
      SettingsRow(label: "API token") {
        SecureField("API token", text: $circleciToken)
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
          .onSubmit(saveToken)
        SettingsCaption(text: tokenSaveError)
        SettingsCaption(text: tokenSaveCaption)
      }
      SettingsRow(label: "Projects") {
        SettingsTextEditor(text: $circleciProjectSlugs)
        SettingsCaption(text: "One project slug per line, like gh/org/repo.")
      }
    }
    .onChange(of: store.circleciStatus) { testStatus = nil }
    .onDisappear(perform: saveToken)
  }

  // CircleCISettings drops blank lines, so the count matches the projects Tower fetches.
  private var circleciProjectCount: Int {
    CircleCISettings(apiToken: "", projectSlugs: circleciProjectSlugs.split(whereSeparator: \.isNewline).map(String.init))
      .projectSlugs.count
  }

  private func saveToken() {
    guard !DemoLaunch.isActive else { return }
    tokenSaveError = saveTrimmedToken(circleciToken, account: KeychainStore.circleciTokenAccount)
  }

  private func testConnection() {
    saveToken()
    isTesting = true
    Task {
      do throws(SourceFailure) {
        _ = try await CircleCIClient(settings: CircleCISettingsKeys.load(), transport: URLSessionTransport())
          .fetch(now: Date())
        testStatus = .ok
        await store.refresh()
      } catch {
        testStatus = .failed(error)
      }
      isTesting = false
    }
  }
}

struct SettingsAboutTab: View {
  let updateChecker: UpdateChecker
  private static let authorURL = URL(string: "https://github.com/wilsonfaustino")!
  private static let repositoryURL = URL(string: "https://github.com/wilsonfaustino/tower")!
  private static let donationURL = URL(string: "https://buymeacoffee.com/wilsonfaustino")!

  private var versionText: String {
    let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "Version \(shortVersion) (\(buildNumber))"
  }

  var body: some View {
    SettingsTabLayout {
      SettingsRow(label: "Tower") {
        Text(versionText)
          .foregroundStyle(Theme.textSecondary)
        if let availableVersion = updateChecker.availableVersion {
          VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
              Text("Version \(availableVersion) is available.")
              UpdateControls(appUpdater: updateChecker.appUpdater)
            }
            // fixedSize collapses the row's Spacer, so Copy sits after the status text like Update sits after the version text.
            UpdateStatusRow(appUpdater: updateChecker.appUpdater)
              .fixedSize()
          }
        }
      }
      SettingsDivider()
      SettingsRow(label: "Made by") {
        Link("Wilson Faustino", destination: Self.authorURL)
      }
      SettingsRow(label: "Source") {
        Link(destination: Self.repositoryURL) {
          Label {
            Text("Star on GitHub")
          } icon: {
            Image(SettingsSymbol.star.rawValue)
          }
        }
      }
      GridRow {
        SupportCard(donationURL: Self.donationURL)
          .gridCellColumns(2)
      }
    }
  }
}

private struct SupportCard: View {
  let donationURL: URL

  var body: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.m) {
      Image(SettingsSymbol.coffee.rawValue)
        .font(.system(size: 18))
        .foregroundStyle(Theme.donationAccent)
        .frame(width: 40, height: 40)
        .background(Theme.donationAccent.opacity(0.18), in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Theme.Spacing.s) {
        Text("Enjoying Tower?")
          .fontWeight(.semibold)
        Text("Tower is free. If it saves you time, you can buy me a coffee.")
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: Theme.Spacing.m) {
          Link(destination: donationURL) {
            HStack(spacing: Theme.Spacing.xs) {
              Text("Buy me a coffee")
              Image(SettingsSymbol.openArrow.rawValue)
                .font(.system(size: 10, weight: .semibold))
            }
            .fontWeight(.medium)
            .foregroundStyle(Theme.donationAccentText)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 5)
            .background(Theme.donationAccent, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
          }
          .buttonStyle(.plain)
          Text("Opens in your browser")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, Theme.Spacing.xxs)
      }
    }
    .padding(Theme.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.banner).strokeBorder(Theme.cardStroke))
  }
}
