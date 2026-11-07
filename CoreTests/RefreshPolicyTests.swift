import Core
import Testing

private func source(_ status: SourceStatus) -> PanelSource {
  PanelSource(status: status, hasData: false, fetchedAt: nil, staleLabel: "PRs")
}

struct RefreshPolicyTests {
  @Test func allSourcesOfflineRetriesSooner() {
    #expect(nextRefreshInterval(sources: [source(.failed(.network)), source(.failed(.network))]) == .seconds(120))
  }

  @Test func offlineGitHubWithJiraNotConfiguredRetriesSooner() {
    #expect(nextRefreshInterval(sources: [source(.failed(.network)), source(.failed(.notConfigured))]) == .seconds(120))
  }

  @Test func healthyGitHubUsesNormalInterval() {
    #expect(nextRefreshInterval(sources: [source(.ok), source(.failed(.network))]) == .seconds(300))
  }

  @Test func authFailureIsNotOffline() {
    #expect(nextRefreshInterval(sources: [source(.failed(.authentication)), source(.failed(.network))]) == .seconds(300))
  }
}

struct ThreeSourceRefreshPolicyTests {
  @Test func allThreeOfflineRetriesSooner() {
    #expect(
      nextRefreshInterval(sources: [source(.failed(.network)), source(.failed(.network)), source(.failed(.network))])
        == .seconds(120))
  }

  @Test func healthyThirdSourceUsesNormalInterval() {
    #expect(nextRefreshInterval(sources: [source(.failed(.network)), source(.failed(.network)), source(.ok)]) == .seconds(300))
  }
}
