import Foundation

public struct JiraSettings: Equatable, Sendable {
  public var siteURL: URL
  public var email: String
  public var apiToken: String

  public init(siteURL: URL, email: String, apiToken: String) {
    self.siteURL = siteURL
    self.email = email
    self.apiToken = apiToken
  }
}

public struct JiraClient: Sendable {
  // Status names differ by ticket type, so filter on the status category only.
  private static let jql = "assignee = currentUser() AND statusCategory = \"In Progress\" ORDER BY updated ASC"
  private static let maxResults = 50
  // Caps the fetch at 250 tickets, so a response that always sends a token cannot loop.
  private static let maxPages = 5

  private let settings: JiraSettings?
  private let transport: HTTPTransport

  public init(settings: JiraSettings?, transport: HTTPTransport) {
    self.settings = settings
    self.transport = transport
  }

  public func fetch() async throws(SourceFailure) -> [JiraTicket] {
    guard let settings else { throw .notConfigured }
    var request = URLRequest(url: settings.siteURL.appending(path: "rest/api/3/search/jql"))
    request.httpMethod = "POST"
    let credentials = Data("\(settings.email):\(settings.apiToken)".utf8).base64EncodedString()
    request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    var issues: [SearchResponse.Issue] = []
    var nextPageToken: String?
    for _ in 0..<Self.maxPages {
      var body: [String: Any] = ["jql": Self.jql, "fields": ["summary", "status", "updated"], "maxResults": Self.maxResults]
      body["nextPageToken"] = nextPageToken
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)

      let data = try await sendMapped(request, transport: transport)
      let response: SearchResponse
      do {
        response = try Self.decoder.decode(SearchResponse.self, from: data)
      } catch {
        throw .unexpected("Jira response did not decode")
      }
      issues += response.issues
      nextPageToken = response.nextPageToken
      if response.isLast == true || nextPageToken == nil { break }
    }
    return issues.map { issue in
      JiraTicket(
        key: issue.key, summary: issue.fields.summary, statusName: issue.fields.status.name,
        updatedAt: issue.fields.updated, url: settings.siteURL.appending(path: "browse/\(issue.key)"))
    }
  }

  // Jira sends "2027-01-12T09:00:00.000+0000": fractional seconds and no colon in the offset.
  private static let decoder: JSONDecoder = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(formatter)
    return decoder
  }()
}

private struct SearchResponse: Decodable {
  struct Issue: Decodable {
    var key: String
    var fields: Fields
  }
  struct Fields: Decodable {
    var summary: String
    var status: Status
    var updated: Date
  }
  struct Status: Decodable { var name: String }

  var issues: [Issue]
  var nextPageToken: String?
  var isLast: Bool?
}
