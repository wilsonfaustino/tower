#if DEBUG
import Core
import Foundation
import Testing

private let demoNow = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func demoSections(_ name: DemoScenario.Name) -> [QueueSection] {
  let scenario = DemoScenario(name: name, now: demoNow)
  let snapshot = scenario.githubSnapshot
  let input = QueueInput(
    viewerLogin: snapshot?.viewerLogin ?? "", authoredPullRequests: snapshot?.authoredPullRequests ?? [],
    reviewRequests: snapshot?.reviewRequests ?? [], jiraTickets: scenario.jiraTickets ?? [],
    pipelines: scenario.pipelines ?? [], dismissedPipelines: [],
    mergedPullRequests: snapshot?.recentlyMergedPullRequests ?? [])
  return buildQueue(input, now: demoNow)
}

private func rowCount(_ sections: [QueueSection]) -> Int {
  sections.flatMap(\.items).map { max($0.children.count, 1) }.reduce(0, +)
}

struct DemoScenarioTests {
  @Test func typicalFillsEverySection() {
    #expect(demoSections(.typical).map(\.kind) == SectionKind.allCases)
  }

  @Test func typicalShowsPassedAndFailedChecksOnWaitingRows() {
    let waitingItems = demoSections(.typical).first { $0.kind == .waiting }?.items ?? []
    let checks = waitingItems.flatMap { [$0] + $0.children }.compactMap(\.strip?.checks)
    #expect(checks.contains(.passed))
    #expect(checks.contains(.failed))
    #expect(checks.contains(.running))
  }

  @Test(arguments: [DemoScenario.Name.typical, .longList])
  func showsARepoGroupWithAStackInWaiting(name: DemoScenario.Name) throws {
    let waitingItems = demoSections(name).first { $0.kind == .waiting }?.items ?? []
    let groupItem = try #require(waitingItems.first { $0.id == "repo:demo-org/infra" })
    #expect(groupItem.children.map(\.reference) == ["#94", "#93", "#90", "#91"])
    #expect(groupItem.badge?.text == "1 changes requested")
  }

  @Test func typicalShowsMoreThanOneIssueTypeOnTidyRows() {
    let tidyItems = demoSections(.typical).first { $0.kind == .tidy }?.items ?? []
    #expect(Set(tidyItems.map(\.symbol)).count > 1)
  }

  @Test func longListListsTheOnHoldPipelineAfterTwoRunningOnes() {
    let watchItems = demoSections(.longList).first { $0.kind == .watch }?.items ?? []
    #expect(watchItems.prefix(2).allSatisfy { $0.badge?.text == "Running" })
    #expect(watchItems.dropFirst(2).contains { $0.badge?.text == "Needs approval" })
  }

  @Test func longListHasEnoughRowsToScroll() {
    #expect(rowCount(demoSections(.longList)) >= 30)
  }

  @Test func clearSkiesHasNoRowsButASummary() {
    #expect(demoSections(.clearSkies).isEmpty)
    #expect(DemoScenario(name: .clearSkies, now: demoNow).githubSnapshot?.reviewsSubmittedToday ?? 0 > 0)
  }

  @Test func offlineHasNoDataAndEverySourceFailsOnTheNetwork() {
    let scenario = DemoScenario(name: .offline, now: demoNow)
    #expect(scenario.githubSnapshot == nil && scenario.jiraTickets == nil && scenario.pipelines == nil)
    #expect([scenario.githubStatus, scenario.jiraStatus, scenario.circleciStatus].allSatisfy { $0 == .failed(.network) })
  }

  @Test func authFailureKeepsRowsAndFailsGitHubSignIn() {
    let scenario = DemoScenario(name: .authFailure, now: demoNow)
    #expect(scenario.githubStatus == .failed(.authentication))
    #expect(!demoSections(.authFailure).isEmpty)
  }

  @Test func onlyUpdateHasANewerVersion() {
    #expect(DemoScenario(name: .update, now: demoNow).availableVersion == "1.0.0")
    #expect(demoSections(.update).map(\.kind) == SectionKind.allCases)
    let otherNames = DemoScenario.Name.allCases.filter { $0 != .update }
    #expect(otherNames.allSatisfy { DemoScenario(name: $0, now: demoNow).availableVersion == nil })
  }

  @Test func launchValueReadsTheTokenAfterTheFlag() {
    #expect(DemoScenario.launchValue(arguments: ["Tower", "-demo", "long-list"]) == "long-list")
    #expect(DemoScenario.launchValue(arguments: ["Tower", "-demo"]) == "")
    #expect(DemoScenario.launchValue(arguments: ["Tower"]) == nil)
  }

  @Test func unknownLaunchValueGivesTypical() {
    #expect(DemoScenario.Name(launchValue: "nope") == .typical)
    #expect(DemoScenario.Name(launchValue: "offline") == .offline)
  }
}
#endif
