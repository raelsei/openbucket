import Foundation
import OpenBucketCore

struct BatchDownloadProgress: Equatable {
  let completed: Int
  let total: Int
  let failed: Int
}

struct BatchDownloadResult {
  let directory: URL
  let downloaded: Int
  let failedKeys: [String]
  let cancelled: Bool
}

@MainActor
struct BatchDownloader {
  let repository: any S3Repository

  func download(
    _ objects: [ObjectSummary],
    profile: ConnectionProfile,
    credentials: S3Credentials,
    bucket: String,
    into parentDirectory: URL,
    progress: (BatchDownloadProgress) -> Void
  ) async throws -> BatchDownloadResult {
    let directory = parentDirectory.appendingPathComponent(
      "OpenBucket Export-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )

    var usedNames = Set<String>()
    var downloaded = 0
    var failedKeys: [String] = []
    for object in objects {
      if Task.isCancelled { break }
      let name = BatchDownloadNames.uniqueName(for: object.key, usedNames: &usedNames)
      let destination = directory.appendingPathComponent(name)
      do {
        _ = try await repository.downloadObject(
          profile: profile, credentials: credentials, bucket: bucket, key: object.key,
          to: destination, maximumBytes: .max
        )
        downloaded += 1
      } catch {
        if Task.isCancelled { break }
        failedKeys.append(object.key)
      }
      progress(
        BatchDownloadProgress(
          completed: downloaded + failedKeys.count, total: objects.count, failed: failedKeys.count)
      )
    }
    return BatchDownloadResult(
      directory: directory, downloaded: downloaded, failedKeys: failedKeys,
      cancelled: Task.isCancelled)
  }
}

enum BatchDownloadNames {
  static func uniqueName(for key: String, usedNames: inout Set<String>) -> String {
    let original = PreviewFileName.from(objectKey: key)
    if usedNames.insert(original).inserted { return original }

    let fileURL = URL(fileURLWithPath: original)
    let fileExtension = fileURL.pathExtension
    let stem = fileExtension.isEmpty ? original : String(original.dropLast(fileExtension.utf8.count + 1))
    let extensionSuffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
    var number = 2
    while true {
      let numberSuffix = " (\(number))"
      let limit = 120 - extensionSuffix.utf8.count - numberSuffix.utf8.count
      var shortened = ""
      for character in stem {
        guard shortened.utf8.count + String(character).utf8.count <= limit else { break }
        shortened.append(character)
      }
      let candidate = shortened + numberSuffix + extensionSuffix
      if usedNames.insert(candidate).inserted { return candidate }
      number += 1
    }
  }
}
