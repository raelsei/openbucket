import Foundation

public struct S3Failure: Error, Equatable, Sendable {
    public enum Category: String, Sendable {
        case network
        case tls
        case authentication
        case regionOrEndpoint
        case authorization
        case unsupportedOperation
        case missingCredentials
        case unknown
    }

    public let category: Category
    public let message: String
    public let technicalDetail: String?

    public init(category: Category, message: String, technicalDetail: String? = nil) {
        self.category = category
        self.message = message
        self.technicalDetail = technicalDetail
    }
}
