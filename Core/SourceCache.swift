import Foundation

public struct Cached<Value: Codable & Sendable>: Codable, Sendable {
  public var value: Value
  public var fetchedAt: Date

  public init(value: Value, fetchedAt: Date) {
    self.value = value
    self.fetchedAt = fetchedAt
  }
}

public struct SourceCache: Sendable {
  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  // A missing or undecodable file (old format, partial write) counts as no cache.
  public func load<Value>(_ type: Value.Type, name: String) -> Cached<Value>? {
    guard let data = try? Data(contentsOf: fileURL(name)) else { return nil }
    return try? JSONDecoder().decode(Cached<Value>.self, from: data)
  }

  public func save<Value>(_ cached: Cached<Value>, name: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(cached).write(to: fileURL(name), options: .atomic)
  }

  // A missing file is the normal case, so a failed removal is not an error.
  public func remove(name: String) {
    try? FileManager.default.removeItem(at: fileURL(name))
  }

  private func fileURL(_ name: String) -> URL {
    directory.appendingPathComponent("\(name).json")
  }
}
