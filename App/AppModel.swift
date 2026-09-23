import Foundation
import Observation
import OpenBucketCore

@MainActor @Observable
final class AppModel {
  struct DownloadSource: Sendable {
    let profile: ConnectionProfile
    let bucket: String
  }

  private(set) var profiles: [ConnectionProfile] = []
  private(set) var selectedProfileID: UUID?
  private(set) var buckets: [String] = []
  private(set) var isConnecting = false
  private(set) var connectionFailure: S3Failure?
  let browser: BrowseSession

  @ObservationIgnored private let repository: any S3Repository
  @ObservationIgnored private let profileStore: ProfileStore
  @ObservationIgnored private let credentialStore: any CredentialStore
  @ObservationIgnored private var connectionTask: Task<Void, Never>?
  @ObservationIgnored private var generation = 0

  init(
    repository: any S3Repository,
    profileStore: ProfileStore,
    credentialStore: any CredentialStore
  ) {
    self.repository = repository
    self.profileStore = profileStore
    self.credentialStore = credentialStore
    browser = BrowseSession(repository: repository)
  }

  var selectedProfile: ConnectionProfile? {
    profiles.first { $0.id == selectedProfileID }
  }

  func loadProfiles() async {
    do {
      profiles = try await profileStore.load()
      if selectedProfileID == nil {
        selectProfile(profiles.first?.id)
      }
    } catch {
      connectionFailure = S3Failure(category: .unknown, message: "Saved connections could not be opened.")
    }
  }

  func save(_ profile: ConnectionProfile, credentials: S3Credentials) async throws {
    let previous = profiles.first { $0.id == profile.id }
    let previousCredentials =
      previous?.credentialReference == profile.credentialReference
      ? try? await credentialStore.load(reference: profile.credentialReference) : nil
    try await credentialStore.save(credentials, reference: profile.credentialReference)
    var updated = profiles.filter { $0.id != profile.id }
    updated.append(profile)
    updated.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    do {
      try await profileStore.save(updated)
    } catch {
      if let previousCredentials {
        try? await credentialStore.save(previousCredentials, reference: profile.credentialReference)
      } else {
        try? await credentialStore.delete(reference: profile.credentialReference)
      }
      throw error
    }
    profiles = updated
    if let previous, previous.credentialReference != profile.credentialReference {
      try? await credentialStore.delete(reference: previous.credentialReference)
    }
    selectProfile(profile.id)
  }

  func deleteSelectedProfile() async throws {
    guard let profile = selectedProfile else { return }
    let updated = profiles.filter { $0.id != profile.id }
    try await profileStore.save(updated)
    try? await credentialStore.delete(reference: profile.credentialReference)
    profiles = updated
    selectProfile(updated.first?.id)
  }

  func credentials(for profile: ConnectionProfile) async throws -> S3Credentials {
    try await credentialStore.load(reference: profile.credentialReference)
  }

  func selectProfile(_ id: UUID?) {
    generation &+= 1
    connectionTask?.cancel()
    browser.cancel()
    selectedProfileID = id
    buckets = []
    connectionFailure = nil
    isConnecting = false
    guard let profile = selectedProfile else { return }
    let requestGeneration = generation
    isConnecting = true
    connectionTask = Task {
      do {
        let credentials = try await credentialStore.load(reference: profile.credentialReference)
        guard requestGeneration == generation, !Task.isCancelled else { return }
        if let bucket = profile.knownBucket, !bucket.isEmpty {
          let location = try S3Location(bucket: bucket, prefix: profile.startingPrefix)
          browser.navigate(profile: profile, credentials: credentials, to: location)
        } else {
          let found = try await repository.listBuckets(profile: profile, credentials: credentials)
          guard requestGeneration == generation, !Task.isCancelled else { return }
          buckets = found.sorted()
        }
        isConnecting = false
      } catch {
        guard requestGeneration == generation, !Task.isCancelled else { return }
        connectionFailure = Self.failure(for: error)
        isConnecting = false
      }
    }
  }

  func open(_ location: S3Location) {
    guard let profile = selectedProfile else { return }
    generation &+= 1
    connectionTask?.cancel()
    browser.cancel()
    connectionFailure = nil
    let requestGeneration = generation
    isConnecting = true
    connectionTask = Task {
      do {
        let credentials = try await credentialStore.load(reference: profile.credentialReference)
        guard requestGeneration == generation, !Task.isCancelled else { return }
        browser.navigate(profile: profile, credentials: credentials, to: location)
        isConnecting = false
      } catch {
        guard requestGeneration == generation, !Task.isCancelled else { return }
        connectionFailure = Self.failure(for: error)
        isConnecting = false
      }
    }
  }

  func refresh() {
    if let location = browser.location { open(location) } else { selectProfile(selectedProfileID) }
  }

  func loadNextPage() {
    guard let profile = selectedProfile else { return }
    let requestGeneration = generation
    Task {
      do {
        let credentials = try await credentialStore.load(reference: profile.credentialReference)
        guard requestGeneration == generation, !Task.isCancelled else { return }
        connectionFailure = nil
        browser.loadNextPage(profile: profile, credentials: credentials)
      } catch {
        guard requestGeneration == generation else { return }
        connectionFailure = Self.failure(for: error)
      }
    }
  }

  func download(_ object: ObjectSummary, to destination: URL, maximumBytes: Int64) async throws {
    guard let source = downloadSource() else {
      throw S3Failure(category: .unknown, message: "Choose a bucket first.")
    }
    try await download(object, from: source, to: destination, maximumBytes: maximumBytes)
  }

  func downloadSource() -> DownloadSource? {
    guard let profile = selectedProfile, let location = browser.location else { return nil }
    return DownloadSource(profile: profile, bucket: location.bucket)
  }

  func download(
    _ object: ObjectSummary,
    from source: DownloadSource,
    to destination: URL,
    maximumBytes: Int64
  ) async throws {
    let credentials = try await credentialStore.load(reference: source.profile.credentialReference)
    try Task.checkCancellation()
    _ = try await repository.downloadObject(
      profile: source.profile,
      credentials: credentials,
      bucket: source.bucket,
      key: object.key,
      to: destination,
      maximumBytes: maximumBytes
    )
  }

  func test(profile: ConnectionProfile, credentials: S3Credentials) async throws -> String {
    if let bucket = profile.knownBucket, !bucket.isEmpty {
      _ = try await repository.listObjects(
        profile: profile,
        credentials: credentials,
        bucket: bucket,
        prefix: profile.startingPrefix,
        continuationToken: nil
      )
      return "Connected to \(bucket)."
    }
    let buckets = try await repository.listBuckets(profile: profile, credentials: credentials)
    return "Connected. Found \(buckets.count) buckets."
  }

  static func failure(for error: Error) -> S3Failure {
    if let failure = error as? S3Failure { return failure }
    if let error = error as? CredentialStoreError {
      switch error {
      case .notFound:
        return S3Failure(
          category: .missingCredentials,
          message: "Credentials are missing. Edit this connection to add them again.")
      case .invalidData, .keychain:
        return S3Failure(
          category: .missingCredentials, message: "Credentials could not be read from Keychain.")
      }
    }
    return S3Failure(category: .unknown, message: "The request could not be completed.")
  }
}
