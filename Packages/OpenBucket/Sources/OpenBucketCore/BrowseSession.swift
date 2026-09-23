import Foundation
import Observation

@MainActor @Observable
public final class BrowseSession {
  public private(set) var location: S3Location?
  public private(set) var prefixes: [String] = []
  public private(set) var objects: [ObjectSummary] = []
  public private(set) var nextToken: String?
  public private(set) var pageNumber = 1
  public private(set) var isLoading = false
  public private(set) var failure: S3Failure?

  @ObservationIgnored private let repository: any S3Repository
  @ObservationIgnored private var activeTask: Task<Void, Never>?
  @ObservationIgnored private var activeProfileID: UUID?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var pageTokens: [String?] = [nil]

  public init(repository: any S3Repository) {
    self.repository = repository
  }

  public func navigate(profile: ConnectionProfile, credentials: S3Credentials, to location: S3Location) {
    cancel()
    activeProfileID = profile.id
    self.location = location
    loadPage(profile: profile, credentials: credentials, location: location, token: nil, index: 0)
  }

  public func loadNextPage(profile: ConnectionProfile, credentials: S3Credentials) {
    guard activeProfileID == profile.id,
      let location,
      let token = nextToken,
      !isLoading
    else { return }
    loadPage(profile: profile, credentials: credentials, location: location, token: token, index: pageNumber)
  }

  public func loadPreviousPage(profile: ConnectionProfile, credentials: S3Credentials) {
    guard activeProfileID == profile.id,
      let location,
      pageNumber > 1,
      !isLoading
    else { return }
    let index = pageNumber - 2
    loadPage(
      profile: profile, credentials: credentials, location: location, token: pageTokens[index], index: index)
  }

  public func cancel() {
    generation &+= 1
    activeTask?.cancel()
    activeTask = nil
    activeProfileID = nil
    location = nil
    prefixes = []
    objects = []
    nextToken = nil
    pageNumber = 1
    pageTokens = [nil]
    failure = nil
    isLoading = false
  }

  private func loadPage(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    location: S3Location,
    token: String?,
    index: Int
  ) {
    isLoading = true
    failure = nil
    let requestGeneration = generation
    activeTask = Task {
      do {
        let page = try await repository.listObjects(
          profile: profile,
          credentials: credentials,
          bucket: location.bucket,
          prefix: location.prefix,
          continuationToken: token
        )
        guard requestGeneration == generation, !Task.isCancelled else { return }
        prefixes = page.prefixes
        objects = page.objects
        nextToken = page.nextToken
        pageNumber = index + 1
        pageTokens = Array(pageTokens.prefix(index)) + [token]
        isLoading = false
      } catch {
        guard requestGeneration == generation, !Task.isCancelled else { return }
        failure = Self.failure(for: error)
        isLoading = false
      }
    }
  }

  private static func failure(for error: Error) -> S3Failure {
    if let failure = error as? S3Failure { return failure }
    return S3Failure(category: .unknown, message: "S3 request failed.")
  }
}
