import Core
import Security
import SwiftUI

struct SettingsView: View {
  let store: QueueStore
  @AppStorage(JiraSettingsKeys.siteURL) private var jiraSiteURL = ""
  @AppStorage(JiraSettingsKeys.email) private var jiraEmail = ""
  @State private var jiraToken = KeychainStore.read(account: KeychainStore.jiraTokenAccount) ?? ""
  @State private var jiraTokenSaveError: String?
  @State private var jiraTestResult: String?
  @State private var isTestingJira = false
  @AppStorage(CircleCISettingsKeys.projectSlugs) private var circleciProjectSlugs = ""
  @State private var circleciToken = KeychainStore.read(account: KeychainStore.circleciTokenAccount) ?? ""
  @State private var circleciTokenSaveError: String?
  @State private var circleciTestResult: String?
  @State private var isTestingCircleCI = false

  var body: some View {
    Form {
      LaunchAtLoginSection()
      Section("GitHub") {
        LabeledContent(
          "Status", value: settingsGitHubStatusText(status: store.githubStatus, viewerLogin: store.githubSnapshot?.viewerLogin))
        GitHubOrganizationsField()
      }
      Section("Jira") {
        TextField("Site URL", text: $jiraSiteURL, prompt: Text("https://acme.atlassian.net"))
        SettingsCaption(text: jiraSiteURLHint(jiraSiteURL))
        TextField("Email", text: $jiraEmail)
        SecureField("API token", text: $jiraToken)
          .onSubmit(saveToken)
        SettingsCaption(text: jiraTokenSaveError)
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
        SettingsCaption(text: circleciTokenSaveError)
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

  private func saveToken() {
    jiraTokenSaveError = saveTrimmedToken(jiraToken, account: KeychainStore.jiraTokenAccount)
  }

  private func saveCircleCIToken() {
    circleciTokenSaveError = saveTrimmedToken(circleciToken, account: KeychainStore.circleciTokenAccount)
  }

  private func testJira() {
    saveToken()
    jiraTestResult = nil
    // A failed save leaves the old token in the Keychain, so a test would check the wrong token.
    guard jiraTokenSaveError == nil else { return }
    isTestingJira = true
    Task {
      do throws(SourceFailure) {
        _ = try await JiraClient(settings: JiraSettingsKeys.load(), transport: URLSessionTransport()).fetch()
        jiraTestResult = "Connected"
        await store.refresh()
      } catch {
        jiraTestResult = settingsFailureText(error, source: "Jira")
      }
      isTestingJira = false
    }
  }

  private func testCircleCI() {
    saveCircleCIToken()
    circleciTestResult = nil
    guard circleciTokenSaveError == nil else { return }
    isTestingCircleCI = true
    let settings = CircleCISettingsKeys.load()
    let projectCount = settings?.projectSlugs.count ?? 0
    Task {
      do throws(SourceFailure) {
        _ = try await CircleCIClient(settings: settings, transport: URLSessionTransport()).fetch(now: Date())
        circleciTestResult = circleciConnectedText(projectCount: projectCount)
      } catch {
        circleciTestResult = settingsFailureText(error, source: "CircleCI")
      }
      isTestingCircleCI = false
    }
  }
}

func settingsGitHubStatusText(status: SourceStatus, viewerLogin: String?) -> String {
  switch status {
  case .idle: "Checking…"
  case .ok: "Signed in as \(viewerLogin ?? "unknown") via gh"
  case .failed(let failure): settingsFailureText(failure, source: "GitHub")
  }
}

func settingsFailureText(_ failure: SourceFailure, source: String) -> String {
  switch failure {
  case .authentication:
    switch source {
    case "GitHub": "Not signed in. Run gh auth login."
    case "CircleCI": "Token rejected. Check the API token."
    default: "Sign-in failed. Check email and token."
    }
  case .network: "Can’t reach \(source)"
  case .notConfigured: "Not set up"
  case .unexpected(let message): message
  }
}

func circleciConnectedText(projectCount: Int) -> String {
  "Connected · \(projectCount) \(projectCount == 1 ? "project" : "projects")"
}

// An empty token deletes the Keychain item, so clearing the field signs the source out.
// Returns the text to show when the Keychain write fails, or nil.
func saveTrimmedToken(
  _ token: String, account: String,
  write: (String, String) throws -> Void = KeychainStore.write(_:account:),
  delete: (String) -> Void = KeychainStore.delete(account:)
) -> String? {
  let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmedToken.isEmpty {
    delete(account)
    return nil
  }
  do {
    try write(trimmedToken, account)
    return nil
  } catch let keychainError as KeychainError {
    let reason = SecCopyErrorMessageString(keychainError.status, nil) as String? ?? "OSStatus \(keychainError.status)"
    return "Can’t save the token: \(reason)"
  } catch {
    return "Can’t save the token: \(error.localizedDescription)"
  }
}

// Mirrors the site check in JiraSettingsKeys.load, and also asks for https so the token never goes out in cleartext.
func jiraSiteURLHint(_ siteURL: String) -> String? {
  guard !siteURL.isEmpty else { return nil }
  if let site = URL(string: siteURL), site.scheme?.lowercased() == "https", site.host() != nil { return nil }
  return "Use the full URL, for example https://acme.atlassian.net"
}
