import Foundation
import OpenBucketCore
import Testing

@testable import OpenBucket

@Test func batchNamesRemainUniqueAfterSanitizing() {
  var used = Set<String>()
  let first = BatchDownloadNames.uniqueName(for: "a:report.txt", usedNames: &used)
  let second = BatchDownloadNames.uniqueName(for: "a\\report.txt", usedNames: &used)

  #expect(first == "areport.txt")
  #expect(second == "areport (2).txt")
  #expect(used.count == 2)
}

@MainActor
@Test func batchDownloadKeepsFailuresSeparateAndWritesToNewFolder() async throws {
  let parent = FileManager.default.temporaryDirectory
    .appendingPathComponent("openbucket-batch-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: parent) }

  let profile = ConnectionProfile(
    name: "Test", endpoint: try S3Endpoint("http://127.0.0.1:23900"),
    region: "test", addressingStyle: .path
  )
  let credentials = S3Credentials(accessKeyID: "test", secretAccessKey: "test")
  let objects = ["one.txt", "bad.txt", "two.txt"].map {
    ObjectSummary(key: $0, size: 1, lastModified: nil, eTag: nil)
  }
  var progress: [BatchDownloadProgress] = []
  let result = try await BatchDownloader(repository: BatchTestRepository()).download(
    objects, profile: profile, credentials: credentials, bucket: "test-bucket", into: parent
  ) { progress.append($0) }

  #expect(result.downloaded == 2)
  #expect(result.failedKeys == ["bad.txt"])
  #expect(!result.cancelled)
  #expect(result.directory.deletingLastPathComponent() == parent)
  #expect(
    try String(contentsOf: result.directory.appendingPathComponent("one.txt"), encoding: .utf8) == "one.txt")
  #expect(
    try String(contentsOf: result.directory.appendingPathComponent("two.txt"), encoding: .utf8) == "two.txt")
  #expect(!FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("bad.txt").path))
  #expect(progress.last == BatchDownloadProgress(completed: 3, total: 3, failed: 1))
}

private struct BatchTestRepository: S3Repository {
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
    if key == "bad.txt" { throw CocoaError(.fileReadUnknown) }
    try Data(key.utf8).write(to: destination)
    return ObjectContentInfo(contentType: "text/plain", byteCount: Int64(key.utf8.count))
  }
}
