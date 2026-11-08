import Core
import Foundation
import Testing

struct URLSessionTransportTests {
  // A file URL gives a plain URLResponse with no network use, which the transport rejects.
  @Test func nonHTTPResponseThrowsBadServerResponse() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("tower-transport-\(UUID().uuidString).json")
    try Data("{}".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }
    await #expect(throws: URLError(.badServerResponse)) {
      _ = try await URLSessionTransport().send(URLRequest(url: fileURL))
    }
  }
}
