import Foundation
import Observation

@MainActor @Observable
public final class BrowseSession {
  public private(set) var location: S3Location?
  public private(set) var prefixes: [String] = []
  public private(set) var objects: [ObjectSummary] = []
  public private(set) var nextToken: String?
  public private(set) var isLoading = false
  public private(set) var failure: S3Failure?

  @ObservationIgnored private let repository: any S3Repository
  @ObservationIgnored private var activeTask: Task<Void, Never>?
  @ObservationIgnored private var activeProfileID: UUID?
  @ObservationIgnored private var generation = 0

  public init(repository: any S3Repository) {
    self.repository = repository
  }

  public func navigate(profile: ConnectionProfile, credentials: S3Credentials, to location: S3Location) {
    cancel()
    activeProfileID = profile.id
    self.location = location
    loadPage(profile: profile, credentials: credentials, location: location, token: nil, append: false)
  }

  public func loadNextPage(profile: ConnectionProfile, credentials: S3Credentials) {
    guard activeProfileID == profile.id,
      let location,
      let token = nextToken,
      !isLoading
    else { return }
    loadPage(profile: profile, credentials: credentials, location: location, token: token, append: true)
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
    failure = nil
    isLoading = false
  }

  private func loadPage(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    location: S3Location,
    token: String?,
    append: Bool
  ) {
    isLoading = true
    failure = nil
    let requestGeneration = generation
    activeTask = Task {
      do {
        var currentToken = token
        var seenTokens = Set<String>()
        var emptyPages = 0
        while true {
          if let currentToken { seenTokens.insert(currentToken) }
          let page = try await repository.listObjects(
            profile: profile,
            credentials: credentials,
            bucket: location.bucket,
            prefix: location.prefix,
            continuationToken: currentToken
          )
          guard requestGeneration == generation, !Task.isCancelled else { return }
          if page.prefixes.isEmpty && page.objects.isEmpty,
            let continuation = page.nextToken,
            !seenTokens.contains(continuation)
          {
            emptyPages += 1
            guard emptyPages < 16 else {
              throw S3Failure(category: .unknown, message: "S3 returned too many empty pages.")
            }
            currentToken = continuation
            continue
          }
          if append {
            var seenPrefixes = Set(prefixes.map { Array($0.utf8) })
            prefixes.append(contentsOf: page.prefixes.filter { seenPrefixes.insert(Array($0.utf8)).inserted })
            var seenObjects = Set(objects.map(\.id))
            objects.append(contentsOf: page.objects.filter { seenObjects.insert($0.id).inserted })
          } else {
            prefixes = page.prefixes
            objects = page.objects
          }
          nextToken = page.nextToken.flatMap { seenTokens.contains($0) ? nil : $0 }
          isLoading = false
          return
        }
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
