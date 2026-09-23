import Foundation
import OpenBucketCore
import UniformTypeIdentifiers

enum BrowserLayout: Hashable {
  case grid
  case list
}

struct BrowserRow: Identifiable {
  let id: String
  let name: String
  let fullKey: String
  let prefix: String?
  let object: ObjectSummary?

  var sortSize: Int64 { object?.size ?? -1 }
  var sortModified: Date { object?.lastModified ?? .distantPast }

  var kindLabel: String {
    if prefix != nil { return "Folder" }
    return switch symbol {
    case "photo": "Image"
    case "play.rectangle": "Video"
    case "waveform": "Audio"
    case "doc.richtext": "PDF"
    case "doc.text": "Text"
    default: "File"
    }
  }

  var symbol: String {
    if prefix != nil { return "folder.fill" }
    guard let type = UTType(filenameExtension: (fullKey as NSString).pathExtension) else { return "doc" }
    if type.conforms(to: .image) { return "photo" }
    if type.conforms(to: .movie) { return "play.rectangle" }
    if type.conforms(to: .audio) { return "waveform" }
    if type.conforms(to: .pdf) { return "doc.richtext" }
    if type.conforms(to: .text) { return "doc.text" }
    return "doc"
  }

  var isImage: Bool {
    guard let object,
      object.size <= 8 * 1024 * 1024,
      let type = UTType(filenameExtension: (fullKey as NSString).pathExtension)
    else { return false }
    return type.conforms(to: .image)
  }

  var isVideo: Bool {
    guard let object,
      object.size <= 8 * 1024 * 1024,
      let type = UTType(filenameExtension: (fullKey as NSString).pathExtension)
    else { return false }
    return type.conforms(to: .movie)
  }

  init(prefix: String, parentPrefix: String) {
    id = Data([0] + Array(prefix.utf8)).base64EncodedString()
    fullKey = prefix
    self.prefix = prefix
    object = nil
    let relative = prefix.hasPrefix(parentPrefix) ? String(prefix.dropFirst(parentPrefix.count)) : prefix
    name = relative.hasSuffix("/") ? String(relative.dropLast()) : relative
  }

  init(object: ObjectSummary, parentPrefix: String) {
    id = Data([1] + Array(object.key.utf8)).base64EncodedString()
    fullKey = object.key
    prefix = nil
    self.object = object
    let relative =
      object.key.hasPrefix(parentPrefix)
      ? String(object.key.dropFirst(parentPrefix.count)) : object.key
    name = relative.isEmpty ? "(current prefix marker)" : relative
  }
}
