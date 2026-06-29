import SwiftUI

struct ContainersWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var containers: [ContainerListItem] = []
    @State private var selection = Set<String>()
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingRunSheet = false
    @State private var deleteRequest: [String] = []
    @State private var logText = ""
    @State private var bootLogText = ""
    @State private var selectedInspect: ContainerInspectSnapshot?
    @State private var inspectorTab: ContainerInspectorTab = .overview
    @State private var logSearchText = ""

    var body: some View {
        VStack(spacing: 0) {
            ResourceHeader(
                title: "Containers",
                subtitle: "\(filteredContainers.count) shown, \(runningContainers.count) running, \(stoppedContainers.count) stopped",
                searchText: $searchText
            )
            
            Divider()
            if isLoading && containers.isEmpty {
                ProgressView("Loading containers...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredContainers.isEmpty {
                ContentUnavailableView("No Containers", systemImage: "truck.box", description: Text("Run an image to create a lightweight Linux VM-backed container."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    containerCatalog
                        .frame(minWidth: 520)
                    inspector
                        .frame(minWidth: 340, idealWidth: 420)
                }
            }
            if let errorMessage {
                FeedbackBar(message: errorMessage, isError: true)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingRunSheet = true } label: { Label("Run", systemImage: "play.circle") }

                ControlGroup {
                    Button { runLifecycle(.start) } label: { Label("Start", systemImage: "play.fill") }
                        .disabled(selection.isEmpty)
                    Button { runLifecycle(.stop) } label: { Label("Stop", systemImage: "stop.fill") }
                        .disabled(selection.isEmpty)
                }

                Button(role: .destructive) { deleteRequest = Array(selection) } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selection.isEmpty)
            }
        }
        .sheet(isPresented: $showingRunSheet) {
            RunContainerSheet(images: appModel.images.map(\.reference)) { request in
                enqueueRun(request)
            }
        }
        .confirmationDialog("Delete selected containers?", isPresented: Binding(get: { !deleteRequest.isEmpty }, set: { if !$0 { deleteRequest = [] } })) {
            Button("Delete", role: .destructive) {
                let ids = deleteRequest
                deleteRequest = []
                enqueueContainerAction(
                    title: "Delete \(ids.count) container(s)",
                    command: "container delete \(ids.joined(separator: " "))"
                ) {
                    try await containerCLIAdapter.deleteContainers(ids: ids)
                }
            }
            Button("Cancel", role: .cancel) { deleteRequest = [] }
        }
        .task {
            if appModel.cachedContainerItems.isEmpty {
                await reload()
            } else {
                syncContainersFromCache()
            }
        }
        .onChange(of: selection) { _, _ in
            Task { await loadDetailsForSelection() }
        }
        .onChange(of: appModel.containersRefreshRevision) { _, _ in
            syncContainersFromCache()
        }
    }

    private var filteredContainers: [ContainerListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return containers }
        return containers.filter { $0.matchesSearchText.contains(query) }
    }

    private var runningContainers: [ContainerListItem] {
        containers.filter(\.isRunning)
    }

    private var stoppedContainers: [ContainerListItem] {
        containers.filter { !$0.isRunning }
    }

    private var publishedPortCount: Int {
        containers.reduce(0) { $0 + $1.publishedPorts.count }
    }

    private var containerCatalog: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredContainers) { item in
                    ContainerCatalogRow(
                        item: item,
                        isSelected: selection.contains(item.id)
                    ) {
                        selection = [item.id]
                    }
                }
            }
            .padding(14)
        }
        .background(FruitTheme.pageBackground)
    }

    private var inspector: some View {
        Group {
            if let selectedContainer, let id = selection.first, selection.count == 1 {
                VStack(spacing: 0) {
                    inspectorHeader(for: selectedContainer)

                    Picker("Inspector Section", selection: $inspectorTab) {
                        ForEach(ContainerInspectorTab.allCases) { tab in
                            Label(tab.title, systemImage: tab.systemImage)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                    Divider()

                    Group {
                        switch inspectorTab {
                        case .overview:
                            overviewInspector(for: selectedContainer)
                        case .logs:
                            logsInspector(containerID: id)
                        case .json:
                            jsonInspector
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .background(FruitTheme.pageBackground)
            } else {
                ContentUnavailableView("Select a Container", systemImage: "sidebar.right", description: Text("Inspect configuration and recent logs for one container."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func inspectorHeader(for container: ContainerListItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(container.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                StatusBadge(text: container.stateDisplay, color: container.isRunning ? .green : .secondary)
                Spacer(minLength: 0)
            }

            Text(container.imageDisplayName)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            FlowLayout(spacing: 8, lineSpacing: 8) {
                ImageMetadataPill(text: selectedInspect?.platform ?? container.platformDisplayName, systemImage: "cpu", tint: .indigo)
                ImageMetadataPill(text: selectedInspect?.resourceSummary ?? container.resourceSummary, systemImage: "gauge", tint: .blue)
                ImageMetadataPill(text: selectedInspect?.portsDisplay ?? container.portsDisplay, systemImage: "network", tint: container.publishedPorts.isEmpty ? .secondary : .teal)
            }
        }
        .padding(14)
    }

    private func overviewInspector(for container: ContainerListItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Panel(title: "Identity", systemImage: "info.circle") {
                    DetailRow("ID", container.id)
                    DetailRow("State", selectedInspect?.state?.capitalized ?? container.stateDisplay)
                    DetailRow("Hostname", selectedInspect?.hostname ?? container.hostname ?? container.name)
                    DetailRow("Image", selectedInspect?.imageReference ?? container.image ?? "Unknown")
                    DetailRow("Created", container.created ?? "-")
                    DetailRow("Platform", selectedInspect?.platform ?? container.platformDisplayName)
                }

                Panel(title: "Runtime", systemImage: "gauge") {
                    DetailRow("Resources", selectedInspect?.resourceSummary ?? container.resourceSummary)
                    DetailRow("Command", selectedInspect?.command ?? container.command ?? "-")
                    DetailRow("Runtime", selectedInspect?.runtimeHandler ?? "-")
                    DetailRow("Rosetta", (selectedInspect?.rosetta ?? container.rosetta) == true ? "Enabled" : "Disabled")
                    DetailRow("Read-only", (selectedInspect?.readOnly ?? container.readOnly) == true ? "Enabled" : "Disabled")
                }

                Panel(title: "Network", systemImage: "network") {
                    DetailRow("Address", selectedInspect?.networkAddress ?? "-")
                    DetailRow("Networks", selectedInspect?.configuredNetworkNames.joined(separator: ", ") ?? "-")
                    DetailRow("Ports", selectedInspect?.portsDisplay ?? container.portsDisplay)
                }

                if let selectedInspect, !selectedInspect.environment.isEmpty {
                    Panel(title: "Environment", systemImage: "list.bullet.rectangle") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(selectedInspect.environment, id: \.self) { value in
                                Text(value)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func logsInspector(containerID: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search logs", text: $logSearchText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        await loadLogs(id: containerID)
                        await loadBootLogs(id: containerID)
                    }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LogOutputPanel(
                        title: "Application Logs",
                        systemImage: "doc.text",
                        text: filteredLogText(logText),
                        originalText: logText,
                        matchCount: matchingLineCount(in: logText),
                        searchIsActive: logSearchText.nilIfEmpty != nil,
                        emptyText: "No logs loaded.",
                        onReload: { Task { await loadLogs(id: containerID) } }
                    )

                    LogOutputPanel(
                        title: "Boot Logs",
                        systemImage: "terminal",
                        text: filteredLogText(bootLogText),
                        originalText: bootLogText,
                        matchCount: matchingLineCount(in: bootLogText),
                        searchIsActive: logSearchText.nilIfEmpty != nil,
                        emptyText: "No boot logs loaded.",
                        onReload: { Task { await loadBootLogs(id: containerID) } }
                    )
                }
                .padding(14)
            }
        }
    }

    private var jsonInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedInspect {
                    Panel(title: "Inspect JSON", systemImage: "curlybraces") {
                        HStack {
                            Button {
                                copyToPasteboard(selectedInspect.rawJSON)
                            } label: {
                                Label("Copy JSON", systemImage: "doc.on.doc")
                            }
                            Spacer()
                        }

                        Text(selectedInspect.rawJSON)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ContentUnavailableView("Inspect Data Loading", systemImage: "curlybraces", description: Text("Select a container and wait for inspect output to finish loading."))
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(14)
        }
    }

    private var selectedContainer: ContainerListItem? {
        guard let id = selection.first, selection.count == 1 else { return nil }
        return containers.first { $0.id == id }
    }

    private func filteredLogText(_ text: String) -> String {
        guard let query = logSearchText.nilIfEmpty else { return text }
        let lines = text.components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(query) }
        return lines.joined(separator: "\n")
    }

    private func matchingLineCount(in text: String) -> Int {
        guard let query = logSearchText.nilIfEmpty else { return text.isEmpty ? 0 : text.components(separatedBy: .newlines).count }
        return text.components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .count
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await containerCLIAdapter.listContainers()
            switch result {
            case .parsed(let value, let diagnostics):
                containers = value
                appModel.cachedContainerItems = value
                appModel.updateContainers(from: value)
                errorMessage = diagnostics.warnings.first
            case .raw(_, let diagnostics):
                containers = []
                errorMessage = diagnostics.warnings.first ?? "Container list returned output that Fruit Container could not parse."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncContainersFromCache() {
        containers = appModel.cachedContainerItems
        selection = selection.filter { id in
            containers.contains { $0.id == id }
        }
        if selection.isEmpty {
            selectedInspect = nil
            logText = ""
            bootLogText = ""
        }
    }

    private func loadDetailsForSelection() async {
        selectedInspect = nil
        logText = ""
        bootLogText = ""
        guard let id = selection.first, selection.count == 1 else { return }
        async let inspect = try? containerCLIAdapter.inspectContainer(id: id)
        async let logs = try? containerCLIAdapter.fetchContainerLogs(id: id, tail: 120)
        async let bootLogs = try? containerCLIAdapter.fetchContainerLogs(id: id, tail: 120, boot: true)
        selectedInspect = await inspect
        logText = await logs ?? ""
        bootLogText = await bootLogs ?? ""
    }

    private func loadLogs(id: String) async {
        logText = (try? await containerCLIAdapter.fetchContainerLogs(id: id, tail: 200)) ?? ""
    }

    private func loadBootLogs(id: String) async {
        bootLogText = (try? await containerCLIAdapter.fetchContainerLogs(id: id, tail: 200, boot: true)) ?? ""
    }

    private func runLifecycle(_ action: ContainerLifecycleAction) {
        let ids = Array(selection)
        enqueueContainerAction(title: "\(action.title) \(ids.count) container(s)", command: "container \(action.command) \(ids.joined(separator: " "))") {
            switch action {
            case .start: try await containerCLIAdapter.startContainers(ids: ids)
            case .stop: try await containerCLIAdapter.stopContainers(ids: ids)
            }
        }
    }

    private func enqueueRun(_ request: ContainerCreateRequest) {
        _ = appModel.enqueueActivity(
            title: "Run \(request.imageReference)",
            section: .containers,
            kind: .container,
            commandDescription: "container run --detach \(request.imageReference)"
        ) { _ in
            let id = try await containerCLIAdapter.runContainer(request: request)
            return ActivityOperationOutcome(summary: "Started container \(id).")
        }
    }

    private func enqueueContainerAction(title: String, command: String, operation: @escaping @Sendable () async throws -> Void) {
        _ = appModel.enqueueActivity(title: title, section: .containers, kind: .container, commandDescription: command) { _ in
            try await operation()
            return ActivityOperationOutcome(summary: "Completed.")
        }
    }
}

// MARK: - Container-specific subviews

private enum ContainerInspectorTab: String, CaseIterable, Identifiable {
    case overview
    case logs
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .logs: "Logs"
        case .json: "JSON"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "info.circle"
        case .logs: "doc.text"
        case .json: "curlybraces"
        }
    }
}

private struct LogOutputPanel: View {
    let title: String
    let systemImage: String
    let text: String
    let originalText: String
    let matchCount: Int
    let searchIsActive: Bool
    let emptyText: String
    let onReload: () -> Void

    var body: some View {
        Panel(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(action: onReload) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)

                    Button {
                        copyToPasteboard(text)
                    } label: {
                        Label(searchIsActive ? "Copy Results" : "Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .disabled(text.isEmpty)
                }

                Text(displayText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var statusText: String {
        if originalText.isEmpty {
            return "No output"
        }
        if searchIsActive {
            return "\(matchCount) matching line\(matchCount == 1 ? "" : "s")"
        }
        return "\(matchCount) line\(matchCount == 1 ? "" : "s")"
    }

    private var displayText: String {
        if text.isEmpty {
            return searchIsActive && !originalText.isEmpty ? "No matching log lines." : emptyText
        }
        return text
    }
}

private struct ContainerStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(FruitTheme.cardFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ContainerCatalogRow: View {
    let item: ContainerListItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.isRunning ? "play.circle.fill" : "stop.circle")
                        .font(.title3)
                        .foregroundStyle(item.isRunning ? .green : .secondary)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.headline)
                                .lineLimit(1)
                            if let role = item.role, !role.isEmpty {
                                Text(role.capitalized)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(FruitTheme.cardFill, in: Capsule())
                            }
                        }

                        Text(item.imageDisplayName)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)
                    StatusBadge(text: item.stateDisplay, color: item.isRunning ? .green : .secondary)
                }

                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ImageMetadataPill(text: item.resourceSummary, systemImage: "gauge", tint: .blue)
                    ImageMetadataPill(text: item.platformDisplayName, systemImage: "cpu", tint: .indigo)
                    ImageMetadataPill(text: item.portsDisplay, systemImage: "network", tint: item.publishedPorts.isEmpty ? .secondary : .teal)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.stateDisplay), \(item.imageDisplayName)")
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.12) : FruitTheme.controlBackground
    }
}

private enum ContainerLifecycleAction {
    case start
    case stop

    var title: String { self == .start ? "Start" : "Stop" }
    var command: String { self == .start ? "start" : "stop" }
}

// MARK: - Run Container Sheet

struct RunContainerSheet: View {
    let images: [String]
    let onRun: (ContainerCreateRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var imageReference = ""
    @State private var name = ""
    @State private var command = ""
    @State private var cpu = ""
    @State private var memory = ""
    @State private var platform = ""
    @State private var ports = ""
    @State private var environment = ""
    @State private var removeWhenStopped = false
    @State private var useRosetta = false
    @State private var readOnlyRoot = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        imageSection
                        containerSection
                        runtimeSection
                        networkingSection
                    }
                    .padding(18)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    CommandPreview(command: commandPreview)

                    HStack {
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)

                        Spacer()

                        Button {
                            onRun(makeRequest())
                            dismiss()
                        } label: {
                            Label("Run Container", systemImage: "play.fill")
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canRun)
                    }
                }
                .padding(18)
                .background(FruitTheme.chromeFill)
            }
            .navigationTitle("Run Container")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .help("Close")
                }
            }
        }
        .frame(width: 760, height: 680)
    }

    private var imageSection: some View {
        RunSheetSection(title: "Image", systemImage: "photo.stack") {
            VStack(alignment: .leading, spacing: 12) {
                if !images.isEmpty {
                    Picker("Local image", selection: $imageReference) {
                        Text("Custom or remote image").tag("")
                        ForEach(images, id: \.self) { image in
                            Text(image).tag(image)
                        }
                    }
                    .pickerStyle(.menu)
                }

                TextField("Image reference", text: $imageReference)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                if let selectedLocalImage {
                    HStack(spacing: 8) {
                        ImageMetadataPill(text: selectedLocalImage.registryDisplay, systemImage: "externaldrive", tint: .indigo)
                        ImageMetadataPill(text: selectedLocalImage.tagDisplay, systemImage: "tag", tint: .blue)
                    }
                }
            }
        }
    }

    private var containerSection: some View {
        RunSheetSection(title: "Container", systemImage: "truck.box") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    RunTextField(title: "Name", text: $name, placeholder: "Optional")
                    RunTextField(title: "Arguments", text: $command, placeholder: "Optional", isMonospaced: true)
                }

                HStack(spacing: 10) {
                    RunTogglePill(title: "Remove", systemImage: "trash", isOn: $removeWhenStopped)
                    RunTogglePill(title: "Read-only", systemImage: "lock", isOn: $readOnlyRoot)
                }
            }
        }
    }

    private var runtimeSection: some View {
        RunSheetSection(title: "Resources", systemImage: "gauge") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    RunTextField(title: "CPUs", text: $cpu, placeholder: "Default")
                        .frame(maxWidth: 130)
                    RunTextField(title: "Memory", text: $memory, placeholder: "1g")
                        .frame(maxWidth: 160)
                    RunTextField(title: "Platform", text: $platform, placeholder: "linux/arm64", isMonospaced: true)
                }

                HStack(spacing: 10) {
                    ForEach(["linux/arm64", "linux/amd64"], id: \.self) { value in
                        Button {
                            platform = value
                        } label: {
                            Label(value, systemImage: value.contains("arm64") ? "cpu" : "desktopcomputer")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    RunTogglePill(title: "Rosetta", systemImage: "cpu", isOn: $useRosetta)
                }
            }
        }
    }

    private var networkingSection: some View {
        RunSheetSection(title: "Network & Environment", systemImage: "network") {
            VStack(alignment: .leading, spacing: 12) {
                RunTextField(title: "Ports", text: $ports, placeholder: "8080:80, 8443:443", isMonospaced: true)
                RunTextField(title: "Environment", text: $environment, placeholder: "KEY=value, MODE=dev", isMonospaced: true)
            }
        }
    }

    private var selectedLocalImage: LocalImageReference? {
        guard images.contains(imageReference) else { return nil }
        return LocalImageReference(reference: imageReference)
    }

    private var canRun: Bool {
        imageReference.nilIfEmpty != nil && validationMessage == nil
    }

    private var validationMessage: String? {
        if imageReference.nilIfEmpty == nil {
            return "Image reference is required."
        }
        if let cpu = cpu.nilIfEmpty, Int(cpu) == nil {
            return "CPUs must be a whole number."
        }
        return nil
    }

    private var commandPreview: String {
        var parts = ["container", "run", "--detach"]
        if let name = name.nilIfEmpty { parts += ["--name", name] }
        if let cpu = cpu.nilIfEmpty { parts += ["--cpus", cpu] }
        if let memory = memory.nilIfEmpty { parts += ["--memory", memory] }
        if let platform = platform.nilIfEmpty { parts += ["--platform", platform] }
        if removeWhenStopped { parts.append("--rm") }
        if readOnlyRoot { parts.append("--read-only") }
        if useRosetta { parts.append("--rosetta") }
        for port in commaList(ports) { parts += ["--publish", port] }
        for env in commaList(environment) { parts += ["--env", env] }
        parts.append(imageReference.nilIfEmpty ?? "<image>")
        parts += shellWords(command)
        return parts.joined(separator: " ")
    }

    private func makeRequest() -> ContainerCreateRequest {
        ContainerCreateRequest(
            imageReference: imageReference,
            name: name.nilIfEmpty,
            commandArguments: shellWords(command),
            environment: dictionaryList(environment),
            publishedPorts: commaList(ports),
            volumeMounts: [],
            network: nil,
            workingDirectory: nil,
            cpuCount: Int(cpu.trimmingCharacters(in: .whitespacesAndNewlines)),
            memory: memory.nilIfEmpty,
            readOnlyRootFilesystem: readOnlyRoot,
            removeWhenStopped: removeWhenStopped,
            platform: platform.nilIfEmpty,
            useRosetta: useRosetta
        )
    }
}

private struct RunSheetSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FruitTheme.cardFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RunTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var isMonospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(isMonospaced ? Font.system(.body, design: .monospaced) : Font.body)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct RunTogglePill: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .controlSize(.small)
    }
}

private struct LocalImageReference {
    let reference: String

    var registryDisplay: String {
        let slashParts = reference.split(separator: "/", omittingEmptySubsequences: false)
        return slashParts.count > 1 ? String(slashParts[0]) : "docker.io"
    }

    var tagDisplay: String {
        let slashIndex = reference.lastIndex(of: "/")
        let searchStart = slashIndex.map { reference.index(after: $0) } ?? reference.startIndex
        guard let colonIndex = reference[searchStart...].lastIndex(of: ":") else {
            return "latest"
        }
        return String(reference[reference.index(after: colonIndex)...])
    }
}

#if DEBUG
#Preview {
    ContainersWorkspaceView()
        .environmentObject(AppModel.preview)
        .frame(width: 1000, height: 680)
}
#endif
