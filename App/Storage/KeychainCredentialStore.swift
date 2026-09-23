import Foundation
import OpenBucketCore
import Security

enum CredentialStoreError: Error, Equatable {
  case notFound
  case invalidData
  case keychain(OSStatus)
}

actor KeychainCredentialStore: CredentialStore {
  private struct Record: Codable {
    let accessKeyID: String
    let secretAccessKey: String
    let sessionToken: String?

    init(_ credentials: S3Credentials) {
      accessKeyID = credentials.accessKeyID
      secretAccessKey = credentials.secretAccessKey
      sessionToken = credentials.sessionToken
    }

    var credentials: S3Credentials {
      S3Credentials(
        accessKeyID: accessKeyID,
        secretAccessKey: secretAccessKey,
        sessionToken: sessionToken
      )
    }
  }

  private let service: String

  init(service: String = "dev.openbucket.credentials") {
    self.service = service
  }

  func save(_ credentials: S3Credentials, reference: UUID) throws {
    let data = try JSONEncoder().encode(Record(credentials))
    do {
      try save(data, reference: reference, dataProtection: true)
      try delete(reference: reference, dataProtection: false)
    } catch CredentialStoreError.keychain(errSecMissingEntitlement) {
      try save(data, reference: reference, dataProtection: false)
    }
  }

  private func save(_ data: Data, reference: UUID, dataProtection: Bool) throws {
    let query = itemQuery(reference: reference, dataProtection: dataProtection)
    var attributes = query
    attributes[kSecValueData as String] = data
    if dataProtection {
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let update = [kSecValueData as String: data] as CFDictionary
      let updateStatus = SecItemUpdate(query as CFDictionary, update)
      guard updateStatus == errSecSuccess else { throw CredentialStoreError.keychain(updateStatus) }
    } else if status != errSecSuccess {
      throw CredentialStoreError.keychain(status)
    }
  }

  func load(reference: UUID) throws -> S3Credentials {
    do {
      if let protected = try read(reference: reference, dataProtection: true) {
        return protected
      }
    } catch CredentialStoreError.keychain(errSecMissingEntitlement) {
    }
    guard let legacy = try read(reference: reference, dataProtection: false) else {
      throw CredentialStoreError.notFound
    }
    try save(legacy, reference: reference)
    return legacy
  }

  private func read(reference: UUID, dataProtection: Bool) throws -> S3Credentials? {
    var query = itemQuery(reference: reference, dataProtection: dataProtection)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
    guard let data = result as? Data,
      let record = try? JSONDecoder().decode(Record.self, from: data)
    else { throw CredentialStoreError.invalidData }
    return record.credentials
  }

  func delete(reference: UUID) throws {
    do {
      try delete(reference: reference, dataProtection: true)
    } catch CredentialStoreError.keychain(errSecMissingEntitlement) {
    }
    try delete(reference: reference, dataProtection: false)
  }

  private func delete(reference: UUID, dataProtection: Bool) throws {
    let status = SecItemDelete(
      itemQuery(reference: reference, dataProtection: dataProtection) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialStoreError.keychain(status)
    }
  }

  private func itemQuery(reference: UUID, dataProtection: Bool) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: reference.uuidString,
    ]
    if dataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }
}
