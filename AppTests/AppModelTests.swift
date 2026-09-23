import Foundation
import OpenBucketCore
import Testing

@testable import OpenBucket

@MainActor
@Test func failedProfileEditRemovesNewKeychainItem() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("openbucket-model-\(UUID().uuidString)", isDirectory: true)
  let fileURL = directory.appendingPathComponent("profiles.json")
  defer { try? FileManager.default.removeItem(at: directory) }

  let credentials = KeychainCredentialStore(service: "dev.openbucket.tests.\(UUID().uuidString)")
  let model = AppModel(
    repository: EmptyRepository(),
    profileStore: ProfileStore(fileURL: fileURL),
    credentialStore: credentials
  )
  let original = ConnectionProfile(
    name: "Garage",
    endpoint: try S3Endpoint("http://127.0.0.1:23900"),
    region: "garage",
    addressingStyle: .path
  )
  try await model.save(
    original,
    credentials: S3Credentials(accessKeyID: "original", secretAccessKey: "original-secret")
  )

  try FileManager.default.removeItem(at: fileURL)
  try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
  let edited = ConnectionProfile(
    id: original.id,
    name: "Garage edited",
    endpoint: original.endpoint,
    region: original.region,
    addressingStyle: original.addressingStyle
  )
  do {
    try await model.save(
      edited,
      credentials: S3Credentials(accessKeyID: "new", secretAccessKey: "new-secret")
    )
    Issue.record("Saving a profile over a directory unexpectedly succeeded")
  } catch {
    #expect(model.profiles == [original])
    #expect(try await credentials.load(reference: original.credentialReference).accessKeyID == "original")
    do {
      _ = try await credentials.load(reference: edited.credentialReference)
      Issue.record("The failed edit left a Keychain item behind")
    } catch CredentialStoreError.notFound {
    }
  }
  try await credentials.delete(reference: original.credentialReference)
}

@MainActor
@Test func downloadKeepsSourceWhenSelectionChanges() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("openbucket-download-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let repository = RecordingDownloadRepository()
  let credentials = MemoryCredentialStore()
  let model = AppModel(
    repository: repository,
    profileStore: ProfileStore(fileURL: directory.appendingPathComponent("profiles.json")),
    credentialStore: credentials
  )
  let endpoint = try S3Endpoint("http://127.0.0.1:23900")
  let first = ConnectionProfile(
    name: "First", endpoint: endpoint, region: "garage", addressingStyle: .path,
    knownBucket: "first-bucket"
  )
  let second = ConnectionProfile(
    name: "Second", endpoint: endpoint, region: "garage", addressingStyle: .path,
    knownBucket: "second-bucket"
  )
  let identity = S3Credentials(accessKeyID: "test", secretAccessKey: "test")
  try await model.save(first, credentials: identity)
  for _ in 0..<100 where model.browser.location == nil { await Task.yield() }
  let source = try #require(model.downloadSource())

  try await model.save(second, credentials: identity)
  let destination = directory.appendingPathComponent("download.txt")
  let object = ObjectSummary(key: "example.txt", size: 1, lastModified: nil, eTag: nil)
  try await model.download(object, from: source, to: destination, maximumBytes: .max)

  let request = try #require(await repository.lastDownload)
  #expect(request.profileID == first.id)
  #expect(request.bucket == "first-bucket")
  #expect(request.key == object.key)
  #expect(try String(contentsOf: destination, encoding: .utf8) == "first-bucket")
}

@MainActor
@Test func editingConnectionRestoresMissingCredentials() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("openbucket-recovery-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let credentials = MemoryCredentialStore()
  let model = AppModel(
    repository: EmptyRepository(),
    profileStore: ProfileStore(fileURL: directory.appendingPathComponent("profiles.json")),
    credentialStore: credentials
  )
  let profile = ConnectionProfile(
    name: "Garage", endpoint: try S3Endpoint("http://127.0.0.1:23900"),
    region: "garage", addressingStyle: .path
  )
  try await model.save(
    profile, credentials: S3Credentials(accessKeyID: "first", secretAccessKey: "first")
  )
  await credentials.delete(reference: profile.credentialReference)

  var edited = profile
  edited.name = "Garage restored"
  try await model.save(
    edited, credentials: S3Credentials(accessKeyID: "restored", secretAccessKey: "restored")
  )

  #expect(model.selectedProfile?.name == "Garage restored")
  #expect(try await credentials.load(reference: profile.credentialReference).accessKeyID == "restored")
}

private struct EmptyRepository: S3Repository {
  func listBuckets(profile: ConnectionProfile, credentials: S3Credentials) async throws -> [String] { [] }

  func listObjects(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    bucket: String,
    prefix: String,
    continuationToken: String?
  ) async throws -> ObjectPage {
    ObjectPage(prefixes: [], objects: [], nextToken: nil)
  }

  func downloadObject(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    bucket: String,
    key: String,
    to destination: URL,
    maximumBytes: Int64
  ) async throws -> ObjectContentInfo {
    throw S3Failure(category: .unknown, message: "This test does not download objects.")
  }
}

private actor MemoryCredentialStore: CredentialStore {
  private var values: [UUID: S3Credentials] = [:]

  func save(_ credentials: S3Credentials, reference: UUID) {
    values[reference] = credentials
  }

  func load(reference: UUID) throws -> S3Credentials {
    guard let credentials = values[reference] else { throw CredentialStoreError.notFound }
    return credentials
  }

  func delete(reference: UUID) {
    values.removeValue(forKey: reference)
  }
}

private actor RecordingDownloadRepository: S3Repository {
  struct Request: Sendable {
    let profileID: UUID
    let bucket: String
    let key: String
  }

  private(set) var lastDownload: Request?

  func listBuckets(profile: ConnectionProfile, credentials: S3Credentials) -> [String] { [] }

  func listObjects(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    bucket: String,
    prefix: String,
    continuationToken: String?
  ) -> ObjectPage {
    ObjectPage(prefixes: [], objects: [], nextToken: nil)
  }

  func downloadObject(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    bucket: String,
    key: String,
    to destination: URL,
    maximumBytes: Int64
  ) throws -> ObjectContentInfo {
    lastDownload = Request(profileID: profile.id, bucket: bucket, key: key)
    try Data(bucket.utf8).write(to: destination)
    return ObjectContentInfo(contentType: "text/plain", byteCount: Int64(bucket.utf8.count))
  }
}
