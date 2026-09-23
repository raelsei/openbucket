import AsyncHTTPClient
import Foundation
import OpenBucketCore
import SotoCore
import Testing

@testable import OpenBucketS3

private actor RecordingHTTPClient: AWSHTTPClient {
  private var recordedURLs: [URL] = []
  private let responseBody: String

  init(
    responseBody: String = """
    <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <Name>photos</Name><Prefix>trip/</Prefix><KeyCount>0</KeyCount>
      <MaxKeys>500</MaxKeys><IsTruncated>false</IsTruncated>
    </ListBucketResult>
    """
  ) {
    self.responseBody = responseBody
  }

  func execute(request: AWSHTTPRequest, timeout: TimeAmount, logger: Logger) async throws -> AWSHTTPResponse {
    recordedURLs.append(request.url)
    return AWSHTTPResponse(
      status: .ok,
      headers: HTTPHeaders(),
      body: AWSHTTPBody(string: responseBody)
    )
  }

  func paths() -> [String] {
    recordedURLs.map { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "" }
  }

  func hosts() -> [String] { recordedURLs.compactMap(\.host) }

  func queries() -> [String] {
    recordedURLs.compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery }
  }
}

@Test func virtualHostStyleMovesBucketIntoHostname() async throws {
  let transport = RecordingHTTPClient()
  let repository = SotoS3Repository(httpClient: transport)
  let profile = ConnectionProfile(
    name: "Gateway",
    endpoint: try S3Endpoint("http://storage.example.com"),
    region: "garage",
    addressingStyle: .virtualHost
  )

  _ = try await repository.listObjects(
    profile: profile,
    credentials: S3Credentials(accessKeyID: "test", secretAccessKey: "test"),
    bucket: "photos",
    prefix: "",
    continuationToken: nil
  )

  let hosts = await transport.hosts()
  let paths = await transport.paths()
  #expect(hosts == ["photos.storage.example.com"])
  #expect(paths == ["/"])
}

@Test func virtualHostWithEndpointPathFailsBeforeSending() async throws {
  let transport = RecordingHTTPClient()
  let repository = SotoS3Repository(httpClient: transport)
  let profile = ConnectionProfile(
    name: "Gateway",
    endpoint: try S3Endpoint("http://storage.example.com/s3/"),
    region: "garage",
    addressingStyle: .virtualHost
  )

  do {
    _ = try await repository.listObjects(
      profile: profile,
      credentials: S3Credentials(accessKeyID: "test", secretAccessKey: "test"),
      bucket: "photos",
      prefix: "",
      continuationToken: nil
    )
    Issue.record("Unsupported addressing sent a request")
  } catch let failure as S3Failure {
    #expect(failure.category == .regionOrEndpoint)
  }
  #expect(await transport.paths().isEmpty)
}

@Test func constructsPathStyleRepositoryForGarage() async throws {
  let repository = SotoS3Repository()
  let profile = ConnectionProfile(
    name: "Garage",
    endpoint: try S3Endpoint("http://127.0.0.1:23900"),
    region: "garage",
    addressingStyle: .path,
    knownBucket: "openbucket-probe"
  )

  let settings = repository.requestSettings(for: profile)

  #expect(settings.endpoint == "http://127.0.0.1:23900")
  #expect(settings.forceVirtualHost == false)
}

@Test func signedRequestKeepsEndpointPathWithoutDoubleSlash() async throws {
  let transport = RecordingHTTPClient()
  let repository = SotoS3Repository(httpClient: transport)
  let profile = ConnectionProfile(
    name: "Gateway",
    endpoint: try S3Endpoint("http://storage.example.com/s3/"),
    region: "garage",
    addressingStyle: .path
  )

  _ = try await repository.listObjects(
    profile: profile,
    credentials: S3Credentials(accessKeyID: "test", secretAccessKey: "test"),
    bucket: "photos",
    prefix: "trip/",
    continuationToken: nil
  )

  let paths = await transport.paths()
  #expect(paths == ["/s3/photos"])
}

