import Foundation
import Testing
@testable import OpenBucketCore

private actor ControlledRepository: S3Repository {
    private var heldRequest: CheckedContinuation<ObjectPage, Error>?

    func listBuckets(profile: ConnectionProfile, credentials: S3Credentials) async throws -> [String] {
        []
    }

    func listObjects(
        profile: ConnectionProfile,
        credentials: S3Credentials,
        bucket: String,
        prefix: String,
        continuationToken: String?
    ) async throws -> ObjectPage {
        if bucket == "slow" {
            return try await withCheckedThrowingContinuation { heldRequest = $0 }
        }
        if continuationToken == "second" {
            return ObjectPage(prefixes: [], objects: [.init(key: "two", size: 2, lastModified: nil, eTag: nil)], nextToken: nil)
        }
        return ObjectPage(
            prefixes: ["folder/"],
            objects: [.init(key: "one", size: 1, lastModified: nil, eTag: nil)],
            nextToken: "second"
        )
    }

    func hasHeldRequest() -> Bool { heldRequest != nil }

    func completeHeldRequest() {
        heldRequest?.resume(returning: ObjectPage(
            prefixes: [],
            objects: [.init(key: "stale", size: 0, lastModified: nil, eTag: nil)],
            nextToken: "stale-token"
        ))
        heldRequest = nil
    }
}

@Test @MainActor func profileSwitchDiscardsStaleObjects() async throws {
    let repository = ControlledRepository()
    let session = BrowseSession(repository: repository)
    let profile = try makeProfile()
    let credentials = S3Credentials(accessKeyID: "test", secretAccessKey: "test")

    session.navigate(profile: profile, credentials: credentials, to: try S3Location(bucket: "slow"))
    for _ in 0..<100 where !(await repository.hasHeldRequest()) { await Task.yield() }
    #expect(await repository.hasHeldRequest())

    session.navigate(profile: profile, credentials: credentials, to: try S3Location(bucket: "fast"))
    await repository.completeHeldRequest()
    for _ in 0..<100 where session.isLoading { await Task.yield() }

    #expect(session.location?.bucket == "fast")
    #expect(session.objects.map(\.key) == ["one"])
    #expect(session.nextToken == "second")
}

@Test @MainActor func nextPageAppendsResults() async throws {
    let repository = ControlledRepository()
    let session = BrowseSession(repository: repository)
    let profile = try makeProfile()
    let credentials = S3Credentials(accessKeyID: "test", secretAccessKey: "test")

    session.navigate(profile: profile, credentials: credentials, to: try S3Location(bucket: "fast"))
    for _ in 0..<100 where session.isLoading { await Task.yield() }
    session.loadNextPage(profile: profile, credentials: credentials)
    for _ in 0..<100 where session.isLoading { await Task.yield() }

    #expect(session.objects.map(\.key) == ["one", "two"])
    #expect(session.nextToken == nil)
}

private func makeProfile() throws -> ConnectionProfile {
    ConnectionProfile(
        name: "Local",
        endpoint: try S3Endpoint("http://127.0.0.1:23900"),
        region: "garage",
        addressingStyle: .path
    )
}
