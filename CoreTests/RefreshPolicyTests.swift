import Core
import Testing

struct RefreshPolicyTests {
  @Test func allSourcesOfflineRetriesSooner() {
    #expect(nextRefreshInterval(github: .failed(.network), jira: .failed(.network)) == .seconds(120))
  }

  @Test func offlineGitHubWithJiraNotConfiguredRetriesSooner() {
    #expect(nextRefreshInterval(github: .failed(.network), jira: .failed(.notConfigured)) == .seconds(120))
  }

  @Test func healthyGitHubUsesNormalInterval() {
    #expect(nextRefreshInterval(github: .ok, jira: .failed(.network)) == .seconds(300))
  }

  @Test func authFailureIsNotOffline() {
    #expect(nextRefreshInterval(github: .failed(.authentication), jira: .failed(.network)) == .seconds(300))
  }
}