@Test func classifiesS3ErrorCodesWithoutEchoingServiceMessages() {
  let denied = S3ErrorMapper.map(AWSResponseError(errorCode: "AccessDenied"))
  let invalidKey = S3ErrorMapper.map(AWSResponseError(errorCode: "InvalidAccessKeyId"))
  let wrongRegion = S3ErrorMapper.map(AWSResponseError(errorCode: "AuthorizationHeaderMalformed"))

  #expect(denied.category == .authorization)
  #expect(invalidKey.category == .authentication)
  #expect(wrongRegion.category == .regionOrEndpoint)
  #expect(denied.technicalDetail == "S3 code: AccessDenied")
}

@Test func classifiesMacOSTLSFailureWithoutLeakingDescription() {
  let failure = S3ErrorMapper.map(HTTPClient.NWTLSError(-9807, reason: "secret endpoint details"))
  #expect(failure.category == .tls)
  #expect(failure.technicalDetail == "SDK error: NWTLSError")
}

@Test func refusesExplicitPathStyleWhenSotoWouldMoveBucketIntoAmazonHost() async throws {
  let transport = RecordingHTTPClient()
  let repository = SotoS3Repository(httpClient: transport)
  let profile = ConnectionProfile(
    name: "AWS",
    endpoint: try S3Endpoint("https://s3.us-east-1.amazonaws.com"),
    region: "us-east-1",
    addressingStyle: .path
  )
  do {
    _ = try await repository.listObjects(
      profile: profile,
      credentials: S3Credentials(accessKeyID: "test", secretAccessKey: "test"),
      bucket: "photos",
      prefix: "",
      continuationToken: nil
    )
    Issue.record("Explicit path style was silently changed")
  } catch let failure as S3Failure {
    #expect(failure.category == .regionOrEndpoint)
  }
  #expect(await transport.paths().isEmpty)
}

@Test func decodesURLEncodedListingKeysExactlyOnce() async throws {
  let transport = RecordingHTTPClient(
    responseBody: """
      <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
        <Name>photos</Name><EncodingType>url</EncodingType>
        <CommonPrefixes><Prefix>a%252Fb/</Prefix></CommonPrefixes>
        <Contents><Key>a%252Fb/file%281%29%01</Key><Size>1</Size></Contents>
        <IsTruncated>false</IsTruncated>
      </ListBucketResult>
      """)
  let repository = SotoS3Repository(httpClient: transport)
  let profile = ConnectionProfile(
    name: "Gateway",
    endpoint: try S3Endpoint("https://storage.example.com"),
    region: "garage",
    addressingStyle: .path
  )
  let page = try await repository.listObjects(
    profile: profile,
    credentials: S3Credentials(accessKeyID: "test", secretAccessKey: "test"),
    bucket: "photos",
    prefix: "",
    continuationToken: nil
  )
  #expect(page.prefixes == ["a%2Fb/"])
  #expect(page.objects.map(\.key) == ["a%2Fb/file(1)\u{01}"])
  #expect(await transport.queries().first?.contains("encoding-type=url") == true)
}

@Test func classifiesUnreachableEndpointAsNetwork() async throws {
  let repository = SotoS3Repository()
  let profile = ConnectionProfile(
    name: "Unavailable",
    endpoint: try S3Endpoint("http://127.0.0.1:1"),
    region: "garage",
    addressingStyle: .path
  )

  do {
    _ = try await repository.listObjects(
      profile: profile,
      credentials: S3Credentials(accessKeyID: "test", secretAccessKey: "test"),
      bucket: "photos",
      prefix: "",
      continuationToken: nil
    )
    Issue.record("An unavailable endpoint returned objects")
  } catch let failure as S3Failure {
    #expect(failure.category == .network)
    #expect(failure.technicalDetail == "SDK error: NWPOSIXError")
  }
}
