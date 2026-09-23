import Foundation
import OpenBucketCore
import SotoCore

enum S3ErrorMapper {
  static func map(_ error: Error) -> S3Failure {
    if let existing = error as? S3Failure { return existing }
    if let urlError = error as? URLError {
      let category: S3Failure.Category =
        urlError.code == .secureConnectionFailed
          || urlError.code == .serverCertificateUntrusted ? .tls : .network
      return S3Failure(
        category: category,
        message: category == .tls
          ? "TLS verification failed. Check the endpoint certificate."
          : "The S3 endpoint could not be reached.",
        technicalDetail: "URL error: \(urlError.code.rawValue)"
      )
    }

    if let serviceError = error as? any AWSErrorType {
      return serviceFailure(for: serviceError)
    }
    let name = String(describing: type(of: error))
    if ["NWPOSIXError", "HTTPClientError", "ChannelError"].contains(name) {
      return S3Failure(
        category: .network,
        message: "The S3 endpoint could not be reached.",
        technicalDetail: "SDK error: \(name)"
      )
    }
    return S3Failure(
      category: .unknown,
      message: "The S3 request failed. Check the connection settings and service response.",
      technicalDetail: "SDK error: \(name)"
    )
  }

  private static func serviceFailure(for error: any AWSErrorType) -> S3Failure {
    let code = error.errorCode
    let safeCode =
      code.count <= 64
        && code.unicodeScalars.allSatisfy {
          CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-.")).contains($0)
        } ? code : "Unrecognized"
    let detail = "S3 code: \(safeCode)"
    switch code {
    case "AccessDenied", "AllAccessDisabled":
      return S3Failure(
        category: .authorization, message: "Access to this S3 operation was denied.", technicalDetail: detail)
    case "InvalidAccessKeyId", "ExpiredToken", "InvalidToken":
      return S3Failure(
        category: .authentication, message: "S3 rejected these credentials.", technicalDetail: detail)
    case "SignatureDoesNotMatch", "InvalidSignatureException":
      return S3Failure(
        category: .authentication,
        message: "The S3 request signature was rejected. Check the secret, region, and endpoint path.",
        technicalDetail: detail)
    case "AuthorizationHeaderMalformed", "PermanentRedirect", "IncorrectEndpoint", "NoSuchBucket":
      return S3Failure(
        category: .regionOrEndpoint, message: "Check the bucket, region, and endpoint address.",
        technicalDetail: detail)
    case "NotImplemented", "UnsupportedOperation":
      return S3Failure(
        category: .unsupportedOperation, message: "This S3 service does not support the requested operation.",
        technicalDetail: detail)
    default:
      return S3Failure(
        category: .unknown,
        message: "The S3 request failed. Check the connection settings and service response.",
        technicalDetail: detail)
    }
  }
}
