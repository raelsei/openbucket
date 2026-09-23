import Darwin
import Foundation
import OpenBucketCore
import SotoCore
import SotoS3

public struct SotoS3Repository: S3Repository {
  private let httpClient: (any AWSHTTPClient)?

  public init() {
    httpClient = nil
  }

  init(httpClient: any AWSHTTPClient) {
    self.httpClient = httpClient
  }

  public func listBuckets(profile: ConnectionProfile, credentials: S3Credentials) async throws -> [String] {
    return try await withService(profile: profile, credentials: credentials) { service in
      let output = try await service.listBuckets()
      return output.buckets?.compactMap(\.name) ?? []
    }
  }

  public func listObjects(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    bucket: String,
    prefix: String,
    continuationToken: String?
  ) async throws -> ObjectPage {
    if profile.addressingStyle == .path,
      let host = profile.endpoint.url.host?.lowercased(),
      Self.isAmazonEndpoint(host),
      !bucket.contains(".")
    {
      throw S3Failure(
        category: .regionOrEndpoint,
        message:
          "Soto uses virtual-host addressing for this Amazon endpoint. Choose Automatic or Virtual host."
      )
    }
    return try await withService(profile: profile, credentials: credentials) { service in
      let request = S3.ListObjectsV2Request(
        bucket: bucket,
        continuationToken: continuationToken,
        delimiter: "/",
        encodingType: .url,
        maxKeys: 500,
        prefix: prefix
      )
      let output = try await service.listObjectsV2(request)
      let isURLEncoded = output.encodingType == .url
      let prefixes = try (output.commonPrefixes ?? []).compactMap { item -> String? in
        guard let prefix = item.prefix else { return nil }
        return try Self.decodeKey(prefix, isURLEncoded: isURLEncoded)
      }
      let objects = try (output.contents ?? []).compactMap { object -> ObjectSummary? in
        guard let key = object.key else { return nil }
        return ObjectSummary(
          key: try Self.decodeKey(key, isURLEncoded: isURLEncoded),
          size: object.size ?? 0,
          lastModified: object.lastModified,
          eTag: object.eTag
        )
      }
      return ObjectPage(
        prefixes: prefixes,
        objects: objects,
        nextToken: output.isTruncated == true ? output.nextContinuationToken : nil
      )
    }
  }

  public func downloadObject(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    bucket: String,
    key: String,
    to destination: URL,
    maximumBytes: Int64
  ) async throws -> ObjectContentInfo {
    guard maximumBytes > 0 else {
      throw S3Failure(category: .unknown, message: "Invalid preview size limit.")
    }
    let timeout: SotoCore.TimeAmount = maximumBytes == .max ? .seconds(3600) : .seconds(120)
    return try await withService(profile: profile, credentials: credentials, timeout: timeout) {
      service in
      let output = try await service.getObject(bucket: bucket, key: key)
      if let length = output.contentLength, length > maximumBytes {
        throw S3Failure(category: .unknown, message: "This object is too large to preview.")
      }
      let staging = destination.deletingLastPathComponent()
        .appendingPathComponent(".openbucket-\(UUID().uuidString).download")
      guard
        FileManager.default.createFile(
          atPath: staging.path, contents: nil, attributes: [.posixPermissions: 0o600]
        )
      else {
        throw CocoaError(.fileWriteUnknown)
      }
      defer { try? FileManager.default.removeItem(at: staging) }
      let handle = try FileHandle(forWritingTo: staging)
      defer { try? handle.close() }
      var byteCount: Int64 = 0
      if !output.body.isEmpty {
        for try await chunk in output.body {
          try Task.checkCancellation()
          guard chunk.readableBytes <= maximumBytes - byteCount else {
            throw S3Failure(category: .unknown, message: "This object is too large to preview.")
          }
          try handle.write(contentsOf: Data(chunk.readableBytesView))
          byteCount += Int64(chunk.readableBytes)
        }
      }
      try handle.close()
      try Task.checkCancellation()
      guard Darwin.rename(staging.path, destination.path) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }
      return ObjectContentInfo(contentType: output.contentType, byteCount: byteCount)
    }
  }

  struct RequestSettings: Sendable {
    let endpoint: String
    let forceVirtualHost: Bool
  }

  func requestSettings(for profile: ConnectionProfile) -> RequestSettings {
    let endpoint = profile.endpoint.absoluteString
    return RequestSettings(
      endpoint: endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint,
      forceVirtualHost: profile.addressingStyle == .virtualHost
    )
  }

  private static func decodeKey(_ value: String, isURLEncoded: Bool) throws -> String {
    guard isURLEncoded else { return value }
    guard let decoded = value.removingPercentEncoding else {
      throw S3Failure(category: .unknown, message: "S3 returned an invalid URL-encoded object key.")
    }
    return decoded
  }

  private static func isAmazonEndpoint(_ host: String) -> Bool {
    host == "amazonaws.com" || host.hasSuffix(".amazonaws.com")
      || host == "amazonaws.com.cn" || host.hasSuffix(".amazonaws.com.cn")
  }

  private func withService<Value: Sendable>(
    profile: ConnectionProfile,
    credentials: S3Credentials,
    timeout: SotoCore.TimeAmount = .seconds(6),
    operation: @Sendable (S3) async throws -> Value
  ) async throws -> Value {
    let endpointPath =
      URLComponents(url: profile.endpoint.url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
    if profile.addressingStyle == .virtualHost && !endpointPath.isEmpty && endpointPath != "/" {
      throw S3Failure(
        category: .regionOrEndpoint,
        message: "Virtual-host addressing cannot be used with an endpoint path. Choose path style."
      )
    }
    let provider = CredentialProviderFactory.static(
      accessKeyId: credentials.accessKeyID,
      secretAccessKey: credentials.secretAccessKey,
      sessionToken: credentials.sessionToken
    )
    let client =
      if let httpClient {
        AWSClient(
          credentialProvider: provider,
          retryPolicy: .jitter(base: .milliseconds(200), maxRetries: 1),
          httpClient: httpClient
        )
      } else {
        AWSClient(
          credentialProvider: provider,
          retryPolicy: .jitter(base: .milliseconds(200), maxRetries: 1)
        )
      }
    let settings = requestSettings(for: profile)
    let options: AWSServiceConfig.Options = settings.forceVirtualHost ? [.s3ForceVirtualHost] : []
    let service = S3(
      client: client,
      region: Region(rawValue: profile.region),
      endpoint: settings.endpoint,
      timeout: timeout,
      options: options
    )
    do {
      let value = try await operation(service)
      try? await client.shutdown()
      return value
    } catch {
      try? await client.shutdown()
      throw S3ErrorMapper.map(error)
    }
  }
}
