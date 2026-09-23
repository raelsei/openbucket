import AppKit
import OpenBucketCore
import SwiftUI

struct ObjectInspectorView: View {
  let row: BrowserRow
  let object: ObjectSummary
  let model: AppModel
  let preview: () -> Void

  @State private var isDownloading = false
  @State private var downloadMessage: String?
  @State private var downloadFailed = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        artwork
          .frame(height: 200)
          .clipShape(.rect(cornerRadius: 12))
          .accessibilityLabel("Preview of \(row.name)")

        Text(row.name)
          .font(.title3.weight(.semibold))
          .lineLimit(2)

        HStack(spacing: 8) {
          Button("Preview", systemImage: "eye", action: preview)
            .buttonStyle(.glass)
            .disabled(object.size > 64 * 1024 * 1024)
            .help("Open in Quick Look (up to 64 MB)")
          Button("Download", systemImage: "arrow.down.to.line", action: chooseDownloadLocation)
            .buttonStyle(.glassProminent)
            .disabled(isDownloading)
        }

        if isDownloading {
          ProgressView("Downloading…")
        }
        if let downloadMessage {
          Label(
            downloadMessage,
            systemImage: downloadFailed ? "exclamationmark.triangle" : "checkmark.circle"
          )
          .font(.callout)
          .foregroundStyle(downloadFailed ? .orange : .secondary)
        }

        Divider()

        LabeledContent("Key") {
          Text(object.key)
            .textSelection(.enabled)
        }
        LabeledContent("Size") {
          Text(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))
        }
        if let date = object.lastModified {
          LabeledContent("Modified") {
            Text(date, format: .dateTime.year().month().day().hour().minute())
          }
        }
        if let eTag = object.eTag {
          LabeledContent("ETag") {
            Text(eTag)
              .textSelection(.enabled)
          }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var artwork: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08))
      if row.isImage || row.isVideo {
        BrowserThumbnail(object: object, model: model, isVideo: row.isVideo)
      } else {
        Image(systemName: row.symbol)
          .font(.system(size: 54, weight: .light))
          .foregroundStyle(.secondary)
      }
    }
    .clipped()
  }

  private func chooseDownloadLocation() {
    guard let source = model.downloadSource() else {
      downloadMessage = "Select a connection and bucket before downloading."
      downloadFailed = true
      return
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = PreviewFileName.from(objectKey: object.key)
    panel.canCreateDirectories = true
    panel.begin { response in
      guard response == .OK, let destination = panel.url else { return }
      Task { @MainActor in
        isDownloading = true
        downloadMessage = nil
        let scoped = destination.startAccessingSecurityScopedResource()
        defer {
          if scoped { destination.stopAccessingSecurityScopedResource() }
          isDownloading = false
        }
        do {
          try await model.download(object, from: source, to: destination, maximumBytes: .max)
          downloadMessage = "Saved \(destination.lastPathComponent)."
          downloadFailed = false
        } catch {
          downloadMessage = AppModel.failure(for: error).message
          downloadFailed = true
        }
      }
    }
  }
}
