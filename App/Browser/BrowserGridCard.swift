import OpenBucketCore
import SwiftUI

struct BrowserGridCard: View {
  let row: BrowserRow
  let model: AppModel
  let thumbnailCache: ThumbnailCache
  let isSelected: Bool
  let selectionMode: Bool
  let open: () -> Void
  let inspect: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: open) {
      VStack(alignment: .leading, spacing: 8) {
        artwork
          .overlay(alignment: .topTrailing) {
            if selectionMode, row.object != nil {
              Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(8)
                .accessibilityHidden(true)
            }
          }
        Text(row.name).font(.body.weight(.medium)).lineLimit(1)
        if let object = row.object {
          Text(
            "\(row.kindLabel) · \(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))"
          )
          .font(.caption).foregroundStyle(.secondary)
        } else {
          Text(row.kindLabel).font(.caption).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .contentShape(cardShape)
    }
    .buttonStyle(.plain)
    .background(cardFill, in: cardShape)
    .overlay(
      cardShape.strokeBorder(
        isSelected
          ? Color.accentColor.opacity(0.55)
          : hovered ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12))
    )
    .onHover { hovered = $0 }
    .accessibilityLabel("\(row.name), \(row.prefix == nil ? "object" : "folder")")
    .accessibilityHint(
      row.prefix == nil
        ? selectionMode ? "Toggle selection" : "Show object information"
        : "Open folder"
    )
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .contextMenu {
      if row.object != nil { Button("Get Info", action: inspect) }
    }
    .help(row.fullKey)
  }

  private var artwork: some View {
    GeometryReader { geometry in
      BrowserArtwork(
        row: row, model: model, cache: thumbnailCache, contentMode: .fill,
        cornerRadius: 20
      )
      .frame(width: geometry.size.width, height: geometry.size.height)
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .frame(height: 160)
  }

  private var cardFill: Color {
    if isSelected { return Color.accentColor.opacity(0.13) }
    if hovered { return Color.accentColor.opacity(0.08) }
    return Color.secondary.opacity(0.035)
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 24, style: .continuous)
  }
}
