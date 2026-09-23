import OpenBucketCore
import SwiftUI

struct BrowserGridCard: View {
  let row: BrowserRow
  let model: AppModel
  let open: () -> Void
  let inspect: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: open) {
      VStack(alignment: .leading, spacing: 8) {
        artwork
        Text(row.name).font(.body.weight(.medium)).lineLimit(1)
        if let object = row.object {
          Text(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))
            .font(.caption).foregroundStyle(.secondary)
        } else {
          Text("Folder").font(.caption).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .contentShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .background(
      hovered ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.035),
      in: RoundedRectangle(cornerRadius: 14)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14).strokeBorder(
        hovered ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12))
    )
    .onHover { hovered = $0 }
    .accessibilityLabel("\(row.name), \(row.prefix == nil ? "object" : "folder")")
    .accessibilityHint(row.prefix == nil ? "Show object information" : "Open folder")
    .contextMenu {
      if row.object != nil { Button("Get Info", action: inspect) }
    }
    .help(row.fullKey)
  }

  private var artwork: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08))
      if row.isImage || row.isVideo, let object = row.object {
        BrowserThumbnail(object: object, model: model, isVideo: row.isVideo)
      } else {
        Image(systemName: row.symbol)
          .font(.system(size: 42, weight: .light))
          .foregroundStyle(row.prefix == nil ? Color.secondary : Color.accentColor)
      }
    }
    .frame(height: 160)
    .clipped()
  }
}
