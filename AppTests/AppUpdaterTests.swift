import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Tower

// A stand-in brew that exits with the given status for each subcommand: `list`, `update` and `upgrade`.
private func makeFakeBrew(listExitStatus: Int32, updateExitStatus: Int32 = 0, upgradeExitStatus: Int32 = 0) throws -> URL {
  let scriptURL = FileManager.default.temporaryDirectory.appending(path: "fake-brew-\(UUID().uuidString)")
  let script = """
    #!/bin/sh
    case "$1" in
      list) exit \(listExitStatus) ;;
      update) exit \(updateExitStatus) ;;
      upgrade) exit \(upgradeExitStatus) ;;
    esac
    exit 1
    """
  try Data(script.utf8).write(to: scriptURL)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
  return scriptURL
}

@MainActor private func preparedUpdater(brewURLs: [URL]) async -> AppUpdater {
  let appUpdater = AppUpdater(findBrews: { brewURLs.map(\.path) })
  await appUpdater.prepareIfNeeded()
  return appUpdater
}

// Lays the view out once, so SwiftUI evaluates its body for the updater's current state.
@MainActor private func render(_ view: some View) {
  let hostingView = NSHostingView(rootView: view)
  hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 80)
  hostingView.layoutSubtreeIfNeeded()
}

@MainActor struct AppUpdaterTests {
  @Test func usesTheBrewThatOwnsTheCask() async throws {
    let brewWithoutCask = try makeFakeBrew(listExitStatus: 1)
    let brewWithCask = try makeFakeBrew(listExitStatus: 0)
    defer {
      try? FileManager.default.removeItem(at: brewWithoutCask)
      try? FileManager.default.removeItem(at: brewWithCask)
    }
    let appUpdater = await preparedUpdater(brewURLs: [brewWithoutCask, brewWithCask])
    #expect(appUpdater.state == .ready)
    #expect(appUpdater.brewPath == brewWithCask.path)
  }

  @Test func noBrewOwnsTheCaskMeansUnavailable() async throws {
    let brewWithoutCask = try makeFakeBrew(listExitStatus: 1)
    defer { try? FileManager.default.removeItem(at: brewWithoutCask) }
    let appUpdater = await preparedUpdater(brewURLs: [brewWithoutCask])
    #expect(appUpdater.state == .unavailable)
    #expect(appUpdater.brewPath == nil)
  }

  @Test func noBrewMeansUnavailable() async {
    let appUpdater = await preparedUpdater(brewURLs: [])
    #expect(appUpdater.state == .unavailable)
    #expect(appUpdater.statusMessage == nil)
  }

  // The test host bundle keeps its version, so a successful upgrade finds no newer version and never relaunches.
  @Test func upgradeWithoutANewerBundleReportsNoNewVersion() async throws {
    let fakeBrew = try makeFakeBrew(listExitStatus: 0)
    defer { try? FileManager.default.removeItem(at: fakeBrew) }
    let appUpdater = await preparedUpdater(brewURLs: [fakeBrew])
    await appUpdater.update()
    #expect(appUpdater.state == .noNewVersion)
    #expect(appUpdater.statusMessage == "No new version yet.")
  }

  @Test func failedHomebrewUpdateSkipsTheUpgrade() async throws {
    let fakeBrew = try makeFakeBrew(listExitStatus: 0, updateExitStatus: 1)
    defer { try? FileManager.default.removeItem(at: fakeBrew) }
    let appUpdater = await preparedUpdater(brewURLs: [fakeBrew])
    await appUpdater.update()
    #expect(appUpdater.state == .failed)
    #expect(appUpdater.statusMessage == "Update failed.")
  }

  @Test func failedUpgradeReportsFailure() async throws {
    let fakeBrew = try makeFakeBrew(listExitStatus: 0, upgradeExitStatus: 1)
    defer { try? FileManager.default.removeItem(at: fakeBrew) }
    let appUpdater = await preparedUpdater(brewURLs: [fakeBrew])
    await appUpdater.update()
    #expect(appUpdater.state == .failed)
  }

  @Test func updateDoesNothingWithoutABrew() async {
    let appUpdater = await preparedUpdater(brewURLs: [])
    await appUpdater.update()
    #expect(appUpdater.state == .unavailable)
  }

  @Test func controlsRenderForEveryReachableState() async throws {
    let unavailableUpdater = await preparedUpdater(brewURLs: [])
    render(UpdateControls(appUpdater: unavailableUpdater))
    render(UpdateStatusRow(appUpdater: unavailableUpdater))

    let fakeBrew = try makeFakeBrew(listExitStatus: 0, updateExitStatus: 1)
    defer { try? FileManager.default.removeItem(at: fakeBrew) }
    let failingUpdater = await preparedUpdater(brewURLs: [fakeBrew])
    render(UpdateControls(appUpdater: failingUpdater))
    await failingUpdater.update()
    #expect(failingUpdater.state == .failed)
    render(UpdateControls(appUpdater: failingUpdater))
    render(UpdateStatusRow(appUpdater: failingUpdater))
  }
}
