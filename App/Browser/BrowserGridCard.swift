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
      .contentShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .background(cardFill, in: RoundedRectangle(cornerRadius: 14))
    .overlay(
      RoundedRectangle(cornerRadius: 14).strokeBorder(
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
    BrowserArtwork(row: row, model: model, cache: thumbnailCache, contentMode: .fit)
      .frame(height: 160)
      .clipped()
  }

  private var cardFill: Color {
    if isSelected { return Color.accentColor.opacity(0.13) }
    if hovered { return Color.accentColor.opacity(0.08) }
    return Color.secondary.opacity(0.035)
  }
}
