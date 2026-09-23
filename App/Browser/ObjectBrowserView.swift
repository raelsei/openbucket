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
  @State private var selectedIDs = Set<BrowserRow.ID>()
  @State private var sortOrder = [KeyPathComparator(\BrowserRow.name)]
  @State private var isSelectingGrid = false
  @State private var batchTask: Task<Void, Never>?
  @State private var batchProgress: BatchDownloadProgress?
  @State private var batchResult: BatchDownloadResult?
  @State private var batchMessage: String?

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
                          isSelected: selectedIDs.contains(row.id)
                            || (showsInspector && inspectedRow?.id == row.id),
                          selectionMode: isSelectingGrid,
                          open: { gridAction(row) }, inspect: { inspect(row) }
                        )
                        .frame(maxWidth: .infinity)
                      }
                      ForEach(0..<(columns - group.items.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                      }
                    }
                    .accessibilityActions {
                      ForEach(group.items) { row in
                        Button(
                          isSelectingGrid && row.object != nil
                            ? "\(selectedIDs.contains(row.id) ? "Deselect" : "Select") \(row.name)"
                            : "Open \(row.name)"
                        ) { gridAction(row) }
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
            ObjectTableView(
              rows: rows, model: model, thumbnailCache: thumbnailCache,
              nextToken: model.browser.nextToken, selection: $selectedIDs,
              sortOrder: $sortOrder, loadNextPage: model.loadNextPage
            )
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if selectedIDs.count > 1 || isSelectingGrid
        || batchProgress != nil || batchResult != nil || batchMessage != nil
      {
        selectionBar
      }
    }
    .inspector(isPresented: $showsInspector) {
      if let inspectedRow, let object = inspectedRow.object {
        ObjectInspectorView(
          row: inspectedRow, object: object, model: model, thumbnailCache: thumbnailCache,
          close: {
            showsInspector = false
            if selectedIDs.count == 1 { selectedIDs.removeAll() }
          }
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
      selectedIDs.removeAll()
      isSelectingGrid = false
    }
    .onChange(of: selectedIDs) { _, selection in
      guard layout == .list else { return }
      guard selection.count == 1,
        let id = selection.first,
        let row = rows.first(where: { $0.id == id })
      else {
        showsInspector = false
        return
      }
      if row.prefix != nil {
        open(row)
      } else {
        inspect(row)
      }
    }
    .onChange(of: Set(rows.map(\.id))) { _, availableIDs in
      selectedIDs.formIntersection(availableIDs)
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
      Text(
        "\(model.browser.objects.count) \(model.browser.objects.count == 1 ? "file" : "files") loaded"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      if layout == .grid, model.browser.objects.count > 1 {
        Button(isSelectingGrid ? "Done" : "Select") {
          isSelectingGrid.toggle()
          if !isSelectingGrid { selectedIDs.removeAll() }
        }
        .buttonStyle(.glass)
      } else if layout == .list, model.browser.objects.count > 1 {
        Button("Select Loaded") {
          selectedIDs = Set(rows.filter { $0.object != nil }.map(\.id))
          showsInspector = false
        }
        .buttonStyle(.glass)
        .help("Select all files loaded from this prefix")
      }
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

  private var selectedObjects: [ObjectSummary] {
    rows.filter { selectedIDs.contains($0.id) }.compactMap(\.object)
  }

  private var selectionBar: some View {
    GlassEffectContainer(spacing: 8) {
      HStack(spacing: 12) {
        if let batchProgress {
          ProgressView(value: Double(batchProgress.completed), total: Double(batchProgress.total))
            .frame(width: 120)
          Text("\(batchProgress.completed) of \(batchProgress.total) processed")
            .font(.callout)
          Button("Cancel") { batchTask?.cancel() }
            .buttonStyle(.glass)
        } else if let batchResult {
          Label(
            "\(batchResult.cancelled ? "Stopped" : "Finished"): \(batchResult.downloaded) saved, \(batchResult.failedKeys.count) failed",
            systemImage: batchResult.cancelled || !batchResult.failedKeys.isEmpty
              ? "exclamationmark.triangle" : "checkmark.circle"
          )
          .font(.callout)
          .lineLimit(1)
          Spacer(minLength: 8)
          if !batchResult.failedKeys.isEmpty {
            Button("Copy Failed Keys") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(
                batchResult.failedKeys.joined(separator: "\n"), forType: .string)
            }
            .buttonStyle(.glass)
          }
          Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([batchResult.directory])
          }
          .buttonStyle(.glass)
          Button("Dismiss") { self.batchResult = nil }
            .buttonStyle(.glass)
        } else if let batchMessage {
          Label(batchMessage, systemImage: "exclamationmark.triangle")
            .font(.callout)
          Spacer(minLength: 8)
          Button("Dismiss") { self.batchMessage = nil }
            .buttonStyle(.glass)
        } else {
          Text(
            "\(selectedObjects.count) loaded \(selectedObjects.count == 1 ? "file" : "files") selected"
          )
          .font(.callout)
          Spacer(minLength: 8)
          if isSelectingGrid {
            Button("Select Loaded") {
              selectedIDs = Set(rows.filter { $0.object != nil }.map(\.id))
            }
            .buttonStyle(.glass)
          }
          if !selectedIDs.isEmpty {
            Button("Clear Selection") { selectedIDs.removeAll() }
              .buttonStyle(.glass)
          }
          Button("Download Selected", systemImage: "arrow.down.to.line") {
            chooseBatchDestination()
          }
          .buttonStyle(.glassProminent)
          .disabled(selectedObjects.isEmpty)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity)
      .glassEffect(.regular, in: .rect(cornerRadius: 16))
      .padding(.horizontal, 16)
      .padding(.bottom, 8)
    }
  }

  private func chooseBatchDestination() {
    guard !selectedObjects.isEmpty, let source = model.downloadSource() else { return }
    let objects = selectedObjects
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Download"
    panel.message = "OpenBucket will create a new folder for the selected files."
    panel.begin { response in
      guard response == .OK, let directory = panel.url else { return }
      Task { @MainActor in
        startBatchDownload(objects, from: source, into: directory)
      }
    }
  }

  private func startBatchDownload(
    _ objects: [ObjectSummary], from source: AppModel.DownloadSource, into directory: URL
  ) {
    guard batchTask == nil else { return }
    batchResult = nil
    batchMessage = nil
    batchProgress = BatchDownloadProgress(completed: 0, total: objects.count, failed: 0)
    batchTask = Task {
      let scoped = directory.startAccessingSecurityScopedResource()
      defer {
        if scoped { directory.stopAccessingSecurityScopedResource() }
        batchProgress = nil
        batchTask = nil
      }
      do {
        let result = try await model.downloadSelected(objects, from: source, into: directory) {
          batchProgress = $0
        }
        batchResult = result
        selectedIDs.removeAll()
      } catch {
        batchMessage = AppModel.failure(for: error).message
      }
    }
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

  private func gridAction(_ row: BrowserRow) {
    if isSelectingGrid, row.object != nil {
      if !selectedIDs.insert(row.id).inserted { selectedIDs.remove(row.id) }
      showsInspector = false
    } else {
      open(row)
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
