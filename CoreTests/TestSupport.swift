import Core
import Foundation

final class StubTransport: HTTPTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var recordedRequests: [URLRequest] = []
  private let respond: @Sendable (URLRequest) throws -> (Data, Int)

  init(respond: @escaping @Sendable (URLRequest) throws -> (Data, Int)) {
    self.respond = respond
  }

  var requests: [URLRequest] { lock.withLock { recordedRequests } }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lock.withLock { recordedRequests.append(request) }
    let (data, statusCode) = try respond(request)
    return (data, HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!)
  }
}

func fixture(_ name: String) throws -> Data {
  let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
  return try Data(contentsOf: fixturesDirectory.appendingPathComponent(name))
}

func isoDate(_ text: String) -> Date {
  try! Date(text, strategy: .iso8601)
}
