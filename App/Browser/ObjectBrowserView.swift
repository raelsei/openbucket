import OpenBucketCore
import SwiftUI

struct ObjectBrowserView: View {
  let model: AppModel

  @State private var inspectedObject: ObjectSummary?
  @State private var showsInspector = false

  var body: some View {
    VStack(spacing: 0) {
      if let location = model.browser.location {
        locationBar(location)
        Divider()
      }

      if let failure = model.connectionFailure ?? model.browser.failure, rows.isEmpty {
        failureView(failure)
      } else if model.isConnecting
        || (model.browser.isLoading && model.browser.objects.isEmpty && model.browser.prefixes.isEmpty)
      {
        ProgressView("Loading S3 contents…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.selectedProfile == nil {
        ContentUnavailableView(
          "Welcome to OpenBucket",
          systemImage: "externaldrive.connected.to.line.below",
          description: Text("Add an S3 connection to browse your objects.")
        )
      } else if model.browser.location == nil {
        if model.buckets.isEmpty {
          ContentUnavailableView(
            "No buckets available",
            systemImage: "shippingbox",
            description: Text(
              "Enter a known bucket in the connection settings if listing all buckets is restricted.")
          )
        } else {
          ContentUnavailableView(
            "Choose a bucket",
            systemImage: "shippingbox",
            description: Text("Select a bucket in the sidebar to browse its objects.")
          )
        }
      } else {
        if let failure = model.connectionFailure ?? model.browser.failure {
          HStack {
            Label(failure.message, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
            Spacer()
            Button("Retry") { model.refresh() }
          }
          .padding(10)
        }

        if rows.isEmpty {
          ContentUnavailableView(
            "This prefix is empty",
            systemImage: "tray",
            description: Text("There are no objects or child prefixes here.")
          )
        } else {
          Table(rows) {
            TableColumn("Name") { row in
              Button {
                open(row)
              } label: {
                Label(row.name, systemImage: row.prefix == nil ? "doc" : "folder")
                  .lineLimit(1)
              }
              .buttonStyle(.plain)
              .help(row.fullKey)
            }
            TableColumn("Size") { row in
              if let object = row.object {
                Text(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))
                  .foregroundStyle(.secondary)
              }
            }
            .width(min: 80, ideal: 110)
            TableColumn("Modified") { row in
              if let date = row.object?.lastModified {
                Text(date, format: .dateTime.year().month().day().hour().minute())
                  .foregroundStyle(.secondary)
              }
            }
            .width(min: 130, ideal: 170)
          }
          .tableStyle(.inset)
        }

        if model.browser.pageNumber > 1 || model.browser.nextToken != nil {
          Divider()
          HStack {
            Button("Previous Page") { model.loadPreviousPage() }
              .disabled(model.browser.pageNumber == 1 || model.browser.isLoading)
            Spacer()
            Text("Page \(model.browser.pageNumber)")
              .foregroundStyle(.secondary)
            Spacer()
            Button("Next Page") { model.loadNextPage() }
              .disabled(model.browser.nextToken == nil || model.browser.isLoading)
            if model.browser.isLoading { ProgressView().controlSize(.small) }
          }
          .padding(10)
        }
      }
    }
    .inspector(isPresented: $showsInspector) {
      if let object = inspectedObject {
        ObjectInspectorView(object: object)
          .inspectorColumnWidth(min: 250, ideal: 300, max: 380)
      }
    }
    .onChange(of: model.browser.location) { _, _ in
      inspectedObject = nil
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

      Image(systemName: "shippingbox")
        .foregroundStyle(.secondary)
      Text(location.displayString)
        .font(.system(.body, design: .monospaced))
        .lineLimit(1)
        .textSelection(.enabled)
      Spacer()
      Text("\(model.browser.objects.count) objects")
        .font(.caption)
        .foregroundStyle(.secondary)
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
          Text(detail)
            .font(.caption.monospaced())
            .textSelection(.enabled)
        }
      }
    } actions: {
      Button("Try Again") { model.refresh() }
    }
  }

  private var rows: [BrowserRow] {
    guard let location = model.browser.location else { return [] }
    let prefixes = model.browser.prefixes.map { prefix in
      BrowserRow(prefix: prefix, parentPrefix: location.prefix)
    }
    let objects = model.browser.objects.map { object in
      BrowserRow(object: object, parentPrefix: location.prefix)
    }
    return prefixes + objects
  }

  private func open(_ row: BrowserRow) {
    if let prefix = row.prefix,
      let bucket = model.browser.location?.bucket,
      let location = try? S3Location(bucket: bucket, prefix: prefix)
    {
      model.open(location)
    } else if let object = row.object {
      inspectedObject = object
      showsInspector = true
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

private struct BrowserRow: Identifiable {
  let id: [UInt8]
  let name: String
  let fullKey: String
  let prefix: String?
  let object: ObjectSummary?

  init(prefix: String, parentPrefix: String) {
    id = [0] + Array(prefix.utf8)
    fullKey = prefix
    self.prefix = prefix
    object = nil
    let relative = prefix.hasPrefix(parentPrefix) ? String(prefix.dropFirst(parentPrefix.count)) : prefix
    name = relative.hasSuffix("/") ? String(relative.dropLast()) : relative
  }

  init(object: ObjectSummary, parentPrefix: String) {
    id = [1] + Array(object.key.utf8)
    fullKey = object.key
    prefix = nil
    self.object = object
    let relative =
      object.key.hasPrefix(parentPrefix)
      ? String(object.key.dropFirst(parentPrefix.count)) : object.key
    name = relative.isEmpty ? "(current prefix marker)" : relative
  }
}
