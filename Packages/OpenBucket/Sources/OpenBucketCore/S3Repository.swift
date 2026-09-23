import Foundation

public struct ObjectSummary: Hashable, Identifiable, Sendable {
  public var id: String { key }
  public let key: String
  public let size: Int64
  public let lastModified: Date?
  public let eTag: String?

  public init(key: String, size: Int64, lastModified: Date?, eTag: String?) {
    self.key = key
    self.size = size
    self.lastModified = lastModified
    self.eTag = eTag
  }
}

public struct ObjectPage: Sendable {
  public let prefixes: [String]
  public let objects: [ObjectSummary]
  public let nextToken: String?

  public init(prefixes: [String], objects: [ObjectSummary], nextToken: String?) {
    self.prefixes = prefixes
    self.objects = objects
    self.nextToken = nextToken
  }
}

/// The read-only S3 operations needed by the browser.
public protocol S3Repository: Sendable {
  func listBuckets(profile: ConnectionProfile, credentials: S3Credentials) async throws -> [String]

  func listObjects(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    bucket: String,
    prefix: String,
    continuationToken: String?
  ) async throws -> ObjectPage
}
