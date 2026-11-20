import Foundation
import Testing

@testable import Tower

// A stand-in brew that answers `brew list --cask` with the given exit status.
private func makeFakeBrew(listExitStatus: Int32) throws -> URL {
  let scriptURL = FileManager.default.temporaryDirectory.appending(path: "fake-brew-\(UUID().uuidString)")
  try Data("#!/bin/sh\nexit \(listExitStatus)\n".utf8).write(to: scriptURL)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
  return scriptURL
}

@MainActor struct AppUpdaterTests {
  @Test func usesTheBrewThatOwnsTheCask() async throws {
    let brewWithoutCask = try makeFakeBrew(listExitStatus: 1)
    let brewWithCask = try makeFakeBrew(listExitStatus: 0)
    defer {
      try? FileManager.default.removeItem(at: brewWithoutCask)
      try? FileManager.default.removeItem(at: brewWithCask)
    }
    let appUpdater = AppUpdater(findBrews: { [brewWithoutCask.path, brewWithCask.path] })
    await appUpdater.prepareIfNeeded()
    #expect(appUpdater.state == .ready)
    #expect(appUpdater.brewPath == brewWithCask.path)
  }

  @Test func noBrewOwnsTheCaskMeansUnavailable() async throws {
    let brewWithoutCask = try makeFakeBrew(listExitStatus: 1)
    defer { try? FileManager.default.removeItem(at: brewWithoutCask) }
    let appUpdater = AppUpdater(findBrews: { [brewWithoutCask.path] })
    await appUpdater.prepareIfNeeded()
    #expect(appUpdater.state == .unavailable)
    #expect(appUpdater.brewPath == nil)
  }

  @Test func noBrewMeansUnavailable() async {
    let appUpdater = AppUpdater(findBrews: { [] })
    await appUpdater.prepareIfNeeded()
    #expect(appUpdater.state == .unavailable)
  }
}
