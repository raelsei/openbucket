import Foundation

public enum AddressingStyle: String, Codable, CaseIterable, Sendable {
  case automatic
  case path
  case virtualHost
}

/// Non-secret connection settings. `credentialReference` resolves in the platform credential store.
public struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
  public let id: UUID
  public var name: String
  public var endpoint: S3Endpoint
  public var region: String
  public var addressingStyle: AddressingStyle
  public var knownBucket: String?
  public var startingPrefix: String
  public let credentialReference: UUID

  public init(
    id: UUID = UUID(),
    name: String,
    endpoint: S3Endpoint,
    region: String,
    addressingStyle: AddressingStyle,
    knownBucket: String? = nil,
    startingPrefix: String = "",
    credentialReference: UUID = UUID()
  ) {
    self.id = id
    self.name = name
    self.endpoint = endpoint
    self.region = region
    self.addressingStyle = addressingStyle
    self.knownBucket = knownBucket
    self.startingPrefix = startingPrefix
    self.credentialReference = credentialReference
  }
}

/// Ephemeral S3 identity. This type intentionally does not conform to Codable.
public struct S3Credentials: Sendable {
  public let accessKeyID: String
  public let secretAccessKey: String
  public let sessionToken: String?

  public init(accessKeyID: String, secretAccessKey: String, sessionToken: String? = nil) {
    self.accessKeyID = accessKeyID
    self.secretAccessKey = secretAccessKey
    self.sessionToken = sessionToken
  }
}
