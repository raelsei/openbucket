import OpenBucketS3
import SwiftUI

@main
struct OpenBucketApp: App {
  var body: some Scene {
    WindowGroup("OpenBucket") {
      ContentView(
        repository: SotoS3Repository(),
        profileStore: ProfileStore(fileURL: Self.profilesURL),
        credentialStore: KeychainCredentialStore()
      )
      .frame(minWidth: 840, minHeight: 520)
    }
  }

  private static var profilesURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("OpenBucket", isDirectory: true)
      .appendingPathComponent("profiles.json")
  }
}
