import AppKit
import OpenBucketCore
import SwiftUI

struct ObjectInspectorView: View {
  let row: BrowserRow
  let object: ObjectSummary
  let model: AppModel
  let thumbnailCache: ThumbnailCache
  let close: () -> Void
  let preview: () -> Void

  @State private var downloadState: DownloadState?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("Info")
            .font(.headline)
          Spacer()
          Button("Close Info", systemImage: "xmark", action: close)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.small)
        }

        artwork
          .frame(height: 180)
          .frame(maxWidth: .infinity)
          .accessibilityLabel("Preview of \(row.name)")
          .padding(.top, 18)

        Text(row.name)
          .font(.title3.weight(.semibold))
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 16)

        HStack(spacing: 6) {
          Label(row.kindLabel, systemImage: row.symbol)
          Text("·")
          Text(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.top, 5)

        GlassEffectContainer(spacing: 10) {
          HStack(spacing: 10) {
            Button(action: preview) {
              Label("Preview", systemImage: "eye")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(object.size > 64 * 1024 * 1024)
            .help("Open in Quick Look (up to 64 MB)")
            Button(action: chooseDownloadLocation) {
              Label("Download", systemImage: "arrow.down.to.line")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .disabled(currentDownloadState?.isRunning == true)
          }
          .controlSize(.large)
        }
        .padding(.top, 18)

        if let state = currentDownloadState {
          if state.isRunning {
            ProgressView("Downloading…")
              .padding(.top, 12)
          } else if let message = state.message {
            Label(
              message,
              systemImage: state.failed ? "exclamationmark.triangle" : "checkmark.circle"
            )
            .font(.callout)
            .foregroundStyle(state.failed ? .orange : .secondary)
            .padding(.top, 12)
          }
        }

        Divider()
          .padding(.vertical, 20)

        Text("Details")
          .font(.headline)
          .padding(.bottom, 5)

        detail("S3 key") {
          Text(object.key)
            .font(.callout.monospaced())
            .textSelection(.enabled)
        }
        Divider()
        detail("Size") {
          Text(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))
        }
        if let date = object.lastModified {
          Divider()
          detail("Modified") {
            Text(date, format: .dateTime.year().month().day().hour().minute())
          }
        }
        if let eTag = object.eTag {
          Divider()
          detail("ETag") {
            Text(eTag)
              .font(.callout.monospaced())
              .textSelection(.enabled)
          }
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var artwork: some View {
    BrowserArtwork(
      row: row, model: model, cache: thumbnailCache, contentMode: .fit,
      symbolSize: 56, cornerRadius: 14
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var currentDownloadState: DownloadState? {
    downloadState?.rowID == row.id ? downloadState : nil
  }

  private func detail<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title.uppercased())
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 11)
  }

  private func chooseDownloadLocation() {
    guard let source = model.downloadSource() else {
      downloadState = DownloadState(
        requestID: UUID(), rowID: row.id, isRunning: false,
        message: "Select a connection and bucket before downloading.", failed: true
      )
      return
    }
    let selectedRowID = row.id
    let panel = NSSavePanel()
    panel.nameFieldStringValue = PreviewFileName.from(objectKey: object.key)
    panel.canCreateDirectories = true
    panel.begin { response in
      guard response == .OK, let destination = panel.url else { return }
      Task { @MainActor in
        let requestID = UUID()
        downloadState = DownloadState(
          requestID: requestID, rowID: selectedRowID, isRunning: true,
          message: nil, failed: false
        )
        let scoped = destination.startAccessingSecurityScopedResource()
        defer {
          if scoped { destination.stopAccessingSecurityScopedResource() }
        }
        do {
          try await model.download(object, from: source, to: destination, maximumBytes: .max)
          guard downloadState?.requestID == requestID else { return }
          downloadState = DownloadState(
            requestID: requestID, rowID: selectedRowID, isRunning: false,
            message: "Saved \(destination.lastPathComponent).", failed: false
          )
        } catch {
          guard downloadState?.requestID == requestID else { return }
          downloadState = DownloadState(
            requestID: requestID, rowID: selectedRowID, isRunning: false,
            message: AppModel.failure(for: error).message, failed: true
          )
        }
      }
    }
  }
}

private struct DownloadState {
  let requestID: UUID
  let rowID: String
  let isRunning: Bool
  let message: String?
  let failed: Bool
}
