import Foundation

public protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
  public init() {}

  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return (data, httpResponse)
  }
}

public enum SourceFailure: Error, Equatable, Sendable {
  case authentication
  case network
  case notConfigured
  case unexpected(String)
}

// Sends the request and maps transport errors and auth status codes to SourceFailure.
func sendMapped(_ request: URLRequest, transport: HTTPTransport) async throws(SourceFailure) -> Data {
  let data: Data
  let response: HTTPURLResponse
  do {
    (data, response) = try await transport.send(request)
  } catch is URLError {
    throw .network
  } catch {
    throw .unexpected(error.localizedDescription)
  }
  switch response.statusCode {
  case 200..<300: return data
  case 401, 403: throw .authentication
  default: throw .unexpected("HTTP \(response.statusCode)")
  }
}
