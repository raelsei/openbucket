import Foundation
import OpenBucketCore
import Security
import Testing

@testable import OpenBucket

@Test func profileFileContainsNoCredentials() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("openbucket-\(UUID().uuidString)", isDirectory: true)
  let fileURL = directory.appendingPathComponent("profiles.json")
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ProfileStore(fileURL: fileURL)
  let profile = ConnectionProfile(
    name: "Garage",
    endpoint: try S3Endpoint("https://s3.example.com/prefix/"),
    region: "garage",
    addressingStyle: .path,
    knownBucket: "photos"
  )

  try await store.save([profile])
  try await store.save([])
  #expect(try await store.load().isEmpty)
  try await store.save([profile])
  let data = try Data(contentsOf: fileURL)
  let text = try #require(String(data: data, encoding: .utf8))

  #expect(text.contains("Garage"))
  #expect(text.contains(profile.credentialReference.uuidString))
  #expect(!text.contains("secretAccessKey"))
  let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
  #expect(attributes[.posixPermissions] as? Int == 0o600)
  let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
  #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)
  #expect(try await store.load() == [profile])
}

@Test func keychainRoundTripAndDeletion() async throws {
  let store = KeychainCredentialStore(service: "dev.openbucket.tests.\(UUID().uuidString)")
  let reference = UUID()
  let credentials = S3Credentials(
    accessKeyID: "test-access-key",
    secretAccessKey: "test-secret-key",
    sessionToken: "test-session-token"
  )
  defer { Task { try? await store.delete(reference: reference) } }

  try await store.save(credentials, reference: reference)
  let loaded = try await store.load(reference: reference)
  #expect(loaded.accessKeyID == credentials.accessKeyID)
  #expect(loaded.secretAccessKey == credentials.secretAccessKey)
  #expect(loaded.sessionToken == credentials.sessionToken)

  try await store.delete(reference: reference)
  do {
    _ = try await store.load(reference: reference)
    Issue.record("A deleted Keychain entry loaded successfully")
  } catch CredentialStoreError.notFound {
  }
}

@Test func credentialsPreferProtectedMacKeychain() async throws {
  let service = "dev.openbucket.tests.\(UUID().uuidString)"
  let store = KeychainCredentialStore(service: service)
  let reference = UUID()
  defer { Task { try? await store.delete(reference: reference) } }
  try await store.save(
    S3Credentials(accessKeyID: "test-access", secretAccessKey: "test-secret"),
    reference: reference
  )

  let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: reference.uuidString,
    kSecUseDataProtectionKeychain as String: true,
    kSecReturnAttributes as String: true,
  ]
  var result: CFTypeRef?
  let status = SecItemCopyMatching(query as CFDictionary, &result)
  if status == errSecSuccess {
    let attributes = try #require(result as? [String: Any])
    #expect(
      attributes[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
  } else {
    #expect(status == errSecMissingEntitlement || status == errSecItemNotFound)
    var legacyQuery = query
    legacyQuery.removeValue(forKey: kSecUseDataProtectionKeychain as String)
    #expect(SecItemCopyMatching(legacyQuery as CFDictionary, &result) == errSecSuccess)
  }
}

@Test func existingLoginKeychainCredentialRemainsReadable() async throws {
  let service = "dev.openbucket.tests.\(UUID().uuidString)"
  let reference = UUID()
  let store = KeychainCredentialStore(service: service)
  defer { Task { try? await store.delete(reference: reference) } }
  let data = try JSONEncoder().encode(["accessKeyID": "legacy-access", "secretAccessKey": "legacy-secret"])
  let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: reference.uuidString,
    kSecValueData as String: data,
  ]
  #expect(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
  let loaded = try await store.load(reference: reference)
  #expect(loaded.accessKeyID == "legacy-access")
  #expect(loaded.secretAccessKey == "legacy-secret")
}
