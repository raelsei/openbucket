import Foundation
import OpenBucketCore

actor ProfileStore {
  private let fileURL: URL

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  func load() throws -> [ConnectionProfile] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([ConnectionProfile].self, from: data)
  }

  func save(_ profiles: [ConnectionProfile]) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(profiles).write(to: fileURL, options: .atomic)
  }
}
