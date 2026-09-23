import OpenBucketCore
import SwiftUI

struct ObjectTableView: View {
  let rows: [BrowserRow]
  let model: AppModel
  let thumbnailCache: ThumbnailCache
  let nextToken: String?
  @Binding var selection: Set<BrowserRow.ID>
  @Binding var sortOrder: [KeyPathComparator<BrowserRow>]
  let loadNextPage: () -> Void

  @State private var isNearBottom = false

  var body: some View {
    let items = sortedRows
    return Table(items, selection: $selection, sortOrder: $sortOrder) {
      TableColumn("Name", value: \.name) { row in
        nameCell(row)
          .onAppear {
            if row.id == items.last?.id, nextToken != nil { loadNextPage() }
          }
      }
      .width(min: 160, ideal: 300)

      TableColumn("Size", value: \.sortSize) { row in
        Text(
          row.object.map {
            ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file)
          } ?? "—"
        )
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(90)

      TableColumn("Modified", value: \.sortModified) { row in
        Group {
          if let date = row.object?.lastModified {
            Text(date, format: .dateTime.year().month().day())
          } else {
            Text("—")
          }
        }
        .foregroundStyle(.secondary)
      }
      .width(145)
    }
    .tableStyle(.inset)
    .alternatingRowBackgrounds(.disabled)
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.visibleRect.maxY >= geometry.contentSize.height - 240
    } action: { _, nearBottom in
      isNearBottom = nearBottom
      if nearBottom, nextToken != nil { loadNextPage() }
    }
    .onChange(of: nextToken) { _, token in
      if token != nil, isNearBottom { loadNextPage() }
    }
  }

  private func nameCell(_ row: BrowserRow) -> some View {
    HStack(spacing: 10) {
      BrowserArtwork(
        row: row, model: model, cache: thumbnailCache, symbolSize: 18,
        cornerRadius: 6, showsVideoBadge: false
      )
      .frame(width: 32, height: 32)
      .clipped()
      .clipShape(.rect(cornerRadius: 6))
      VStack(alignment: .leading, spacing: 2) {
        Text(row.name).lineLimit(1)
        Text(row.kindLabel).font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .help(row.fullKey)
  }

  private var sortedRows: [BrowserRow] {
    let folders = rows.filter { $0.prefix != nil }.sorted(using: sortOrder)
    let objects = rows.filter { $0.object != nil }.sorted(using: sortOrder)
    return folders + objects
  }
}
