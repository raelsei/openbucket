import Foundation

public struct ObjectSummary: Hashable, Identifiable, Sendable {
  public var id: [UInt8] { Array(key.utf8) }
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

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id && lhs.size == rhs.size && lhs.lastModified == rhs.lastModified
      && lhs.eTag == rhs.eTag
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(size)
    hasher.combine(lastModified)
    hasher.combine(eTag)
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

public struct ObjectContentInfo: Sendable {
  public let contentType: String?
  public let byteCount: Int64

  public init(contentType: String?, byteCount: Int64) {
    self.contentType = contentType
    self.byteCount = byteCount
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

  func downloadObject(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    bucket: String,
    key: String,
    to destination: URL,
    maximumBytes: Int64
  ) async throws -> ObjectContentInfo
}
