import Foundation

/// A bucket and literal object-key prefix in an `s3://` location.
public struct S3Location: Hashable, Sendable {
  public enum ParseError: Error, Equatable {
    case invalidScheme
    case missingBucket
  }

  public let bucket: String
  public let prefix: String

  public init(bucket: String, prefix: String = "") throws {
    guard !bucket.isEmpty, !bucket.contains("/") else { throw ParseError.missingBucket }
    self.bucket = bucket
    self.prefix = prefix
  }

  public init(_ text: String) throws {
    guard text.hasPrefix("s3://") else { throw ParseError.invalidScheme }
    let remainder = text.dropFirst(5)
    let separator = remainder.firstIndex(of: "/")
    let bucket = separator.map { String(remainder[..<$0]) } ?? String(remainder)
    let prefix = separator.map { String(remainder[remainder.index(after: $0)...]) } ?? ""
    try self.init(bucket: bucket, prefix: prefix)
  }

  public var displayString: String {
    "s3://\(bucket)/\(prefix)"
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.bucket.utf8.elementsEqual(rhs.bucket.utf8)
      && lhs.prefix.utf8.elementsEqual(rhs.prefix.utf8)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(Array(bucket.utf8))
    hasher.combine(Array(prefix.utf8))
  }
}
