import Foundation
import Testing

@testable import Tower

struct GitHubReconnectTests {
  @Test func withoutGhOpensTheCLISite() {
    var openedURLs: [URL] = []
    GitHubReconnect.open(ghPath: nil) { openedURLs.append($0) }
    #expect(openedURLs == [URL(string: "https://cli.github.com")!])
  }

  @Test func withGhWritesAnExecutableLoginScriptAndOpensIt() throws {
    let scriptDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("tower-reconnect-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scriptDirectory) }
    var openedURLs: [URL] = []

    GitHubReconnect.open(ghPath: "/opt/homebrew/bin/gh", scriptDirectory: scriptDirectory) { openedURLs.append($0) }

    let scriptURL = scriptDirectory.appendingPathComponent("tower-gh-login.command")
    #expect(openedURLs == [scriptURL])
    #expect(try String(contentsOf: scriptURL, encoding: .utf8) == "#!/bin/zsh\n'/opt/homebrew/bin/gh' auth login\n")
    let permissions = try FileManager.default.attributesOfItem(atPath: scriptURL.path)[.posixPermissions] as? Int
    #expect(permissions == 0o755)
  }

  @Test func unwritableScriptFolderOpensNothing() {
    let missingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("tower-missing-\(UUID().uuidString)")
    var openedURLs: [URL] = []
    GitHubReconnect.open(ghPath: "/opt/homebrew/bin/gh", scriptDirectory: missingDirectory) { openedURLs.append($0) }
    #expect(openedURLs.isEmpty)
  }
}
