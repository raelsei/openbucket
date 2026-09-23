import OpenBucketCore
import SwiftUI

struct ConnectionEditor: View {
  @Environment(\.dismiss) private var dismiss
  let model: AppModel
  let existing: ConnectionProfile?

  @State private var name: String
  @State private var endpoint: String
  @State private var region: String
  @State private var addressingStyle: AddressingStyle
  @State private var bucket: String
  @State private var startingPrefix: String
  @State private var accessKeyID = ""
  @State private var secretAccessKey = ""
  @State private var sessionToken = ""
  @State private var isWorking = false
  @State private var feedback: String?
  @State private var feedbackIsError = false

  init(model: AppModel, existing: ConnectionProfile?) {
    self.model = model
    self.existing = existing
    _name = State(initialValue: existing?.name ?? "")
    _endpoint = State(initialValue: existing?.endpoint.absoluteString ?? "https://")
    _region = State(initialValue: existing?.region ?? "us-east-1")
    _addressingStyle = State(initialValue: existing?.addressingStyle ?? .automatic)
    _bucket = State(initialValue: existing?.knownBucket ?? "")
    _startingPrefix = State(initialValue: existing?.startingPrefix ?? "")
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section("Connection") {
          TextField("Name", text: $name)
          TextField("Endpoint URL", text: $endpoint)
            .textContentType(.URL)
          TextField("Region", text: $region)
          Picker("Bucket addressing", selection: $addressingStyle) {
            Text("Automatic").tag(AddressingStyle.automatic)
            Text("Path style").tag(AddressingStyle.path)
            Text("Virtual host").tag(AddressingStyle.virtualHost)
          }
        }

        Section("Starting location") {
          TextField("Known bucket (optional)", text: $bucket)
          TextField("Object key prefix (optional)", text: $startingPrefix)
          Text("A known bucket connects without permission to list every bucket.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Credentials") {
          TextField("Access key ID", text: $accessKeyID)
          SecureField("Secret access key", text: $secretAccessKey)
          SecureField("Session token (optional)", text: $sessionToken)
          Text("Credentials are saved in this Mac’s Keychain.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Request shape") {
          Text(requestShape)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
          Text("The endpoint path and object key prefix are separate settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let feedback {
          Section {
            Label(feedback, systemImage: feedbackIsError ? "exclamationmark.triangle" : "checkmark.circle")
              .foregroundStyle(feedbackIsError ? .red : .green)
          }
        }
      }
      .formStyle(.grouped)

      Divider()
      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Test Connection") { runTest() }
          .disabled(isWorking)
        Button(existing == nil ? "Add Connection" : "Save Changes") { save() }
          .buttonStyle(.glassProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(isWorking)
      }
      .padding()
    }
    .frame(minWidth: 540, minHeight: 610)
    .task {
      guard let existing else { return }
      do {
        let credentials = try await model.credentials(for: existing)
        accessKeyID = credentials.accessKeyID
        secretAccessKey = credentials.secretAccessKey
        sessionToken = credentials.sessionToken ?? ""
      } catch {
        feedback = AppModel.failure(for: error).message
        feedbackIsError = true
      }
    }
  }

  private var requestShape: String {
    guard let url = URLComponents(string: endpoint), let host = url.host else {
      return "Enter an endpoint URL to preview the request."
    }
    let basePath =
      url.percentEncodedPath.hasSuffix("/")
      ? String(url.percentEncodedPath.dropLast()) : url.percentEncodedPath
    let bucketName = bucket.isEmpty ? "<bucket>" : bucket
    switch addressingStyle {
    case .automatic:
      return "Custom endpoint uses path style; endpoint path: \(basePath.isEmpty ? "/" : basePath)"
    case .path:
      return "\(host)\(basePath)/\(bucketName)/<object-key>"
    case .virtualHost:
      if !basePath.isEmpty {
        return "Virtual host requires an endpoint without a path."
      }
      return "\(bucketName).\(host)\(basePath)/<object-key>"
    }
  }

  private func values() throws -> (ConnectionProfile, S3Credentials) {
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanAccessKey = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty, !cleanRegion.isEmpty,
      !cleanAccessKey.isEmpty, !secretAccessKey.isEmpty
    else { throw EditorError.missingRequiredField }
    let endpoint = try S3Endpoint(endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    let endpointPath =
      URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
    if addressingStyle == .virtualHost && !endpointPath.isEmpty && endpointPath != "/" {
      throw EditorError.virtualHostEndpointPath
    }
    let profile = ConnectionProfile(
      id: existing?.id ?? UUID(),
      name: cleanName,
      endpoint: endpoint,
      region: cleanRegion,
      addressingStyle: addressingStyle,
      knownBucket: bucket.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
      startingPrefix: startingPrefix,
      credentialReference: UUID()
    )
    let credentials = S3Credentials(
      accessKeyID: cleanAccessKey,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken.nilIfEmpty
    )
    return (profile, credentials)
  }

  private func runTest() {
    isWorking = true
    feedback = nil
    Task {
      do {
        let (profile, credentials) = try values()
        feedback = try await model.test(profile: profile, credentials: credentials)
        feedbackIsError = false
      } catch {
        show(error)
      }
      isWorking = false
    }
  }

  private func save() {
    isWorking = true
    feedback = nil
    Task {
      do {
        let (profile, credentials) = try values()
        try await model.save(profile, credentials: credentials)
        dismiss()
      } catch {
        show(error)
        isWorking = false
      }
    }
  }

  private func show(_ error: Error) {
    switch error {
    case EditorError.missingRequiredField:
      feedback = "Name, region, access key, and secret key are required."
    case EditorError.virtualHostEndpointPath:
      feedback = "Choose path style for an endpoint URL that contains a path."
    default:
      feedback = AppModel.failure(for: error).message
    }
    feedbackIsError = true
  }
}

private enum EditorError: Error {
  case missingRequiredField
  case virtualHostEndpointPath
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
