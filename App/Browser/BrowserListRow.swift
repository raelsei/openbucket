import OpenBucketCore
import SwiftUI

struct BrowserListRow: View {
  let row: BrowserRow
  let model: AppModel
  let thumbnailCache: ThumbnailCache
  let compact: Bool
  let isSelected: Bool
  let open: () -> Void
  let inspect: () -> Void

  @State private var hovered = false

  var body: some View {
    HStack(spacing: 0) {
      Button(action: open) {
        HStack(spacing: 12) {
          BrowserArtwork(
            row: row, model: model, cache: thumbnailCache, symbolSize: 22,
            cornerRadius: 8, showsVideoBadge: false
          )
          .frame(width: 44, height: 44)
          .clipShape(.rect(cornerRadius: 8))

          VStack(alignment: .leading, spacing: 4) {
            Text(row.name)
              .font(.body.weight(.medium))
              .lineLimit(1)
            Text(compact ? compactMetadata : row.kindLabel)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          if !compact {
            Text(
              row.object.map {
                ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file)
              } ?? "—"
            )
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .trailing)

            Group {
              if let date = row.object?.lastModified {
                Text(date, format: .dateTime.year().month().day())
              } else {
                Text("—")
              }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: 120, alignment: .trailing)
          }

          if row.prefix != nil {
            Image(systemName: "chevron.right")
              .font(.callout)
              .foregroundStyle(.secondary)
              .frame(width: 28)
              .accessibilityHidden(true)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.leading, 12)
        .padding(.trailing, row.object == nil ? 12 : 8)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(row.name)
      .accessibilityHint(row.prefix == nil ? "Show object information" : "Open folder")
      .help(row.fullKey)

      if row.object != nil {
        Button(action: inspect) {
          Image(systemName: "info.circle")
            .font(.system(size: 18, weight: .medium))
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Information for \(row.name)")
        .help("Object information")
        .padding(.trailing, 12)
      }
    }
    .background(fill, in: RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10).strokeBorder(
        isSelected ? Color.accentColor.opacity(0.5) : Color.clear)
    )
    .onHover { hovered = $0 }
    .contextMenu {
      if row.object != nil { Button("Get Info", action: inspect) }
    }
  }

  private var compactMetadata: String {
    var values = [row.kindLabel]
    if let object = row.object {
      values.append(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))
      if let date = object.lastModified {
        values.append(date.formatted(.dateTime.year().month().day()))
      }
    }
    return values.joined(separator: " · ")
  }

  private var fill: Color {
    if isSelected { return Color.accentColor.opacity(0.13) }
    if hovered { return Color.accentColor.opacity(0.08) }
    return Color.clear
  }
}

struct BrowserListHeader: View {
  let compact: Bool

  var body: some View {
    HStack(spacing: 12) {
      Color.clear.frame(width: 44, height: 1)
      Text("Name")
        .frame(maxWidth: .infinity, alignment: .leading)
      if !compact {
        Text("Size").frame(width: 80, alignment: .trailing)
        Text("Modified").frame(width: 120, alignment: .trailing)
      }
      Color.clear.frame(width: 28, height: 1)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .accessibilityHidden(true)
  }
}
