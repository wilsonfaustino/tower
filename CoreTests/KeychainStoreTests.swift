import Core
import Foundation
import Testing

// Each test uses its own account, so the real Jira and CircleCI tokens stay untouched.
private func withTestAccount(_ body: (String) throws -> Void) rethrows {
  let account = "tower-tests-\(UUID().uuidString)"
  KeychainStore.delete(account: account)
  defer { KeychainStore.delete(account: account) }
  try body(account)
}

struct KeychainStoreTests {
  @Test func missingAccountReadsNil() {
    withTestAccount { account in
      #expect(KeychainStore.read(account: account) == nil)
    }
  }

  @Test func writeThenReadRoundTrips() throws {
    try withTestAccount { account in
      try KeychainStore.write("first-token", account: account)
      #expect(KeychainStore.read(account: account) == "first-token")
    }
  }

  @Test func secondWriteReplacesTheValue() throws {
    try withTestAccount { account in
      try KeychainStore.write("first-token", account: account)
      try KeychainStore.write("second-token", account: account)
      #expect(KeychainStore.read(account: account) == "second-token")
    }
  }

  @Test func deleteRemovesTheValue() throws {
    try withTestAccount { account in
      try KeychainStore.write("first-token", account: account)
      KeychainStore.delete(account: account)
      #expect(KeychainStore.read(account: account) == nil)
    }
  }
}
