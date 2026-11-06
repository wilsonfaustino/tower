import AppKit
import Core

// Tower cannot run `gh auth login` without a terminal. Opening a .command file makes
// Terminal run it, which needs no Automation permission.
enum GitHubReconnect {
  static func open(ghPath: String?) {
    guard let ghPath else {
      NSWorkspace.shared.open(URL(string: "https://cli.github.com")!)
      return
    }
    let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("tower-gh-login.command")
    let script = "#!/bin/zsh\n'\(ghPath)' auth login\n"
    do {
      try script.write(to: scriptURL, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    } catch {
      return
    }
    NSWorkspace.shared.open(scriptURL)
  }
}
