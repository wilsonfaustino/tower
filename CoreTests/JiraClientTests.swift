import Core
import Foundation
import Testing

private let settings = JiraSettings(siteURL: URL(string: "https://acme.atlassian.net")!, email: "me@acme.com", apiToken: "jira-token")

struct JiraClientTests {
  @Test func decodesFixtureIntoTickets() async throws {
    let fixtureData = try fixture("jira-search.json")
    let tickets = try await JiraClient(settings: settings, transport: StubTransport { _ in (fixtureData, 200) }).fetch()
    #expect(tickets == [
      JiraTicket(
        key: "PROJ-1432", summary: "Offline sync for trap counts", statusName: "In Progress",
        updatedAt: isoDate("2027-01-12T09:00:00Z"), url: URL(string: "https://acme.atlassian.net/browse/PROJ-1432")!),
      JiraTicket(
        key: "PROJ-1440", summary: "Export scouting report as PDF", statusName: "In Review",
        updatedAt: isoDate("2027-01-14T15:30:00Z"), url: URL(string: "https://acme.atlassian.net/browse/PROJ-1440")!),
    ])
  }

  @Test func sendsJQLWithBasicAuth() async throws {
    let fixtureData = try fixture("jira-search.json")
    let transport = StubTransport { _ in (fixtureData, 200) }
    _ = try await JiraClient(settings: settings, transport: transport).fetch()
    let request = try #require(transport.requests.first)
    #expect(request.url == URL(string: "https://acme.atlassian.net/rest/api/3/search/jql"))
    #expect(request.httpMethod == "POST")
    let expectedCredentials = Data("me@acme.com:jira-token".utf8).base64EncodedString()
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(expectedCredentials)")
    let bodyData = try #require(request.httpBody)
    let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
    #expect(body["jql"] as? String == "assignee = currentUser() AND statusCategory = \"In Progress\" ORDER BY updated ASC")
    #expect(body["fields"] as? [String] == ["summary", "status", "updated"])
    #expect(body["maxResults"] as? Int == 50)
  }

  @Test func missingSettingsIsNotConfiguredWithoutRequest() async {
    let transport = StubTransport { _ in (Data(), 200) }
    await #expect(throws: SourceFailure.notConfigured) { try await JiraClient(settings: nil, transport: transport).fetch() }
    #expect(transport.requests.isEmpty)
  }

  @Test func unauthorizedResponseIsAuthenticationFailure() async {
    let transport = StubTransport { _ in (Data(), 401) }
    await #expect(throws: SourceFailure.authentication) { try await JiraClient(settings: settings, transport: transport).fetch() }
  }
}
