import Foundation

// Hides one failed pipeline only while its newest workflow stays the same, so a rerun that fails shows it again.
public struct PipelineDismissal: Codable, Hashable, Sendable {
  public var pipelineId: String
  public var newestWorkflowId: String?

  public init(pipelineId: String, newestWorkflowId: String?) {
    self.pipelineId = pipelineId
    self.newestWorkflowId = newestWorkflowId
  }
}

extension Pipeline {
  public var dismissal: PipelineDismissal { PipelineDismissal(pipelineId: id, newestWorkflowId: newestWorkflowId) }
}

// Keeps only the dismissals of pipelines CircleCI still returns inside the pipeline window, so the list does not grow.
public func prunedDismissals(
  _ dismissals: Set<PipelineDismissal>, pipelines: [Pipeline], now: Date
) -> Set<PipelineDismissal> {
  let recentPipelineIds = Set(pipelines.filter { now.timeIntervalSince($0.createdAt) <= pipelineWindow }.map(\.id))
  return dismissals.filter { recentPipelineIds.contains($0.pipelineId) }
}
