import OpenBucketCore
import SwiftUI

struct ObjectInspectorView: View {
  let object: ObjectSummary

  var body: some View {
    Form {
      Section("Object") {
        LabeledContent("Key") {
          Text(object.key)
            .textSelection(.enabled)
        }
        LabeledContent("Size") {
          Text(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))
        }
        if let date = object.lastModified {
          LabeledContent("Modified") {
            Text(date, format: .dateTime.year().month().day().hour().minute())
          }
        }
        if let eTag = object.eTag {
          LabeledContent("ETag") {
            Text(eTag)
              .textSelection(.enabled)
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Object Info")
  }
}
