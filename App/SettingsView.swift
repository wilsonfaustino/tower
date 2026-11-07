import Core
import SwiftUI

struct SettingsView: View {
  let store: QueueStore
  @AppStorage(JiraSettingsKeys.siteURL) private var jiraSiteURL = ""
  @AppStorage(JiraSettingsKeys.email) private var jiraEmail = ""
  @State private var jiraToken = KeychainStore.read(account: KeychainStore.jiraTokenAccount) ?? ""
  @State private var jiraTestResult: String?
  @State private var isTestingJira = false
  @AppStorage(CircleCISettingsKeys.projectSlugs) private var circleciProjectSlugs = ""
  @State private var circleciToken = KeychainStore.read(account: KeychainStore.circleciTokenAccount) ?? ""
  @State private var circleciTestResult: String?
  @State private var isTestingCircleCI = false

  var body: some View {
    Form {
      Section("GitHub") {
        LabeledContent("Status", value: githubStatusText)
      }
      Section("Jira") {
        TextField("Site URL", text: $jiraSiteURL, prompt: Text("https://acme.atlassian.net"))
        TextField("Email", text: $jiraEmail)
        SecureField("API token", text: $jiraToken)
          .onSubmit(saveToken)
        HStack {
          Button("Test connection", action: testJira)
            .disabled(isTestingJira)
          if let jiraTestResult {
            Text(jiraTestResult).foregroundStyle(Theme.textSecondary)
          }
        }
      }
      Section("CircleCI") {
        SecureField("API token", text: $circleciToken)
          .onSubmit(saveCircleCIToken)
        LabeledContent("Projects") {
          TextEditor(text: $circleciProjectSlugs)
            .font(.body.monospaced())
            .frame(minHeight: 60)
        }
        Text("One project slug per line, like gh/org/repo.")
          .font(.caption)
          .foregroundStyle(Theme.textSecondary)
        HStack {
          Button("Test connection", action: testCircleCI)
            .disabled(isTestingCircleCI)
          if let circleciTestResult {
            Text(circleciTestResult).foregroundStyle(Theme.textSecondary)
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .onDisappear {
      saveToken()
      saveCircleCIToken()
    }
  }

  private var githubStatusText: String {
    switch store.githubStatus {
    case .idle: "Checking"
    case .ok: "Signed in as \(store.githubSnapshot?.viewerLogin ?? "unknown") via gh"
    case .failed(let failure): failureText(failure, source: "GitHub")
    }
  }

  private func failureText(_ failure: SourceFailure, source: String) -> String {
    switch failure {
    case .authentication:
      switch source {
      case "GitHub": "Not signed in. Run gh auth login."
      case "CircleCI": "Token rejected. Check the API token."
      default: "Sign-in failed. Check email and token."
      }
    case .network: "Can't reach \(source)"
    case .notConfigured: "Not set up"
    case .unexpected(let message): message
    }
  }

  private func saveToken() {
    let trimmedToken = jiraToken.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedToken.isEmpty {
      KeychainStore.delete(account: KeychainStore.jiraTokenAccount)
    } else {
      try? KeychainStore.write(trimmedToken, account: KeychainStore.jiraTokenAccount)
    }
  }

  private func saveCircleCIToken() {
    let trimmedToken = circleciToken.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedToken.isEmpty {
      KeychainStore.delete(account: KeychainStore.circleciTokenAccount)
    } else {
      try? KeychainStore.write(trimmedToken, account: KeychainStore.circleciTokenAccount)
    }
  }

  private func testJira() {
    saveToken()
    isTestingJira = true
    jiraTestResult = nil
    Task {
      do throws(SourceFailure) {
        _ = try await JiraClient(settings: JiraSettingsKeys.load(), transport: URLSessionTransport()).fetch()
        jiraTestResult = "Connected"
        await store.refresh()
      } catch {
        jiraTestResult = failureText(error, source: "Jira")
      }
      isTestingJira = false
    }
  }

  private func testCircleCI() {
    saveCircleCIToken()
    isTestingCircleCI = true
    circleciTestResult = nil
    let projectCount = CircleCISettingsKeys.load()?.projectSlugs.count ?? 0
    Task {
      await store.refresh()
      switch store.circleciStatus {
      case .failed(let failure):
        circleciTestResult = failureText(failure, source: "CircleCI")
      default:
        circleciTestResult = "Connected · \(projectCount) \(projectCount == 1 ? "project" : "projects")"
      }
      isTestingCircleCI = false
    }
  }
}
