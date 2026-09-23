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
