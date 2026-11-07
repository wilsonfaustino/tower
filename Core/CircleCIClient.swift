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

  private let settings: CircleCISettings?
  private let transport: HTTPTransport

  public init(settings: CircleCISettings?, transport: HTTPTransport) {
    self.settings = settings
    self.transport = transport
  }

  public func fetch(now: Date) async throws(SourceFailure) -> [Pipeline] {
    let slugs = (settings?.projectSlugs ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard let settings, !settings.apiToken.isEmpty, !slugs.isEmpty else { throw .notConfigured }
    let token = settings.apiToken
    let pipelinesBySlug = try await Self.concurrentMap(slugs) { slug throws(SourceFailure) in
      try await fetchProject(slug: slug, token: token, now: now)
    }
    return pipelinesBySlug.flatMap(\.self)
  }

  private func fetchProject(slug: String, token: String, now: Date) async throws(SourceFailure) -> [Pipeline] {
    guard let pageURL = Self.apiURL("project/\(slug)/pipeline/mine") else { throw .unexpected("\(slug) not found") }
    let page: PipelinePage
    do {
      page = try await get(pageURL, token: token)
    } catch .unexpected("HTTP 404") {
      throw .unexpected("\(slug) not found")
    }
    let recentItems = page.items.filter { now.timeIntervalSince($0.createdAt) <= pipelineWindow }
    return try await Self.concurrentMap(recentItems) { item throws(SourceFailure) in
      let state: PipelineState
      // The pipeline state reads "created" for running, finished and failed pipelines alike.
      if item.state == "errored" {
        state = .failed
      } else {
        guard let workflowURL = Self.apiURL("pipeline/\(item.id)/workflow") else {
          throw .unexpected("CircleCI response did not decode")
        }
        let workflows: WorkflowList = try await get(workflowURL, token: token)
        state = Self.state(workflowStatuses: workflows.items.map(\.status))
      }
      return Pipeline(
        projectSlug: item.projectSlug, number: item.number, ref: item.vcs.tag ?? item.vcs.branch ?? "",
        refIsTag: item.vcs.tag != nil, triggerType: item.trigger.type,
        hasPullRequest: !(item.vcs.reviewUrl ?? "").isEmpty, createdAt: item.createdAt, state: state,
        url: Self.webURL(slug: item.projectSlug, number: item.number))
    }
  }

  // Runs the requests at the same time and keeps the input order. The first failure in input order wins.
  private static func concurrentMap<Input: Sendable, Output: Sendable>(
    _ inputs: [Input], _ transform: @escaping @Sendable (Input) async throws(SourceFailure) -> Output
  ) async throws(SourceFailure) -> [Output] {
    let results = await withTaskGroup(of: (Int, Result<Output, SourceFailure>).self) { group in
      for (index, input) in inputs.enumerated() {
        group.addTask {
          do throws(SourceFailure) {
            return (index, .success(try await transform(input)))
          } catch {
            return (index, .failure(error))
          }
        }
      }
      var resultsByIndex = [Result<Output, SourceFailure>?](repeating: nil, count: inputs.count)
      for await (index, result) in group { resultsByIndex[index] = result }
      return resultsByIndex
    }
    var outputs: [Output] = []
    for result in results { outputs.append(try result!.get()) }
    return outputs
  }

  // Canceled and not_run workflows are final and do not change the state.
  private static func state(workflowStatuses statuses: [String]) -> PipelineState {
    if statuses.contains(where: failedStatuses.contains) { return .failed }
    if statuses.contains("on_hold") { return .onHold }
    if statuses.contains("running") { return .running }
    return .succeeded
  }

  // A slug with characters a URL cannot hold, such as a space, gives nil.
  private static func apiURL(_ path: String) -> URL? {
    URL(string: "\(baseURL.absoluteString)/\(path)", encodingInvalidCharacters: false)
  }

  // The web app spells the VCS prefix out: "gh/acme/app-web" opens at "pipelines/github/acme/app-web".
  private static func webURL(slug: String, number: Int) -> URL {
    var parts = slug.split(separator: "/").map(String.init)
    if parts.first == "gh" { parts[0] = "github" }
    if parts.first == "bb" { parts[0] = "bitbucket" }
    return URL(string: "https://app.circleci.com/pipelines/\(parts.joined(separator: "/"))/\(number)")!
  }

  private func get<Response: Decodable>(_ url: URL, token: String) async throws(SourceFailure) -> Response {
    var request = URLRequest(url: url)
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
