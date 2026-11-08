import Core
import Foundation
import Testing

@testable import Tower

struct SettingsFailureTextTests {
  @Test(arguments: [
    ("GitHub", "Not signed in. Run gh auth login."),
    ("CircleCI", "Token rejected. Check the API token."),
    ("Jira", "Sign-in failed. Check email and token."),
  ])
  func authenticationTextNamesTheFixPerSource(source: String, text: String) {
    #expect(settingsFailureText(.authentication, source: source) == text)
  }

  @Test func otherFailures() {
    #expect(settingsFailureText(.network, source: "Jira") == "Can’t reach Jira")
    #expect(settingsFailureText(.notConfigured, source: "CircleCI") == "Not set up")
    #expect(settingsFailureText(.unexpected("HTTP 500"), source: "GitHub") == "HTTP 500")
  }
}

struct SettingsGitHubStatusTextTests {
  @Test func statusText() {
    #expect(settingsGitHubStatusText(status: .idle, viewerLogin: nil) == "Checking…")
    #expect(settingsGitHubStatusText(status: .ok, viewerLogin: "octo-me") == "Signed in as octo-me via gh")
    #expect(settingsGitHubStatusText(status: .ok, viewerLogin: nil) == "Signed in as unknown via gh")
    #expect(settingsGitHubStatusText(status: .failed(.authentication), viewerLogin: nil) == "Not signed in. Run gh auth login.")
  }
}

struct CircleCIConnectedTextTests {
  @Test func countsProjects() {
    #expect(circleciConnectedText(projectCount: 1) == "Connected · 1 project")
    #expect(circleciConnectedText(projectCount: 3) == "Connected · 3 projects")
  }
}

struct SaveTrimmedTokenTests {
  @Test func writesTheTrimmedToken() {
    var writes: [(String, String)] = []
    var deletes: [String] = []
    saveTrimmedToken("  secret-token \n", account: "jira-api-token") { writes.append(($0, $1)) } delete: { deletes.append($0) }
    #expect(writes.map(\.0) == ["secret-token"])
    #expect(writes.map(\.1) == ["jira-api-token"])
    #expect(deletes.isEmpty)
  }

  @Test(arguments: ["", "  \n "])
  func blankTokenDeletesTheAccount(token: String) {
    var writeCount = 0
    var deletes: [String] = []
    saveTrimmedToken(token, account: "circleci-api-token") { _, _ in writeCount += 1 } delete: { deletes.append($0) }
    #expect(writeCount == 0)
    #expect(deletes == ["circleci-api-token"])
  }
}
