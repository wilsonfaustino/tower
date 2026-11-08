import Core
import Foundation
import Testing

private let settings = JiraSettings(siteURL: URL(string: "https://acme.atlassian.net")!, email: "me@acme.com", apiToken: "jira-token")

private func searchPage(keys: [String], nextPageToken: String?) -> Data {
  let issues = keys.map { key in
    ["key": key, "fields": ["summary": "Ticket \(key)", "status": ["name": "In Progress"], "updated": "2027-01-12T09:00:00.000+0000"]]
  }
  var page: [String: Any] = ["issues": issues, "isLast": nextPageToken == nil]
  page["nextPageToken"] = nextPageToken
  return try! JSONSerialization.data(withJSONObject: page)
}

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

  @Test func followsNextPageTokenUntilLastPage() async throws {
    let transport = StubTransport { request in
      let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
      return body?["nextPageToken"] as? String == "page-2"
        ? (searchPage(keys: ["PROJ-3"], nextPageToken: nil), 200)
        : (searchPage(keys: ["PROJ-1", "PROJ-2"], nextPageToken: "page-2"), 200)
    }
    let tickets = try await JiraClient(settings: settings, transport: transport).fetch()
    #expect(tickets.map(\.key) == ["PROJ-1", "PROJ-2", "PROJ-3"])
    #expect(transport.requests.count == 2)
  }

  @Test func stopsAfterFivePages() async throws {
    let transport = StubTransport { _ in (searchPage(keys: ["PROJ-1"], nextPageToken: "more"), 200) }
    let tickets = try await JiraClient(settings: settings, transport: transport).fetch()
    #expect(transport.requests.count == 5)
    #expect(tickets.count == 5)
  }

  @Test func failedLaterPageFailsTheFetch() async {
    let transport = StubTransport { request in
      let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
      return body?["nextPageToken"] == nil ? (searchPage(keys: ["PROJ-1"], nextPageToken: "page-2"), 200) : (Data(), 401)
    }
    await #expect(throws: SourceFailure.authentication) { try await JiraClient(settings: settings, transport: transport).fetch() }
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
