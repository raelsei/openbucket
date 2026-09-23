import Foundation

enum PreviewFileName {
  static func from(objectKey: String) -> String {
    let component = String(objectKey.split(separator: "/").last ?? "object")
    let safe = String(
      component.filter { character in
        character != ":" && character != "\\" && !character.isNewline
          && !character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
      })
    let extensionStart = safe.lastIndex(of: ".")
    let extensionText = extensionStart.map { String(safe[safe.index(after: $0)...]) } ?? ""
    let hasExtension =
      !extensionText.isEmpty && extensionText.utf8.count <= 16
      && extensionText.unicodeScalars.allSatisfy {
        $0.value < 128 && CharacterSet.alphanumerics.contains($0)
      }
    let suffix = hasExtension ? ".\(extensionText)" : ""
    let stem: String
    if hasExtension, let extensionStart {
      stem = String(safe[..<extensionStart])
    } else {
      stem = safe
    }
    let byteLimit = 120 - suffix.utf8.count
    var shortened = ""
    for character in stem {
      guard shortened.utf8.count + String(character).utf8.count <= byteLimit else { break }
      shortened.append(character)
    }
    return (shortened.isEmpty || shortened == "." || shortened == ".." ? "object" : shortened) + suffix
  }
}
