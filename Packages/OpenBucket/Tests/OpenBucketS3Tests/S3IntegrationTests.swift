import Foundation
import OpenBucketCore
import Testing

@testable import OpenBucketS3

@Test(.enabled(if: ProcessInfo.processInfo.environment["OPENBUCKET_TEST_ENDPOINT"] != nil))
func listsKnownBucketAndNestedPrefix() async throws {
  let environment = ProcessInfo.processInfo.environment
  let endpoint = try #require(environment["OPENBUCKET_TEST_ENDPOINT"])
  let region = try #require(environment["OPENBUCKET_TEST_REGION"])
  let bucket = try #require(environment["OPENBUCKET_TEST_BUCKET"])
  let accessKey = try #require(environment["OPENBUCKET_TEST_ACCESS_KEY"])
  let secretKey = try #require(environment["OPENBUCKET_TEST_SECRET_KEY"])
  let prefix = try #require(environment["OPENBUCKET_TEST_PREFIX"])
  let expectedKey = try #require(environment["OPENBUCKET_TEST_EXPECT_KEY"])
  let profile = ConnectionProfile(
    name: "Integration S3",
    endpoint: try S3Endpoint(endpoint),
    region: region,
    addressingStyle: .path,
    knownBucket: bucket
  )
  let credentials = S3Credentials(accessKeyID: accessKey, secretAccessKey: secretKey)
  let repository = SotoS3Repository()

  let root = try await repository.listObjects(
    profile: profile,
    credentials: credentials,
    bucket: bucket,
    prefix: "",
    continuationToken: nil
  )
  let firstPrefix = String(prefix.split(separator: "/").first ?? "") + "/"
  #expect(root.prefixes.contains(firstPrefix))

  let nested = try await repository.listObjects(
    profile: profile,
    credentials: credentials,
    bucket: bucket,
    prefix: prefix,
    continuationToken: nil
  )
  #expect(nested.objects.contains { $0.key == expectedKey })

  let file = FileManager.default.temporaryDirectory.appendingPathComponent(
    "openbucket-test-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: file) }
  let info = try await repository.downloadObject(
    profile: profile,
    credentials: credentials,
    bucket: bucket,
    key: expectedKey,
    to: file,
    maximumBytes: 8 * 1024 * 1024
  )
  let data = try Data(contentsOf: file)
  #expect(info.byteCount == data.count)
  #expect(!data.isEmpty)
}
