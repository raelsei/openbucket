import SwiftUI

struct BrowserListRow: View {
  let row: BrowserRow
  let open: () -> Void
  let inspect: () -> Void
  @State private var hovered = false

  var body: some View {
    HStack(spacing: 0) {
      Button(action: open) {
        HStack(spacing: 12) {
          Image(systemName: row.symbol)
            .font(.title3)
            .foregroundStyle(row.prefix == nil ? Color.secondary : Color.accentColor)
            .frame(width: 28)
          Text(row.name)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
          if let object = row.object {
            Text(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))
              .frame(width: 90, alignment: .trailing)
              .foregroundStyle(.secondary)
            Text(object.lastModified ?? .distantPast, format: .dateTime.year().month().day())
              .frame(width: 110, alignment: .trailing)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(row.name)
      .accessibilityHint(row.prefix == nil ? "Show object information" : "Open folder")
      if row.object != nil {
        Button(action: inspect) {
          Image(systemName: "info.circle").frame(width: 36, height: 40)
        }
        .buttonStyle(.plain)
        .help("Object information")
        .accessibilityLabel("Information for \(row.name)")
      }
    }
    .background(
      hovered ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8)
    )
    .onHover { hovered = $0 }
    .contextMenu {
      if row.object != nil { Button("Get Info", action: inspect) }
    }
    .help(row.fullKey)
  }
}
