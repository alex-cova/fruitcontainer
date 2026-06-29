import SwiftUI

struct VolumesWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var volumes: [VolumeListItem] = []
    @State private var selection = Set<String>()
    @State private var searchText = ""
    @State private var inspect: VolumeInspectSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreateSheet = false
    @State private var deleteRequest: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            ResourceHeader(title: "Volumes", subtitle: "\(filteredVolumes.count) volumes", searchText: $searchText)
            Divider()
            if isLoading && volumes.isEmpty {
                ProgressView("Loading volumes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredVolumes.isEmpty {
                ContentUnavailableView("No Volumes", systemImage: "internaldrive", description: Text("Create a volume for persistent container data."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    volumeTable.frame(minWidth: 560)
                    volumeInspector.frame(minWidth: 340, idealWidth: 420)
                }
            }
            if let errorMessage {
                FeedbackBar(message: errorMessage, isError: true)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingCreateSheet = true } label: { Label("Create", systemImage: "plus") }
                ControlGroup {
                    Button(role: .destructive) { deleteRequest = Array(selection) } label: { Label("Delete", systemImage: "trash") }
                        .disabled(selection.isEmpty)
                    Button { enqueueVolumeAction(title: "Prune unused volumes", command: "container volume prune") { try await containerCLIAdapter.pruneVolumes() } } label: { Label("Prune", systemImage: "scissors") }
                        .disabled(volumes.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateVolumeSheet { request in
                enqueueVolumeAction(title: "Create volume \(request.name)", command: request.commandDescription) {
                    try await containerCLIAdapter.createVolume(
                        name: request.name,
                        size: request.size,
                        labels: request.labels,
                        options: request.options
                    )
                }
            }
        }
        .confirmationDialog("Delete selected volumes?", isPresented: Binding(get: { !deleteRequest.isEmpty }, set: { if !$0 { deleteRequest = [] } })) {
            Button("Delete", role: .destructive) {
                let names = deleteRequest
                deleteRequest = []
                enqueueVolumeAction(title: "Delete \(names.count) volume(s)", command: "container volume delete \(names.joined(separator: " "))") {
                    try await containerCLIAdapter.deleteVolumes(names: names)
                }
            }
            Button("Cancel", role: .cancel) { deleteRequest = [] }
        }
        .task {
            if appModel.cachedVolumeItems.isEmpty {
                await reload()
            } else {
                syncVolumesFromCache()
            }
        }
        .onChange(of: selection) { _, _ in
            Task { await loadInspect() }
        }
        .onChange(of: appModel.volumesRefreshRevision) { _, _ in
            syncVolumesFromCache()
        }
    }

    private var filteredVolumes: [VolumeListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return volumes }
        return volumes.filter {
            $0.name.lowercased().contains(query)
                || ($0.driver ?? "").lowercased().contains(query)
                || ($0.source ?? "").lowercased().contains(query)
                || ($0.format ?? "").lowercased().contains(query)
        }
    }

    private var selectedVolume: VolumeListItem? {
        guard let id = selection.first, selection.count == 1 else { return nil }
        return volumes.first { $0.id == id }
    }

    private var volumeTable: some View {
        Table(filteredVolumes, selection: $selection) {
            TableColumn("Name") { volume in
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name).fontWeight(.medium)
                    Text(volume.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            TableColumn("Driver") { volume in
                Text(volume.driver ?? "-")
            }
            TableColumn("Format") { volume in
                Text(volume.format ?? "-")
            }
            TableColumn("Size") { volume in
                Text(volume.sizeInBytes.map(formatBytes) ?? "-")
            }
            TableColumn("Attached") { volume in
                Text("\(appModel.volumes.first { $0.name == volume.name }?.attachedContainerCount ?? 0)")
            }
        }
    }

    private var volumeInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let volume = selectedVolume {
                    Panel(title: "Details", systemImage: "info.circle") {
                        DetailRow("Name", volume.name)
                        DetailRow("Driver", inspect?.driver ?? volume.driver ?? "-")
                        DetailRow("Format", inspect?.format ?? volume.format ?? "-")
                        DetailRow("Source", inspect?.source ?? volume.source ?? "-")
                        DetailRow("Size", (inspect?.sizeInBytes ?? volume.sizeInBytes).map(formatBytes) ?? "-")
                        DetailRow("Created", inspect?.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? volume.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "-")
                    }
                    Panel(title: "Inspect JSON", systemImage: "curlybraces") {
                        HStack {
                            Button("Reload") { Task { await loadInspect() } }
                            Button("Copy") { copyToPasteboard(inspect?.rawJSON ?? "") }.disabled(inspect == nil)
                            Spacer()
                        }
                        Text(inspect?.rawJSON ?? "No inspect output loaded.")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ContentUnavailableView("Select a Volume", systemImage: "internaldrive", description: Text("Inspect mount source, labels, options, and raw JSON."))
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(14)
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let relationshipScan = await containerCLIAdapter.scanResourceRelationships()
            let result = try await containerCLIAdapter.listVolumes()
            switch result {
            case .parsed(let value, let diagnostics):
                volumes = value
                appModel.cachedVolumeItems = value
                appModel.updateVolumes(from: value, relationships: relationshipScan.hints)
                errorMessage = diagnostics.warnings.first
            case .raw(_, let diagnostics):
                volumes = []
                errorMessage = diagnostics.warnings.first ?? "Volume list returned output that Fruit Container could not parse."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncVolumesFromCache() {
        volumes = appModel.cachedVolumeItems
        selection = selection.filter { id in
            volumes.contains { $0.id == id }
        }
        if selection.isEmpty {
            inspect = nil
        }
    }

    private func loadInspect() async {
        inspect = nil
        guard let volume = selectedVolume else { return }
        inspect = try? await containerCLIAdapter.inspectVolume(name: volume.name)
    }

    private func enqueueVolumeAction(title: String, command: String, operation: @escaping @Sendable () async throws -> Void) {
        _ = appModel.enqueueActivity(title: title, section: .volumes, kind: .volume, commandDescription: command) { _ in
            try await operation()
            return ActivityOperationOutcome(summary: "Completed.")
        }
    }
}

// MARK: - Volume Creation Sheet

private struct VolumeCreateViewRequest {
    var name: String
    var size: String?
    var labels: [String: String]
    var options: [String: String]

    var commandDescription: String {
        var parts = ["container", "volume", "create"]
        for label in labels.sorted(by: { $0.key < $1.key }) {
            parts.append(contentsOf: ["--label", "\(label.key)=\(label.value)"])
        }
        for option in options.sorted(by: { $0.key < $1.key }) {
            parts.append(contentsOf: ["--opt", "\(option.key)=\(option.value)"])
        }
        if let size {
            parts.append(contentsOf: ["--size", size])
        }
        parts.append(name)
        return parts.joined(separator: " ")
    }
}

private struct CreateVolumeSheet: View {
    let onCreate: (VolumeCreateViewRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var size = ""
    @State private var labels = ""
    @State private var options = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Volume") {
                    TextField("Name", text: $name)
                    TextField("Size", text: $size)
                }
                Section("Metadata") {
                    TextField("Labels", text: $labels)
                    TextField("Options", text: $options)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Volume")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(
                            VolumeCreateViewRequest(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                size: size.nilIfEmpty,
                                labels: dictionaryList(labels),
                                options: dictionaryList(options)
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 460, height: 340)
    }
}

#if DEBUG
#Preview {
    VolumesWorkspaceView()
        .environmentObject(AppModel.preview)
        .frame(width: 1000, height: 640)
}
#endif
