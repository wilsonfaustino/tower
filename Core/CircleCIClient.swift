import Foundation

public struct CircleCISettings: Equatable, Sendable {
  public var apiToken: String
  public var projectSlugs: [String]

  public init(apiToken: String, projectSlugs: [String]) {
    self.apiToken = apiToken
    self.projectSlugs = projectSlugs
  }
}

// Pipelines older than this leave the panel, so the client does not read their workflows.
let pipelineWindow: TimeInterval = 24 * 3600

public struct CircleCIClient: Sendable {
  private static let baseURL = URL(string: "https://circleci.com/api/v2")!
  private static let failedStatuses: Set<String> = ["failed", "error", "failing", "unauthorized"]
  private static let runningStatuses: Set<String> = ["running", "not_run"]

  private let settings: CircleCISettings?
  private let transport: HTTPTransport

  public init(settings: CircleCISettings?, transport: HTTPTransport) {
    self.settings = settings
    self.transport = transport
  }

  public func fetch(now: Date) async throws(SourceFailure) -> [Pipeline] {
    guard let settings, !settings.apiToken.isEmpty, !settings.projectSlugs.isEmpty else { throw .notConfigured }
    var pipelines: [Pipeline] = []
    for slug in settings.projectSlugs {
      let page: PipelinePage
      do {
        page = try await get("project/\(slug)/pipeline/mine", token: settings.apiToken)
      } catch .unexpected("HTTP 404") {
        throw .unexpected("\(slug) not found")
      }
      for item in page.items where now.timeIntervalSince(item.createdAt) <= pipelineWindow {
        let state: PipelineState
        // The pipeline state reads "created" for running, finished and failed pipelines alike.
        if item.state == "errored" {
          state = .failed
        } else {
          let workflows: WorkflowList = try await get("pipeline/\(item.id)/workflow", token: settings.apiToken)
          state = Self.state(workflowStatuses: workflows.items.map(\.status))
        }
        pipelines.append(Pipeline(
          projectSlug: item.projectSlug, number: item.number, ref: item.vcs.tag ?? item.vcs.branch ?? "",
          refIsTag: item.vcs.tag != nil, triggerType: item.trigger.type,
          hasPullRequest: !(item.vcs.reviewUrl ?? "").isEmpty, createdAt: item.createdAt, state: state,
          url: Self.webURL(slug: item.projectSlug, number: item.number)))
      }
    }
    return pipelines
  }

  // A pipeline with no workflows yet counts as running.
  private static func state(workflowStatuses statuses: [String]) -> PipelineState {
    if statuses.contains("on_hold") { return .onHold }
    if statuses.contains(where: failedStatuses.contains) { return .failed }
    if statuses.isEmpty || statuses.contains(where: runningStatuses.contains) { return .running }
    return .succeeded
  }

  // The web app spells the VCS prefix out: "gh/acme/app-web" opens at "pipelines/github/acme/app-web".
  private static func webURL(slug: String, number: Int) -> URL {
    var parts = slug.split(separator: "/").map(String.init)
    if parts.first == "gh" { parts[0] = "github" }
    if parts.first == "bb" { parts[0] = "bitbucket" }
    return URL(string: "https://app.circleci.com/pipelines/\(parts.joined(separator: "/"))/\(number)")!
  }

  private func get<Response: Decodable>(_ path: String, token: String) async throws(SourceFailure) -> Response {
    var request = URLRequest(url: URL(string: "\(Self.baseURL.absoluteString)/\(path)")!)
    request.setValue(token, forHTTPHeaderField: "Circle-Token")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let data = try await sendMapped(request, transport: transport)
    do {
      return try Self.decoder.decode(Response.self, from: data)
    } catch {
      throw .unexpected("CircleCI response did not decode")
    }
  }

  // CircleCI sends "2027-01-15T11:02:34.621Z", with fractional seconds.
  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let text = try decoder.singleValueContainer().decode(String.self)
      return try Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
    return decoder
  }()
}

private struct PipelinePage: Decodable {
  struct Item: Decodable {
    var id: String
    var number: Int
    var state: String
    var createdAt: Date
    var projectSlug: String
    var trigger: Trigger
    var vcs: VCS
  }
  struct Trigger: Decodable { var type: String }
  // A tag push has a tag and no branch.
  struct VCS: Decodable {
    var branch: String?
    var tag: String?
    var reviewUrl: String?
  }

  var items: [Item]
}

private struct WorkflowList: Decodable {
  struct Workflow: Decodable { var status: String }

  var items: [Workflow]
}
