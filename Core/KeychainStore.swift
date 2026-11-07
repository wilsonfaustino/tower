import Foundation
import Security

public enum KeychainStore {
  private static let service = "dev.wilsonfaustino.Tower"
  public static let jiraTokenAccount = "jira-api-token"
  public static let circleciTokenAccount = "circleci-api-token"

  public static func read(account: String) -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  public static func write(_ value: String, account: String) throws {
    let data = Data(value.utf8)
    let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }
    var addQuery = baseQuery(account: account)
    addQuery[kSecValueData as String] = data
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
  }

  public static func delete(account: String) {
    SecItemDelete(baseQuery(account: account) as CFDictionary)
  }

  private static func baseQuery(account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }
}

public struct KeychainError: Error, Equatable {
  public let status: OSStatus
}
