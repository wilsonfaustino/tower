import Core
import Foundation
import Testing

private func temporaryCache() -> (SourceCache, URL) {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tower-cache-\(UUID().uuidString)")
  return (SourceCache(directory: directory), directory)
}

struct SourceCacheTests {
  @Test func saveThenLoadRoundTrips() throws {
    let (cache, _) = temporaryCache()
    let fetchedAt = isoDate("2027-01-15T12:00:00Z")
    try cache.save(Cached(value: ["a", "b"], fetchedAt: fetchedAt), name: "jira")
    let loaded = cache.load([String].self, name: "jira")
    #expect(loaded?.value == ["a", "b"])
    #expect(loaded?.fetchedAt == fetchedAt)
  }

  @Test func missingFileLoadsNil() {
    let (cache, _) = temporaryCache()
    #expect(cache.load([String].self, name: "github") == nil)
  }

  @Test func undecodableFileLoadsNil() throws {
    let (cache, directory) = temporaryCache()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not json {".utf8).write(to: directory.appendingPathComponent("github.json"))
    #expect(cache.load([String].self, name: "github") == nil)
  }
}
