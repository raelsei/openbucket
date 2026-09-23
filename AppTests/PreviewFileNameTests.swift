import Testing

@testable import OpenBucket

@Test func longPreviewNameKeepsFileExtension() {
  let name = PreviewFileName.from(objectKey: "photos/\(String(repeating: "a", count: 130)).png")

  #expect(name.hasSuffix(".png"))
  #expect(name.utf8.count <= 120)
}

@Test func previewNameIsSafeForLocalTemporaryFile() {
  let name = PreviewFileName.from(objectKey: "photos/\(String(repeating: "🌊", count: 80)):\\bad\n.mp4")

  #expect(name.hasSuffix(".mp4"))
  #expect(name.utf8.count <= 120)
  #expect(!name.contains(":"))
  #expect(!name.contains("\\"))
  #expect(!name.contains("\n"))
}
