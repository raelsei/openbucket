import AppKit
import OpenBucketCore
import QuickLook
import SwiftUI

struct ObjectBrowserView: View {
  let model: AppModel
  @Binding var layout: BrowserLayout
  let showSidebar: () -> Void
  let addConnection: () -> Void
  let editConnection: () -> Void

  @State private var inspectedRow: BrowserRow?
  @State private var showsInspector = false
  @State private var thumbnailCache = ThumbnailCache()
  @State private var previewURL: URL?
  @State private var previewDirectory: URL?
  @State private var previewTask: Task<Void, Never>?
  @State private var previewRequestID: UUID?
  @State private var previewError: String?
  @State private var isPreparingPreview = false

  var body: some View {
    VStack(spacing: 0) {
      if let location = model.browser.location {
        locationBar(location)
        Divider()
      }
      if let failure = model.connectionFailure ?? model.browser.failure, rows.isEmpty {
        failureView(failure)
      } else if model.browser.location == nil
        && (model.isConnecting || model.browser.isLoading)
      {
        ProgressView("Loading S3 contents…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.selectedProfile == nil {
        ContentUnavailableView {
          Label("Welcome to OpenBucket", systemImage: "externaldrive.connected.to.line.below")
        } description: {
          Text("Add an S3 connection to browse your objects.")
        } actions: {
          Button("Add Connection", action: addConnection).buttonStyle(.glassProminent)
        }
      } else if model.browser.location == nil {
        ContentUnavailableView {
          Label(
            model.buckets.isEmpty ? "No buckets available" : "Choose a bucket", systemImage: "shippingbox")
        } description: {
          Text(
            model.buckets.isEmpty
              ? "Enter a known bucket in connection settings if listing all buckets is restricted."
              : "Select a bucket in the sidebar to browse its objects."
          )
        } actions: {
          if model.buckets.isEmpty {
            Button("Edit Connection", action: editConnection).buttonStyle(.glassProminent)
          } else {
            Button("Show Sidebar", action: showSidebar).buttonStyle(.glassProminent)
          }
        }
      } else {
        if let failure = model.connectionFailure ?? model.browser.failure {
          HStack {
            Label(failure.message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            Spacer()
            Button("Retry") { model.browser.nextToken == nil ? model.refresh() : model.loadNextPage() }
          }
          .padding(12)
        }
        if let previewError {
          HStack {
            Label(previewError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            Spacer()
            Button("Dismiss") { self.previewError = nil }
          }
          .padding(12)
        }
        if rows.isEmpty {
          ContentUnavailableView(
            "This prefix is empty",
            systemImage: "tray",
            description: Text("There are no objects or child prefixes here.")
          )
        } else {
          if layout == .grid {
            GeometryReader { geometry in
              let availableWidth = geometry.size.width + (showsInspector ? 360 : 0)
              let columns = availableWidth < 560 ? 1 : availableWidth < 1000 ? 2 : 3
              ScrollViewReader { scroll in
                List {
                  ForEach(gridRows(columns: columns)) { group in
                    HStack(alignment: .top, spacing: 16) {
                      ForEach(group.items) { row in
                        BrowserGridCard(
                          row: row, model: model, thumbnailCache: thumbnailCache,
                          isSelected: showsInspector && inspectedRow?.id == row.id,
                          open: { open(row) }, inspect: { inspect(row) }
                        )
                        .frame(maxWidth: .infinity)
                      }
                      ForEach(0..<(columns - group.items.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                      }
                    }
                    .accessibilityActions {
                      ForEach(group.items) { row in
                        Button("Open \(row.name)") { open(row) }
                      }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                  }
                  if let token = model.browser.nextToken {
                    loadMore(token).listRowBackground(Color.clear).listRowSeparator(.hidden)
                  }
                }
                .listStyle(.plain)
                .onChange(of: rows.first?.id) { _, firstID in
                  if let firstID { scrollToTop(firstID, using: scroll) }
                }
              }
            }
          } else {
            GeometryReader { geometry in
              let compact = geometry.size.width < 620
              VStack(spacing: 0) {
                BrowserListHeader(compact: compact)
                  .padding(.horizontal, 16)
                Divider()
                ScrollViewReader { scroll in
                  List {
                    ForEach(rows) { row in
                      BrowserListRow(
                        row: row, model: model, thumbnailCache: thumbnailCache,
                        compact: compact, isSelected: showsInspector && inspectedRow?.id == row.id,
                        open: { open(row) }, inspect: { inspect(row) }
                      )
                      .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                      .listRowSeparator(.hidden)
                    }
                    if let token = model.browser.nextToken {
                      loadMore(token).listRowSeparator(.hidden)
                    }
                  }
                  .listStyle(.plain)
                  .onChange(of: rows.first?.id) { _, firstID in
                    if let firstID { scrollToTop(firstID, using: scroll) }
                  }
                }
              }
            }
          }
        }
      }
    }
    .inspector(isPresented: $showsInspector) {
      if let inspectedRow, let object = inspectedRow.object {
        ObjectInspectorView(
          row: inspectedRow, object: object, model: model, thumbnailCache: thumbnailCache,
          close: { showsInspector = false }
        ) {
          preparePreview(object)
        }
        .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
      }
    }
    .quickLookPreview($previewURL)
    .onChange(of: previewURL) { _, url in
      if url == nil { clearPreview() }
    }
    .onChange(of: model.browser.location) { _, _ in
      previewTask?.cancel()
      previewTask = nil
      previewRequestID = nil
      isPreparingPreview = false
      previewURL = nil
      clearPreview()
      inspectedRow = nil
      showsInspector = false
    }
  }

  private func locationBar(_ location: S3Location) -> some View {
    HStack(spacing: 12) {
      Button {
        guard let parent = parent(of: location),
          let next = try? S3Location(bucket: location.bucket, prefix: parent)
        else { return }
        model.open(next)
      } label: {
        Image(systemName: "chevron.left")
      }
      .disabled(location.prefix.isEmpty)
      .help("Parent prefix")
      Image(systemName: "shippingbox").foregroundStyle(.secondary)
      Text(location.displayString)
        .font(.system(.body, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.middle)
        .contextMenu {
          Button("Copy S3 Location") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(location.displayString, forType: .string)
          }
        }
      Spacer()
      Text("\(model.browser.objects.count) objects")
        .font(.caption)
        .foregroundStyle(.secondary)
      if isPreparingPreview || model.isConnecting || model.browser.isLoading {
        ProgressView().controlSize(.small)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private func failureView(_ failure: S3Failure) -> some View {
    ContentUnavailableView {
      Label("Connection failed", systemImage: "exclamationmark.triangle")
    } description: {
      VStack(spacing: 8) {
        Text(failure.message)
        if let detail = failure.technicalDetail {
          Text(detail).font(.caption.monospaced()).textSelection(.enabled)
        }
      }
    } actions: {
      Button("Try Again") { model.refresh() }
    }
  }

  private var rows: [BrowserRow] {
    guard let location = model.browser.location else { return [] }
    return model.browser.prefixes.map { BrowserRow(prefix: $0, parentPrefix: location.prefix) }
      + model.browser.objects.map { BrowserRow(object: $0, parentPrefix: location.prefix) }
  }

  private func open(_ row: BrowserRow) {
    if let prefix = row.prefix,
      let bucket = model.browser.location?.bucket,
      let location = try? S3Location(bucket: bucket, prefix: prefix)
    {
      model.open(location)
    } else if row.object != nil {
      inspect(row)
    }
  }

  private func inspect(_ row: BrowserRow) {
    guard row.object != nil else { return }
    inspectedRow = row
    showsInspector = true
  }

  private func preparePreview(_ object: ObjectSummary) {
    guard object.size <= 64 * 1024 * 1024 else {
      previewError = "This object is larger than the 64 MB preview limit."
      return
    }
    previewTask?.cancel()
    previewError = nil
    isPreparingPreview = true
    let requestID = UUID()
    previewRequestID = requestID
    let currentLocation = model.browser.location
    previewTask = Task {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("OpenBucketPreview-\(UUID().uuidString)", isDirectory: true)
      do {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
        let destination = directory.appendingPathComponent(PreviewFileName.from(objectKey: object.key))
        try await model.download(object, to: destination, maximumBytes: 64 * 1024 * 1024)
        guard !Task.isCancelled, model.browser.location == currentLocation else {
          try? FileManager.default.removeItem(at: directory)
          return
        }
        clearPreview()
        previewDirectory = directory
        previewURL = destination
      } catch {
        try? FileManager.default.removeItem(at: directory)
        if !Task.isCancelled {
          previewError = (error as? S3Failure)?.message ?? "This object could not be previewed."
        }
      }
      if previewRequestID == requestID {
        isPreparingPreview = false
        previewRequestID = nil
        previewTask = nil
      }
    }
  }

  private func clearPreview() {
    if let previewDirectory { try? FileManager.default.removeItem(at: previewDirectory) }
    previewDirectory = nil
  }

  private func loadMore(_ token: String) -> some View {
    HStack(spacing: 10) {
      ProgressView().controlSize(.small)
      Text("Loading more objects…").foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(20)
    .id(token)
    .onScrollVisibilityChange(threshold: 0.5) { visible in
      if visible && model.browser.failure == nil { model.loadNextPage() }
    }
  }

  private func gridRows(columns: Int) -> [BrowserGridRow] {
    let items = rows
    return stride(from: 0, to: items.count, by: columns).map { offset in
      let group = Array(items[offset..<min(offset + columns, items.count)])
      return BrowserGridRow(id: group[0].id, items: group)
    }
  }

  private func scrollToTop(_ rowID: String, using proxy: ScrollViewProxy) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      proxy.scrollTo(rowID, anchor: .top)
    }
  }

  private func parent(of location: S3Location) -> String? {
    guard !location.prefix.isEmpty else { return nil }
    let withoutTrailingSlash =
      location.prefix.hasSuffix("/")
      ? String(location.prefix.dropLast()) : location.prefix
    guard let separator = withoutTrailingSlash.lastIndex(of: "/") else { return "" }
    return String(withoutTrailingSlash[...separator])
  }
}

private struct BrowserGridRow: Identifiable {
  let id: String
  let items: [BrowserRow]
}
