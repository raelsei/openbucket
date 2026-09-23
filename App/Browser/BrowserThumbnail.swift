import AppKit
import ImageIO
import OpenBucketCore
import QuickLookThumbnailing
import SwiftUI

struct BrowserThumbnail: View {
  let object: ObjectSummary
  let model: AppModel
  let isVideo: Bool
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity)
          .overlay(alignment: .bottomTrailing) {
            if isVideo {
              Image(systemName: "play.fill")
                .padding(8)
                .background(.regularMaterial, in: Circle())
                .padding(8)
            }
          }
      } else {
        Image(systemName: isVideo ? "play.rectangle" : "photo")
          .font(.system(size: 42, weight: .light))
          .foregroundStyle(.secondary)
      }
    }
    .task(id: object.id) {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("OpenBucketThumbnail-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      do {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
        let file = directory.appendingPathComponent(
          "media.\((object.key as NSString).pathExtension.lowercased())"
        )
        try await model.download(object, to: file, maximumBytes: 8 * 1024 * 1024)
        try Task.checkCancellation()
        if isVideo {
          let request = QLThumbnailGenerator.Request(
            fileAt: file,
            size: CGSize(width: 520, height: 520),
            scale: 1,
            representationTypes: .thumbnail
          )
          image = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
          return
        }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 520,
              kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary
          )
        else { return }
        image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
      } catch {
      }
    }
  }
}
