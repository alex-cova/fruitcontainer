import SwiftUI

struct NetworksWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var networks: [NetworkListItem] = []
    @State private var selection = Set<String>()
    @State private var searchText = ""
    @State private var inspect: NetworkInspectSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreateSheet = false
    @State private var deleteRequest: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            ResourceHeader(title: "Networks", subtitle: "\(filteredNetworks.count) networks", searchText: $searchText)
            Divider()
            if isLoading && networks.isEmpty {
                ProgressView("Loading networks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredNetworks.isEmpty {
                ActionableEmptyState(
                    title: searchText.isEmpty ? "No Networks" : "No Matching Networks",
                    systemImage: searchText.isEmpty ? "network" : "magnifyingglass",
                    message: searchText.isEmpty ? "Create a custom network or start the service to view built-in networks." : "No networks match \"\(searchText)\".",
                    actionTitle: searchText.isEmpty ? "Create Network" : "Clear Search",
                    actionSystemImage: searchText.isEmpty ? "plus" : "xmark.circle",
                    action: searchText.isEmpty ? { showingCreateSheet = true } : { searchText = "" }
                )
            } else {
                HSplitView {
                    networkTable.frame(minWidth: 560)
                    networkInspector.frame(minWidth: 340, idealWidth: 420)
                }
            }
            if let errorMessage {
                FeedbackBar(message: errorMessage, isError: true)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingCreateSheet = true } label: { Label("Create", systemImage: "plus") }

                Button(role: .destructive) {
                    deleteRequest = Array(selection)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!canDeleteSelectedNetworks)
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateNetworkSheet { request in
                enqueueNetworkAction(
                    title: "Create network \(request.name)",
                    command: request.commandDescription
                ) {
                    try await containerCLIAdapter.createNetwork(
                        name: request.name,
                        ipv4Subnet: request.ipv4Subnet,
                        ipv6Subnet: request.ipv6Subnet,
                        labels: request.labels,
                        isInternal: request.isInternal
                    )
                }
            }
        }
        .confirmationDialog("Delete selected networks?", isPresented: Binding(get: { !deleteRequest.isEmpty }, set: { if !$0 { deleteRequest = [] } })) {
            Button("Delete", role: .destructive) {
                let names = deleteRequest
                deleteRequest = []
                enqueueNetworkAction(title: "Delete \(names.count) network(s)", command: "container network delete \(names.joined(separator: " "))") {
                    try await containerCLIAdapter.deleteNetworks(names: names)
                }
            }
            Button("Cancel", role: .cancel) { deleteRequest = [] }
        }
        .task {
            if appModel.cachedNetworkItems.isEmpty {
                await reload()
            } else {
                syncNetworksFromCache()
            }
        }
        .onChange(of: selection) { _, _ in
            Task { await loadInspect() }
        }
        .onChange(of: appModel.networksRefreshRevision) { _, _ in
            syncNetworksFromCache()
        }
    }

    private var filteredNetworks: [NetworkListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return networks }
        return networks.filter {
            $0.name.lowercased().contains(query)
                || ($0.mode ?? "").lowercased().contains(query)
                || ($0.plugin ?? "").lowercased().contains(query)
                || ($0.ipv4Subnet ?? "").lowercased().contains(query)
        }
    }

    private var selectedNetworks: [NetworkListItem] {
        networks.filter { selection.contains($0.id) }
    }

    private var canDeleteSelectedNetworks: Bool {
        !selection.isEmpty && !selectedNetworks.contains(where: \.isBuiltin)
    }

    private var selectedNetwork: NetworkListItem? {
        guard let id = selection.first, selection.count == 1 else { return nil }
        return networks.first { $0.id == id }
    }

    private var networkTable: some View {
        Table(filteredNetworks, selection: $selection) {
            TableColumn("Name") { network in
                VStack(alignment: .leading, spacing: 2) {
                    Text(network.name).fontWeight(.medium)
                    Text(network.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Network \(network.name), ID \(network.id)")
            }
            .width(min: 180, ideal: 230)
            TableColumn("Mode") { network in
                Text(network.mode ?? "-")
            }
            .width(min: 72, ideal: 96, max: 120)
            TableColumn("Subnet") { network in
                Text(network.ipv4Subnet ?? network.ipv6Subnet ?? "-").lineLimit(1)
            }
            .width(min: 150, ideal: 190)
            TableColumn("Attached") { network in
                Text("\(appModel.networks.first { $0.name == network.name }?.attachedContainerCount ?? 0)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 72, ideal: 86, max: 100)
            TableColumn("Role") { network in
                StatusBadge(text: network.isBuiltin ? "Built-in" : "Custom", color: network.isBuiltin ? .secondary : .blue)
            }
            .width(min: 96, ideal: 110, max: 130)
        }
    }

    private var networkInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let network = selectedNetwork {
                    Panel(title: "Details", systemImage: "info.circle") {
                        DetailRow("Name", network.name)
                        DetailRow("ID", network.id)
                        DetailRow("State", inspect?.state ?? network.state ?? "-")
                        DetailRow("Mode", inspect?.mode ?? network.mode ?? "-")
                        DetailRow("Role", network.isBuiltin ? "Built-in" : "Custom")
                    }
                    Panel(title: "Configuration", systemImage: "slider.horizontal.3") {
                        DetailRow("IPv4 Subnet", inspect?.ipv4Subnet ?? network.ipv4Subnet ?? "-")
                        DetailRow("IPv6 Subnet", inspect?.ipv6Subnet ?? network.ipv6Subnet ?? "-")
                        DetailRow("Gateway", inspect?.ipv4Gateway ?? "-")
                        DetailRow("Plugin", inspect?.plugin ?? network.plugin ?? "-")
                        DetailRow("Variant", inspect?.pluginVariant ?? network.pluginVariant ?? "-")
                    }
                    Panel(title: "Labels", systemImage: "tag") {
                        KeyValueList(values: inspect?.labels ?? network.labels)
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
                        title: "Select a Network",
                        systemImage: "network",
                        message: "Inspect subnets, plugin metadata, labels, and raw JSON."
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
            let result = try await containerCLIAdapter.listNetworks()
            switch result {
            case .parsed(let value, let diagnostics):
                networks = value
                appModel.cachedNetworkItems = value
                appModel.updateNetworks(from: value, relationships: relationshipScan.hints)
                errorMessage = diagnostics.warnings.first
            case .raw(_, let diagnostics):
                networks = []
                errorMessage = diagnostics.warnings.first ?? "Network list returned output that Fruit Container could not parse."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncNetworksFromCache() {
        networks = appModel.cachedNetworkItems
        selection = selection.filter { id in
            networks.contains { $0.id == id }
        }
        if selection.isEmpty {
            inspect = nil
        }
    }

    private func loadInspect() async {
        inspect = nil
        guard let network = selectedNetwork else { return }
        inspect = try? await containerCLIAdapter.inspectNetwork(name: network.name)
    }

    private func enqueueNetworkAction(title: String, command: String, operation: @escaping @Sendable () async throws -> Void) {
        _ = appModel.enqueueActivity(title: title, section: .networks, kind: .network, commandDescription: command) { _ in
            try await operation()
            return ActivityOperationOutcome(summary: "Completed.")
        }
    }
}

// MARK: - Network Creation Sheet

private struct NetworkCreateViewRequest {
    var name: String
    var ipv4Subnet: String?
    var ipv6Subnet: String?
    var labels: [String: String]
    var isInternal: Bool

    var commandDescription: String {
        var parts = ["container", "network", "create"]
        for label in labels.sorted(by: { $0.key < $1.key }) {
            parts.append(contentsOf: ["--label", "\(label.key)=\(label.value)"])
        }
        if isInternal {
            parts.append("--internal")
        }
        if let ipv4Subnet {
            parts.append(contentsOf: ["--subnet", ipv4Subnet])
        }
        if let ipv6Subnet {
            parts.append(contentsOf: ["--subnet-v6", ipv6Subnet])
        }
        parts.append(name)
        return parts.joined(separator: " ")
    }
}

private struct CreateNetworkSheet: View {
    let onCreate: (NetworkCreateViewRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var ipv4Subnet = ""
    @State private var ipv6Subnet = ""
    @State private var labels = ""
    @State private var isInternal = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Panel(title: "Network", systemImage: "network") {
                            FormField(title: "Name", text: $name, placeholder: "frontend", helper: "Required unique network name.")
                            FormField(title: "IPv4 Subnet", text: $ipv4Subnet, placeholder: "10.42.0.0/24", helper: "Optional CIDR subnet.", isMonospaced: true)
                            FormField(title: "IPv6 Subnet", text: $ipv6Subnet, placeholder: "fd00:42::/64", helper: "Optional IPv6 CIDR subnet.", isMonospaced: true)
                            Toggle("Internal network", isOn: $isInternal)
                        }
                        Panel(title: "Labels", systemImage: "tag") {
                            FormField(title: "Labels", text: $labels, placeholder: "key=value,key2=value2", helper: "Comma-separated metadata pairs.", isMonospaced: true)
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
                            Label("Create Network", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canCreate)
                    }
                }
                .padding(18)
                .background(FruitTheme.chromeFill)
            }
            .navigationTitle("Create Network")
        }
        .frame(width: 560, height: 520)
    }

    private var canCreate: Bool {
        name.nilIfEmpty != nil
    }

    private var request: NetworkCreateViewRequest {
        NetworkCreateViewRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            ipv4Subnet: ipv4Subnet.nilIfEmpty,
            ipv6Subnet: ipv6Subnet.nilIfEmpty,
            labels: dictionaryList(labels),
            isInternal: isInternal
        )
    }

    private var commandPreview: String {
        canCreate ? request.commandDescription : "container network create <name>"
    }
}

#if DEBUG
#Preview {
    NetworksWorkspaceView()
        .environmentObject(AppModel.preview)
        .frame(width: 1000, height: 640)
}
#endif
