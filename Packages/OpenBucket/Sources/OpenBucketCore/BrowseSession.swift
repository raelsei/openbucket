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
        prefixes = []
        objects = []
        nextToken = nil
        failure = nil
        isLoading = true
        let requestGeneration = generation
        activeTask = Task {
            do {
                let page = try await repository.listObjects(
                    profile: profile,
                    credentials: credentials,
                    bucket: location.bucket,
                    prefix: location.prefix,
                    continuationToken: nil
                )
                guard requestGeneration == generation, !Task.isCancelled else { return }
                prefixes = page.prefixes
                objects = page.objects
                nextToken = page.nextToken
                isLoading = false
            } catch {
                guard requestGeneration == generation, !Task.isCancelled else { return }
                failure = Self.failure(for: error)
                isLoading = false
            }
        }
    }

    public func loadNextPage(profile: ConnectionProfile, credentials: S3Credentials) {
        guard activeProfileID == profile.id,
            let location,
            let token = nextToken,
            !isLoading
        else { return }
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
                prefixes.append(contentsOf: page.prefixes)
                objects.append(contentsOf: page.objects)
                nextToken = page.nextToken
                isLoading = false
            } catch {
                guard requestGeneration == generation, !Task.isCancelled else { return }
                failure = Self.failure(for: error)
                isLoading = false
            }
        }
    }

    public func cancel() {
        generation &+= 1
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
    }

    private static func failure(for error: Error) -> S3Failure {
        if let failure = error as? S3Failure { return failure }
        return S3Failure(category: .unknown, message: "S3 request failed.")
    }
}
