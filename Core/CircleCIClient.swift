import Foundation

public struct CircleCISettings: Equatable, Sendable {
  public var apiToken: String
  public var projectSlugs: [String]

  public init(apiToken: String, projectSlugs: [String]) {
    self.apiToken = apiToken
    self.projectSlugs = projectSlugs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }
}

// Pipelines older than this leave the panel, so the client does not read their workflows.
let pipelineWindow: TimeInterval = 24 * 3600

public struct CircleCIClient: Sendable {
  private static let baseURL = URL(string: "https://circleci.com/api/v2")!
  private static let failedStatuses: Set<String> = ["failed", "error", "failing", "unauthorized"]
  private static let setupPipelineStates: Set<String> = ["setup-pending", "setup", "pending"]
  // Keeps a burst of workflow requests small for an owner with many recent pipelines.
  private static let maxWorkflowRequestsInFlight = 4

  private let settings: CircleCISettings?
  private let transport: HTTPTransport

  public init(settings: CircleCISettings?, transport: HTTPTransport) {
    self.settings = settings
    self.transport = transport
  }

  public func fetch(now: Date) async throws(SourceFailure) -> [Pipeline] {
    guard let settings, !settings.apiToken.isEmpty, !settings.projectSlugs.isEmpty else { throw .notConfigured }
    let token = settings.apiToken
    let candidatesBySlug = try await Self.concurrentMap(settings.projectSlugs) { slug throws(SourceFailure) in
      try await fetchProject(slug: slug, token: token, now: now)
    }
    let candidates = candidatesBySlug.flatMap(\.self)
    // The queue shows only the newest pipeline per key, and none when that one has a PR.
    let newestPipelines = newestPipelinePerKey(candidates.map(\.pipeline))
    let newestCandidates = candidates.filter { newestPipelines.contains($0.pipeline) }
    return try await Self.concurrentMap(newestCandidates, maxConcurrent: Self.maxWorkflowRequestsInFlight) {
      candidate throws(SourceFailure) in
      try await withWorkflowState(candidate, token: token)
    }
  }

  private func fetchProject(slug: String, token: String, now: Date) async throws(SourceFailure) -> [Candidate] {
    guard let pageURL = Self.apiURL("project/\(slug)/pipeline/mine") else { throw .unexpected("\(slug) not found") }
    let page: PipelinePage
    do {
      page = try await get(pageURL, token: token)
    } catch .unexpected("HTTP 404") {
      throw .unexpected("\(slug) not found")
    }
    return page.items.filter { now.timeIntervalSince($0.createdAt) <= pipelineWindow }.map { item in
      // The workflow state replaces this placeholder state.
      let pipeline = Pipeline(
        projectSlug: item.projectSlug, number: item.number, ref: item.vcs.tag ?? item.vcs.branch ?? "",
        refIsTag: item.vcs.tag != nil, triggerType: item.trigger.type,
        hasPullRequest: !(item.vcs.reviewUrl ?? "").isEmpty, createdAt: item.createdAt, state: .succeeded,
        url: Self.webURL(slug: item.projectSlug, number: item.number))
      return Candidate(id: item.id, pipelineState: item.state, pipeline: pipeline)
    }
  }

  // A pipeline with a PR leaves the queue, so it keeps the placeholder state without a workflow request.
  private func withWorkflowState(_ candidate: Candidate, token: String) async throws(SourceFailure) -> Pipeline {
    var pipeline = candidate.pipeline
    if pipeline.hasPullRequest { return pipeline }
    // The pipeline state reads "created" for running, finished and failed pipelines alike.
    if candidate.pipelineState == "errored" {
      pipeline.state = .failed
      return pipeline
    }
    guard let workflowURL = Self.apiURL("pipeline/\(candidate.id)/workflow") else {
      throw .unexpected("CircleCI response did not decode")
    }
    let workflows: WorkflowList = try await get(workflowURL, token: token)
    if workflows.items.isEmpty {
      // No workflows means setup still runs, or the config filters removed every workflow.
      pipeline.state = Self.setupPipelineStates.contains(candidate.pipelineState) ? .running : .succeeded
    } else {
      // A rerun adds a new workflow with the same name, so only the newest run of each name counts.
      let newestRuns = Dictionary(grouping: workflows.items, by: \.name).values.compactMap { runs in
        runs.max { $0.createdAt < $1.createdAt }
      }
      pipeline.state = Self.state(workflowStatuses: newestRuns.map(\.status))
    }
    return pipeline
  }

  // Runs up to maxConcurrent requests at a time and keeps the input order. The first failure in input order wins.
  private static func concurrentMap<Input: Sendable, Output: Sendable>(
    _ inputs: [Input], maxConcurrent: Int = .max,
    _ transform: @escaping @Sendable (Input) async throws(SourceFailure) -> Output
  ) async throws(SourceFailure) -> [Output] {
    let results = await withTaskGroup(of: (Int, Result<Output, SourceFailure>).self) { group in
      func addTask(index: Int) {
        let input = inputs[index]
        group.addTask {
          do throws(SourceFailure) {
            return (index, .success(try await transform(input)))
          } catch {
            return (index, .failure(error))
          }
        }
      }
      var nextIndex = 0
      while nextIndex < min(maxConcurrent, inputs.count) {
        addTask(index: nextIndex)
        nextIndex += 1
      }
      var resultsByIndex = [Result<Output, SourceFailure>?](repeating: nil, count: inputs.count)
      for await (index, result) in group {
        resultsByIndex[index] = result
        if nextIndex < inputs.count {
          addTask(index: nextIndex)
          nextIndex += 1
        }
      }
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

private struct Candidate: Sendable {
  var id: String
  var pipelineState: String
  var pipeline: Pipeline
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
  struct Workflow: Decodable {
    var name: String
    var status: String
    var createdAt: Date
  }

  var items: [Workflow]
}
