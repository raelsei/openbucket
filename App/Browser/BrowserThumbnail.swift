import AppKit
import ImageIO
import OpenBucketCore
import QuickLookThumbnailing
import SwiftUI

@MainActor
final class ThumbnailCache {
  private let images = NSCache<NSString, NSImage>()

  init() {
    images.countLimit = 96
    images.totalCostLimit = 96 * 1024 * 1024
  }

  func image(for key: String) -> NSImage? {
    images.object(forKey: key as NSString)
  }

  func insert(_ image: NSImage, for key: String) {
    let cost = Int(image.size.width * image.size.height * 4)
    images.setObject(image, forKey: key as NSString, cost: cost)
  }
}

struct BrowserArtwork: View {
  let row: BrowserRow
  let model: AppModel
  let cache: ThumbnailCache
  var contentMode: ContentMode = .fill
  var symbolSize: CGFloat = 42
  var cornerRadius: CGFloat = 10
  var showsVideoBadge = true

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.secondary.opacity(0.08))
      if row.isImage || row.isVideo, let object = row.object {
        BrowserThumbnail(
          object: object, model: model, isVideo: row.isVideo, cache: cache,
          contentMode: contentMode, symbolSize: symbolSize, showsVideoBadge: showsVideoBadge
        )
      } else {
        Image(systemName: row.symbol)
          .font(.system(size: symbolSize, weight: .light))
          .foregroundStyle(row.prefix == nil ? Color.secondary : Color.accentColor)
      }
    }
    .clipShape(.rect(cornerRadius: cornerRadius))
  }
}

struct BrowserThumbnail: View {
  let object: ObjectSummary
  let model: AppModel
  let isVideo: Bool
  let cache: ThumbnailCache
  var contentMode: ContentMode = .fill
  var symbolSize: CGFloat = 42
  var showsVideoBadge = true

  @State private var image: NSImage?
  @State private var loadedKey: String?

  var body: some View {
    Group {
      if let image = displayedImage {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .transition(.opacity)
          .overlay(alignment: .bottomTrailing) {
            if isVideo && showsVideoBadge {
              Image(systemName: "play.fill")
                .padding(8)
                .background(.regularMaterial, in: Circle())
                .padding(8)
            }
          }
      } else {
        Image(systemName: isVideo ? "play.rectangle" : "photo")
          .font(.system(size: symbolSize, weight: .light))
          .foregroundStyle(.secondary)
      }
    }
    .animation(.easeOut(duration: 0.18), value: loadedKey)
    .task(id: cacheKey) {
      guard let cacheKey, let source = model.downloadSource() else { return }
      if let cached = cache.image(for: cacheKey) {
        image = cached
        loadedKey = cacheKey
        return
      }
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
        try await model.download(object, from: source, to: file, maximumBytes: 8 * 1024 * 1024)
        try Task.checkCancellation()
        let thumbnail: NSImage
        if isVideo {
          let request = QLThumbnailGenerator.Request(
            fileAt: file,
            size: CGSize(width: 520, height: 520),
            scale: 1,
            representationTypes: .thumbnail
          )
          thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        } else {
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
          thumbnail = NSImage(
            cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        try Task.checkCancellation()
        cache.insert(thumbnail, for: cacheKey)
        image = thumbnail
        loadedKey = cacheKey
      } catch {
      }
    }
  }

  private var cacheKey: String? {
    guard let source = model.downloadSource() else { return nil }
    let key = Data(object.key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
    return "\(source.profile.id)/\(source.bucket)/\(key)/\(object.eTag ?? "")/\(object.size)"
  }

  private var displayedImage: NSImage? {
    guard let cacheKey else { return nil }
    return cache.image(for: cacheKey) ?? (loadedKey == cacheKey ? image : nil)
  }
}
