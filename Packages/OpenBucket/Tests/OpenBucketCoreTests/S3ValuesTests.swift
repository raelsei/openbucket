import Testing

@testable import OpenBucketCore

@Test func parsesLocationWithoutChangingKeyPrefix() throws {
  let location = try S3Location("s3://photos//2026/trip/")

  #expect(location.bucket == "photos")
  #expect(location.prefix == "/2026/trip/")
}

@Test func retainsEndpointPath() throws {
  let endpoint = try S3Endpoint("https://storage.example.com/s3/")

  #expect(endpoint.absoluteString == "https://storage.example.com/s3/")
}

@Test func rejectsEndpointQuery() {
  #expect(throws: S3Endpoint.ValidationError.self) {
    try S3Endpoint("https://storage.example.com/s3/?token=secret")
  }
}

@Test func rejectsEndpointPathThatTheSDKWouldRewrite() {
  #expect(throws: S3Endpoint.ValidationError.self) {
    try S3Endpoint("https://storage.example.com/s3%2Fgateway")
  }
}

@Test func objectIdentityKeepsDistinctUTF8Keys() {
  let composed = ObjectSummary(key: "\u{00E9}.txt", size: 1, lastModified: nil, eTag: nil)
  let decomposed = ObjectSummary(key: "e\u{0301}.txt", size: 1, lastModified: nil, eTag: nil)
  #expect(composed.id != decomposed.id)
  #expect(composed != decomposed)
  #expect(Set([composed, decomposed]).count == 2)
}

@Test func locationEqualityKeepsDistinctUTF8Prefixes() throws {
  let composed = try S3Location(bucket: "photos", prefix: "\u{00E9}/")
  let decomposed = try S3Location(bucket: "photos", prefix: "e\u{0301}/")
  #expect(composed != decomposed)
}
