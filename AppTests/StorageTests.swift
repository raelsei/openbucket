import Foundation
import OpenBucketCore
import Testing

@testable import OpenBucket

@Test func profileFileContainsNoCredentials() async throws {
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("openbucket-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: fileURL) }
  let store = ProfileStore(fileURL: fileURL)
  let profile = ConnectionProfile(
    name: "Garage",
    endpoint: try S3Endpoint("https://s3.example.com/prefix/"),
    region: "garage",
    addressingStyle: .path,
    knownBucket: "photos"
  )

  try await store.save([profile])
  let data = try Data(contentsOf: fileURL)
  let text = try #require(String(data: data, encoding: .utf8))

  #expect(text.contains("Garage"))
  #expect(text.contains(profile.credentialReference.uuidString))
  #expect(!text.contains("secretAccessKey"))
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
