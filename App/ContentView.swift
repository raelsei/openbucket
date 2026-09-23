import OpenBucketCore
import SwiftUI

struct ContentView: View {
  @State private var model: AppModel
  @State private var sidebarSelection: UUID?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var browserLayout: BrowserLayout = .grid
  @State private var showsEditor = false
  @State private var editingProfile: ConnectionProfile?
  @State private var showsOpenLocation = false
  @State private var showsDeleteConfirmation = false

  init(repository: any S3Repository, profileStore: ProfileStore, credentialStore: any CredentialStore) {
    _model = State(
      initialValue: AppModel(
        repository: repository,
        profileStore: profileStore,
        credentialStore: credentialStore
      ))
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(selection: $sidebarSelection) {
        Section("Connections") {
          ForEach(model.profiles) { profile in
            Label(profile.name, systemImage: "externaldrive.connected.to.line.below")
              .tag(profile.id)
              .contextMenu {
                Button("Edit Connection") { edit(profile) }
                Button("Delete Connection", role: .destructive) {
                  model.selectProfile(profile.id)
                  showsDeleteConfirmation = true
                }
              }
          }
        }

        if !model.buckets.isEmpty {
          Section("Buckets") {
            ForEach(model.buckets, id: \.self) { bucket in
              Button {
                if let location = try? S3Location(bucket: bucket) {
                  model.open(location)
                }
              } label: {
                Label(bucket, systemImage: "shippingbox")
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .navigationTitle("OpenBucket")
      .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 350)
    } detail: {
      ObjectBrowserView(
        model: model,
        layout: $browserLayout,
        showSidebar: { columnVisibility = .all },
        addConnection: {
          editingProfile = nil
          showsEditor = true
        },
        editConnection: {
          if let profile = model.selectedProfile { edit(profile) }
        }
      )
      .navigationTitle(model.selectedProfile?.name ?? "Browse S3")
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          editingProfile = nil
          showsEditor = true
        } label: {
          Label("Add Connection", systemImage: "plus")
        }
        .help("Add S3 connection")
        .keyboardShortcut("n", modifiers: .command)

        if let profile = model.selectedProfile {
          Button {
            showsOpenLocation = true
          } label: {
            Label("Open S3 Location", systemImage: "arrow.right.doc.on.clipboard")
          }
          .help("Open s3://bucket/prefix")
          .keyboardShortcut("l", modifiers: .command)

          Button {
            model.refresh()
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .help("Refresh current location")
          .keyboardShortcut("r", modifiers: .command)

          Menu {
            Button("Edit Connection") { edit(profile) }
            Button("Delete Connection", role: .destructive) {
              showsDeleteConfirmation = true
            }
          } label: {
            Label("Connection Actions", systemImage: "ellipsis.circle")
          }

          Picker("View", selection: $browserLayout) {
            Label("Grid", systemImage: "square.grid.2x2").tag(BrowserLayout.grid)
            Label("List", systemImage: "list.bullet").tag(BrowserLayout.list)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 100)
          .help("Change object view")
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .sheet(isPresented: $showsEditor) {
      ConnectionEditor(model: model, existing: editingProfile)
    }
    .sheet(isPresented: $showsOpenLocation) {
      OpenLocationSheet(model: model)
    }
    .confirmationDialog(
      "Delete this connection?",
      isPresented: $showsDeleteConfirmation
    ) {
      Button("Delete Connection", role: .destructive) {
        Task { try? await model.deleteSelectedProfile() }
      }
    } message: {
      Text("The profile and its Keychain credentials will be removed from this Mac.")
    }
    .onChange(of: sidebarSelection) { _, id in
      if model.selectedProfileID != id { model.selectProfile(id) }
    }
    .onChange(of: model.selectedProfileID) { _, id in
      sidebarSelection = id
    }
    .task { await model.loadProfiles() }
  }

  private func edit(_ profile: ConnectionProfile) {
    editingProfile = profile
    showsEditor = true
  }
}

private struct OpenLocationSheet: View {
  @Environment(\.dismiss) private var dismiss
  let model: AppModel

  @State private var text = "s3://"
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Open S3 Location")
        .font(.title2.weight(.semibold))
      TextField("s3://bucket/prefix/", text: $text)
        .font(.system(.body, design: .monospaced))
      if let errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Open") {
          do {
            model.open(try S3Location(text))
            dismiss()
          } catch {
            errorMessage = "Enter a location such as s3://bucket/photos/."
          }
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 460)
  }
}
