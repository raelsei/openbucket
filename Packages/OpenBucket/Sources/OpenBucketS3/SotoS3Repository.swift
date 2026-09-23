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
    try await withService(profile: profile, credentials: credentials) { service in
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
    try await withService(profile: profile, credentials: credentials) { service in
      let request = S3.ListObjectsV2Request(
        bucket: bucket,
        continuationToken: continuationToken,
        delimiter: "/",
        maxKeys: 500,
        prefix: prefix
      )
      let output = try await service.listObjectsV2(request)
      let prefixes = output.commonPrefixes?.compactMap(\.prefix) ?? []
      let objects =
        output.contents?.compactMap { object -> ObjectSummary? in
          guard let key = object.key else { return nil }
          return ObjectSummary(
            key: key,
            size: object.size ?? 0,
            lastModified: object.lastModified,
            eTag: object.eTag
          )
        } ?? []
      return ObjectPage(
        prefixes: prefixes,
        objects: objects,
        nextToken: output.isTruncated == true ? output.nextContinuationToken : nil
      )
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

  private func withService<Value: Sendable>(
    profile: ConnectionProfile,
    credentials: S3Credentials,
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
      timeout: .seconds(6),
      options: options
    )
    do {
      let value = try await operation(service)
      try await client.shutdown()
      return value
    } catch {
      try? await client.shutdown()
      throw S3ErrorMapper.map(error)
    }
  }
}
