import Core
import Foundation
import Testing

@testable import Tower

// Hosted tests run inside Tower.app, so each test uses its own defaults suite, not the owner's settings.
private func withDefaults(_ values: [String: String], _ body: (UserDefaults) -> Void) {
  let suiteName = "tower-tests-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  for (key, value) in values { defaults.set(value, forKey: key) }
  body(defaults)
  defaults.removePersistentDomain(forName: suiteName)
}

private let jiraValues = [JiraSettingsKeys.siteURL: "https://acme.atlassian.net", JiraSettingsKeys.email: "me@acme.dev"]

struct JiraSettingsLoaderTests {
  @Test func loadsSiteEmailAndTokenFromItsAccount() {
    withDefaults(jiraValues) { defaults in
      var readAccount: String?
      let settings = JiraSettingsKeys.load(defaults: defaults) { account in
        readAccount = account
        return "jira-token"
      }
      #expect(readAccount == KeychainStore.jiraTokenAccount)
      #expect(settings == JiraSettings(siteURL: URL(string: "https://acme.atlassian.net")!, email: "me@acme.dev", apiToken: "jira-token"))
    }
  }

  @Test(arguments: [
    [JiraSettingsKeys.email: "me@acme.dev"],
    [JiraSettingsKeys.siteURL: "acme.atlassian.net", JiraSettingsKeys.email: "me@acme.dev"],
    [JiraSettingsKeys.siteURL: "https://acme.atlassian.net"],
    [JiraSettingsKeys.siteURL: "https://acme.atlassian.net", JiraSettingsKeys.email: ""],
  ])
  func missingSiteHostOrEmailLoadsNil(values: [String: String]) {
    withDefaults(values) { defaults in
      #expect(JiraSettingsKeys.load(defaults: defaults) { _ in "jira-token" } == nil)
    }
  }

  @Test(arguments: [nil, ""])
  func missingTokenLoadsNil(token: String?) {
    withDefaults(jiraValues) { defaults in
      #expect(JiraSettingsKeys.load(defaults: defaults) { _ in token } == nil)
    }
  }
}

struct CircleCISettingsLoaderTests {
  @Test func loadsOneSlugPerLineAndTokenFromItsAccount() {
    withDefaults([CircleCISettingsKeys.projectSlugs: "gh/acme/app-web\n\n  gh/acme/api  \n"]) { defaults in
      var readAccount: String?
      let settings = CircleCISettingsKeys.load(defaults: defaults) { account in
        readAccount = account
        return "circle-token"
      }
      #expect(readAccount == KeychainStore.circleciTokenAccount)
      #expect(settings == CircleCISettings(apiToken: "circle-token", projectSlugs: ["gh/acme/app-web", "gh/acme/api"]))
    }
  }

  @Test(arguments: [[:], [CircleCISettingsKeys.projectSlugs: " \n \n"]])
  func emptySlugsLoadNil(values: [String: String]) {
    withDefaults(values) { defaults in
      #expect(CircleCISettingsKeys.load(defaults: defaults) { _ in "circle-token" } == nil)
    }
  }

  @Test(arguments: [nil, ""])
  func missingTokenLoadsNil(token: String?) {
    withDefaults([CircleCISettingsKeys.projectSlugs: "gh/acme/app-web"]) { defaults in
      #expect(CircleCISettingsKeys.load(defaults: defaults) { _ in token } == nil)
    }
  }
}

struct GitHubSettingsLoaderTests {
  @Test func loadsOneOrganizationPerLine() {
    withDefaults([GitHubSettingsKeys.organizations: "acme\n\n  side-project  \n"]) { defaults in
      #expect(GitHubSettingsKeys.loadOrganizations(defaults: defaults) == ["acme", "  side-project  "])
    }
  }

  @Test func missingValueLoadsEmptyList() {
    withDefaults([:]) { defaults in
      #expect(GitHubSettingsKeys.loadOrganizations(defaults: defaults).isEmpty)
    }
  }
}
