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
                ActionableEmptyState(
                    title: searchText.isEmpty ? "No Volumes" : "No Matching Volumes",
                    systemImage: searchText.isEmpty ? "internaldrive" : "magnifyingglass",
                    message: searchText.isEmpty ? "Create a volume for persistent container data." : "No volumes match \"\(searchText)\".",
                    actionTitle: searchText.isEmpty ? "Create Volume" : "Clear Search",
                    actionSystemImage: searchText.isEmpty ? "plus" : "xmark.circle",
                    action: searchText.isEmpty ? { showingCreateSheet = true } : { searchText = "" }
                )
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
                    Text(volume.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Volume \(volume.name), ID \(volume.id)")
            }
            .width(min: 180, ideal: 230)
            TableColumn("Driver") { volume in
                Text(volume.driver ?? "-")
            }
            .width(min: 86, ideal: 110, max: 140)
            TableColumn("Format") { volume in
                Text(volume.format ?? "-")
            }
            .width(min: 86, ideal: 110, max: 140)
            TableColumn("Size") { volume in
                Text(volume.sizeInBytes.map(formatBytes) ?? "-")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 90, ideal: 110, max: 140)
            TableColumn("Attached") { volume in
                Text("\(appModel.volumes.first { $0.name == volume.name }?.attachedContainerCount ?? 0)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 72, ideal: 86, max: 100)
        }
    }

    private var volumeInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let volume = selectedVolume {
                    Panel(title: "Details", systemImage: "info.circle") {
                        DetailRow("Name", volume.name)
                        DetailRow("ID", volume.id)
                        DetailRow("Driver", inspect?.driver ?? volume.driver ?? "-")
                        DetailRow("Format", inspect?.format ?? volume.format ?? "-")
                    }
                    Panel(title: "Storage", systemImage: "internaldrive") {
                        DetailRow("Source", inspect?.source ?? volume.source ?? "-")
                        DetailRow("Size", (inspect?.sizeInBytes ?? volume.sizeInBytes).map(formatBytes) ?? "-")
                        DetailRow("Created", inspect?.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? volume.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "-")
                    }
                    Panel(title: "Labels", systemImage: "tag") {
                        KeyValueList(values: inspect?.labels ?? volume.labels)
                    }
                    Panel(title: "Options", systemImage: "slider.horizontal.3") {
                        KeyValueList(values: inspect?.options ?? volume.options)
                    }
                    Panel(title: "Inspect JSON", systemImage: "curlybraces") {
                        HStack {
                            Button { Task { await loadInspect() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                            Button { copyToPasteboard(inspect?.rawJSON ?? "") } label: { Label("Copy JSON", systemImage: "doc.on.doc") }
                                .disabled(inspect == nil)
                            Spacer()
                        }
                        CodeBlock(text: inspect?.rawJSON ?? "", emptyText: "No inspect output loaded.")
                    }
                } else {
                    ActionableEmptyState(
                        title: "Select a Volume",
                        systemImage: "internaldrive",
                        message: "Inspect mount source, labels, options, and raw JSON."
                    )
                    .frame(minHeight: 240)
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
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Panel(title: "Volume", systemImage: "internaldrive") {
                            FormField(title: "Name", text: $name, placeholder: "app-data", helper: "Required unique volume name.")
                            FormField(title: "Size", text: $size, placeholder: "10g", helper: "Optional storage limit, for drivers that support it.", isMonospaced: true)
                        }
                        Panel(title: "Metadata", systemImage: "tag") {
                            FormField(title: "Labels", text: $labels, placeholder: "key=value,key2=value2", helper: "Comma-separated metadata pairs.", isMonospaced: true)
                            FormField(title: "Options", text: $options, placeholder: "type=tmpfs,o=size=1g", helper: "Comma-separated driver option pairs.", isMonospaced: true)
                        }
                    }
                    .padding(18)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    CommandPreview(command: commandPreview)
                    HStack {
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button {
                            onCreate(request)
                            dismiss()
                        } label: {
                            Label("Create Volume", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canCreate)
                    }
                }
                .padding(18)
                .background(FruitTheme.chromeFill)
            }
            .navigationTitle("Create Volume")
        }
        .frame(width: 560, height: 520)
    }

    private var canCreate: Bool {
        name.nilIfEmpty != nil
    }

    private var request: VolumeCreateViewRequest {
        VolumeCreateViewRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            size: size.nilIfEmpty,
            labels: dictionaryList(labels),
            options: dictionaryList(options)
        )
    }

    private var commandPreview: String {
        canCreate ? request.commandDescription : "container volume create <name>"
    }
}

#if DEBUG
#Preview {
    VolumesWorkspaceView()
        .environmentObject(AppModel.preview)
        .frame(width: 1000, height: 640)
}
#endif
