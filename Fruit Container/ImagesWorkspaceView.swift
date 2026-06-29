import SwiftUI

struct ImagesWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var images: [ImageListItem] = []
    @State private var selection = Set<String>()
    @State private var searchText = ""
    @State private var pullReference = ""
    @State private var tagTarget = ""
    @State private var pushReference = ""
    @State private var inspect: ImageInspectSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingWorkflow = false
    @State private var deleteRequest: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            ResourceHeader(title: "Images", subtitle: "\(filteredImages.count) local images", searchText: $searchText)
            
            Divider()
            if isLoading && images.isEmpty {
                ProgressView("Loading images...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredImages.isEmpty {
                ContentUnavailableView("No Images", systemImage: "photo.stack", description: Text("Pull an OCI-compatible image from a registry to get started."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    imageCatalog.frame(minWidth: 560)
                    imageInspector.frame(minWidth: 360, idealWidth: 440)
                }
            }
            if let errorMessage {
                FeedbackBar(message: errorMessage, isError: true)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingWorkflow = true } label: { Label("Workflow", systemImage: "plus") }
                ControlGroup {
                    Button(role: .destructive) {
                        deleteRequest = Array(selection)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selection.isEmpty)

                    Button {
                        enqueueImageAction(title: "Prune unused images", command: "container image prune --all") { _ in
                            try await containerCLIAdapter.pruneImages(removeAllUnused: true)
                        }
                    } label: {
                        Label("Prune", systemImage: "sparkles")
                    }
                    .disabled(images.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingWorkflow) {
            ImageWorkflowSheet(
                localImages: images.map(\.reference),
                pullReference: $pullReference,
                tagTarget: $tagTarget,
                pushReference: $pushReference,
                selectedReference: selection.first,
                onPull: performPull,
                onTag: performTag,
                onPush: performPush
            )
        }
        .confirmationDialog("Delete selected images?", isPresented: Binding(get: { !deleteRequest.isEmpty }, set: { if !$0 { deleteRequest = [] } })) {
            Button("Delete", role: .destructive) {
                let references = deleteRequest
                deleteRequest = []
                enqueueImageAction(title: "Delete \(references.count) image(s)", command: "container image delete \(references.joined(separator: " "))") { _ in
                    try await containerCLIAdapter.deleteImages(references: references)
                }
            }
            Button("Cancel", role: .cancel) { deleteRequest = [] }
        }
        .task {
            if appModel.cachedImageItems.isEmpty {
                await reload()
            } else {
                syncImagesFromCache()
            }
        }
        .onChange(of: selection) { _, _ in
            Task { await loadInspect() }
        }
        .onChange(of: appModel.imagesRefreshRevision) { _, _ in
            syncImagesFromCache()
        }
    }

    private var filteredImages: [ImageListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return images }
        return images.filter {
            $0.reference.lowercased().contains(query)
                || $0.id.lowercased().contains(query)
                || ($0.size ?? "").lowercased().contains(query)
                || ($0.mediaType ?? "").lowercased().contains(query)
                || $0.platforms.joined(separator: " ").lowercased().contains(query)
        }
    }

    private var selectedImage: ImageListItem? {
        guard let reference = selection.first else { return nil }
        return images.first { $0.reference == reference }
    }

   

    private var imageCatalog: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredImages) { image in
                    ImageCatalogRow(
                        image: image,
                        isSelected: selection.contains(image.reference),
                        action: { selection = [image.reference] },
                        onRun: {
                            selection = [image.reference]
                            quickRun(image)
                        },
                        onCopyReference: { copyToPasteboard(image.reference) },
                        onDelete: {
                            selection = [image.reference]
                            deleteRequest = [image.reference]
                        }
                    )
                }
            }
            .padding(14)
        }
        .background(FruitTheme.pageBackground)
    }

    private var imageInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let image = selectedImage, selection.count == 1 {
                    Panel(title: "Image", systemImage: "info.circle") {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(image.displayName)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                Text(image.registryDisplay)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                ImageMetadataPill(text: image.tagDisplay, systemImage: "tag", tint: .blue)
                                ImageMetadataPill(text: image.variantDisplay, systemImage: "square.3.layers.3d", tint: .teal)
                            }
                        }

                        Divider()

                        DetailRow("Reference", image.reference)
                        DetailRow("Image ID", image.shortID)
                        DetailRow("Digest", inspect?.digest ?? image.id)
                        DetailRow("Media Type", inspect?.mediaType ?? image.mediaType ?? "-")
                        DetailRow("Created", image.createdDisplay)
                        DetailRow("Payload", image.totalSizeDisplay)
                    }

                    Panel(title: "Platforms", systemImage: "cpu") {
                        if image.platforms.isEmpty {
                            Text("No platform metadata")
                                .foregroundStyle(.secondary)
                        } else {
                            FlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(image.platforms, id: \.self) { platform in
                                    PlatformChip(platform: platform)
                                }
                            }
                        }
                    }

                    Panel(title: "Manifest", systemImage: "curlybraces") {
                        HStack {
                            Button("Reload") { Task { await loadInspect() } }
                            Button("Copy") { copyToPasteboard(inspect?.rawJSON ?? "") }.disabled(inspect == nil)
                            Spacer()
                        }
                        Text(inspect?.rawJSON ?? "No JSON loaded.")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else {
                    ContentUnavailableView("Select an Image", systemImage: "photo.stack", description: Text("Inspect digest, variants, and raw metadata."))
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
            let result = try await containerCLIAdapter.listImages()
            switch result {
            case .parsed(let value, let diagnostics):
                images = value
                appModel.cachedImageItems = value
                appModel.updateImages(from: value)
                errorMessage = diagnostics.warnings.first
            case .raw(_, let diagnostics):
                images = []
                errorMessage = diagnostics.warnings.first ?? "Image list returned output that Fruit Container could not parse."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncImagesFromCache() {
        images = appModel.cachedImageItems
        selection = selection.filter { reference in
            images.contains { $0.reference == reference }
        }
        if selection.isEmpty {
            inspect = nil
        }
    }

    private func loadInspect() async {
        inspect = nil
        guard let reference = selection.first, selection.count == 1 else { return }
        inspect = try? await containerCLIAdapter.inspectImage(reference: reference)
    }

    private func performPull(_ reference: String) {
        let model = appModel
        enqueueImageAction(title: "Pull \(reference)", command: "container image pull --progress plain -- \(reference)") { activityID in
            try await containerCLIAdapter.pullImage(reference: reference) { chunk in
                await MainActor.run {
                    model.appendActivityOutput(id: activityID, chunk: chunk.text)
                }
            }
        }
    }

    /// Runs an image with default settings (detached, auto-named by the CLI).
    /// For fine-grained options the user can still use the Run sheet in the
    /// Containers workspace; this is the quick secondary-click affordance.
    private func quickRun(_ image: ImageListItem) {
        let request = ContainerCreateRequest(
            imageReference: image.reference,
            name: nil,
            commandArguments: [],
            environment: [:],
            publishedPorts: [],
            volumeMounts: [],
            network: nil,
            workingDirectory: nil,
            cpuCount: nil,
            memory: nil
        )
        _ = appModel.enqueueActivity(
            title: "Run \(image.reference)",
            section: .containers,
            kind: .container,
            commandDescription: "container run --detach \(image.reference)"
        ) { _ in
            let id = try await containerCLIAdapter.runContainer(request: request)
            return ActivityOperationOutcome(summary: "Started container \(id).")
        }
    }

    private func performTag(source: String, target: String) {
        enqueueImageAction(title: "Tag \(source)", command: "container image tag \(source) \(target)") { _ in
            try await containerCLIAdapter.tagImage(sourceReference: source, targetReference: target)
        }
    }

    private func performPush(_ reference: String) {
        enqueueImageAction(title: "Push \(reference)", command: "container image push \(reference)") { _ in
            try await containerCLIAdapter.pushImage(reference: reference)
        }
    }

    private func enqueueImageAction(title: String, command: String, operation: @escaping @Sendable (_ activityID: UUID) async throws -> Void) {
        let adapter = containerCLIAdapter
        let model = appModel
        _ = appModel.enqueueActivity(title: title, section: .images, kind: .image, commandDescription: command) { activityID in
            try await operation(activityID)
            if let result = try? await adapter.listImages() {
                await MainActor.run {
                    if case .parsed(let value, _) = result {
                        model.cachedImageItems = value
                    }
                    model.updateImageSummary(from: result)
                }
            }
            return ActivityOperationOutcome(summary: "Completed.")
        }
    }

    private var registryCount: Int {
        Set(images.map(\.registryDisplay)).count
    }

    private var platformCount: Int {
        Set(images.flatMap(\.platforms)).count
    }

    private var totalPayloadDisplay: String {
        let total = images.compactMap(\.totalVariantSizeBytes).reduce(Int64(0), +)
        return total > 0 ? formatBytes(total) : "-"
    }
}

// MARK: - Images-specific subviews

private struct ImageCatalogRow: View {
    let image: ImageListItem
    let isSelected: Bool
    let action: () -> Void
    let onRun: () -> Void
    let onCopyReference: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconFill)
                    Image(systemName: image.registrySymbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(iconTint)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(image.displayName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(image.tagDisplay)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.11), in: Capsule())

                        Spacer(minLength: 0)

                        Text(image.totalSizeDisplay)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Label(image.registryDisplay, systemImage: "externaldrive")
                        Text(image.shortID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                        Label(image.variantDisplay, systemImage: "square.3.layers.3d")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !image.platforms.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(image.platforms.prefix(4), id: \.self) { platform in
                                PlatformChip(platform: platform, compact: true)
                            }
                            if image.platforms.count > 4 {
                                Text("+\(image.platforms.count - 4)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(image.reference), \(image.variantDisplay)")
        .contextMenu {
            Button {
                onRun()
            } label: {
                Label("Run", systemImage: "play.fill")
            }

            Button {
                onCopyReference()
            } label: {
                Label("Copy Reference", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.10) : FruitTheme.controlBackground
    }

    private var iconFill: Color {
        iconTint.opacity(isSelected ? 0.18 : 0.12)
    }

    private var iconTint: Color {
        if image.reference.hasPrefix("ghcr.io/apple/") { return .orange }
        if image.reference.contains("mongodb") { return .green }
        if image.reference.contains("nginx") { return .red }
        return .indigo
    }
}

private struct ImageStatTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(FruitTheme.cardFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Image Workflow Sheet

struct ImageWorkflowSheet: View {
    let localImages: [String]
    @Binding var pullReference: String
    @Binding var tagTarget: String
    @Binding var pushReference: String
    let selectedReference: String?
    let onPull: (String) -> Void
    let onTag: (_ source: String, _ target: String) -> Void
    let onPush: (String) -> Void

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tagSource = ""
    @State private var mode: ImageWorkflowMode = .pull

    private static let popularOfficialImages = [
        PopularImageSuggestion(reference: "nginx:latest", title: "nginx", detail: "Official web server", symbol: "globe"),
        PopularImageSuggestion(reference: "alpine:latest", title: "alpine", detail: "Small Linux base", symbol: "terminal"),
        PopularImageSuggestion(reference: "redis:latest", title: "redis", detail: "Cache and data store", symbol: "memorychip"),
        PopularImageSuggestion(reference: "postgres:latest", title: "postgres", detail: "Relational database", symbol: "cylinder.split.1x2"),
        PopularImageSuggestion(reference: "ubuntu:latest", title: "ubuntu", detail: "Linux distribution", symbol: "desktopcomputer"),
        PopularImageSuggestion(reference: "python:latest", title: "python", detail: "Python runtime", symbol: "chevron.left.forwardslash.chevron.right"),
        PopularImageSuggestion(reference: "node:latest", title: "node", detail: "JavaScript runtime", symbol: "curlybraces"),
        PopularImageSuggestion(reference: "mysql:latest", title: "mysql", detail: "Relational database", symbol: "externaldrive"),
        PopularImageSuggestion(reference: "mongo:latest", title: "mongo", detail: "Document database", symbol: "doc.richtext"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Workflow", selection: $mode) {
                    ForEach(ImageWorkflowMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding([.horizontal, .top], 18)
                .padding(.bottom, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch mode {
                        case .pull:
                            pullPanel
                        case .tag:
                            tagPanel
                        case .push:
                            pushPanel
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Image Workflow")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if let selectedReference {
                tagSource = selectedReference
                if pushReference.isEmpty { pushReference = selectedReference }
            }
        }
        .frame(width: 640, height: 560)
    }

    private var pullPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            workflowHeader(
                title: "Pull Image",
                detail: "Choose a popular Docker Official Image or enter any registry reference.",
                symbol: "square.and.arrow.down"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(Self.popularOfficialImages) { image in
                    popularImageButton(image)
                }
            }

            workflowField(
                title: "Image reference",
                text: $pullReference,
                placeholder: "nginx:latest"
            )

            workflowCommand("container image pull --progress plain -- \(pullReference.nilIfEmpty ?? "<image>")")

            primaryActionButton("Pull Image", systemImage: "square.and.arrow.down") {
                onPull(pullReference)
                showActivityAndDismiss()
            }
            .disabled(pullReference.nilIfEmpty == nil)
        }
    }

    private var tagPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            workflowHeader(
                title: "Tag Image",
                detail: "Create another local reference for a selected image.",
                symbol: "tag"
            )

            Picker("Source image", selection: $tagSource) {
                Text("Select local image").tag("")
                ForEach(localImages, id: \.self) { image in
                    Text(image).tag(image)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            workflowField(
                title: "Target reference",
                text: $tagTarget,
                placeholder: "registry.example.com/team/app:latest"
            )

            workflowCommand("container image tag \(tagSource.isEmpty ? "<source>" : tagSource) \(tagTarget.nilIfEmpty ?? "<target>")")

            primaryActionButton("Tag Image", systemImage: "tag") {
                onTag(tagSource, tagTarget)
                showActivityAndDismiss()
            }
            .disabled(tagSource.isEmpty || tagTarget.nilIfEmpty == nil)
        }
    }

    private var pushPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            workflowHeader(
                title: "Push Image",
                detail: "Push a local image reference to its configured registry.",
                symbol: "arrow.up.circle"
            )

            if !localImages.isEmpty {
                Picker("Local image", selection: $pushReference) {
                    Text("Custom reference").tag("")
                    ForEach(localImages, id: \.self) { image in
                        Text(image).tag(image)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            workflowField(
                title: "Reference",
                text: $pushReference,
                placeholder: "registry.example.com/team/app:latest"
            )

            workflowCommand("container image push \(pushReference.nilIfEmpty ?? "<reference>")")

            primaryActionButton("Push Image", systemImage: "arrow.up.circle") {
                onPush(pushReference)
                showActivityAndDismiss()
            }
            .disabled(pushReference.nilIfEmpty == nil)
        }
    }

    private func workflowHeader(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func popularImageButton(_ image: PopularImageSuggestion) -> some View {
        Button {
            pullReference = image.reference
        } label: {
            HStack(spacing: 10) {
                Image(systemName: image.symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(image.title)
                        .font(.callout.weight(.semibold))
                    Text(image.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FruitTheme.cardFill, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(image.reference)
    }

    private func workflowField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func workflowCommand(_ command: String) -> some View {
        CommandPreview(command: command)
    }

    private func primaryActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
                Text("Progress and results open in Logs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.large)
    }

    private func showActivityAndDismiss() {
        dismiss()
        DispatchQueue.main.async {
            appModel.selectedFruitSection = .activity
        }
    }
}

struct CommandPreview: View {
    let command: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copyToPasteboard(command)
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Copy command")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FruitTheme.cardFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum ImageWorkflowMode: String, CaseIterable, Identifiable {
    case pull
    case tag
    case push

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pull: "Pull"
        case .tag: "Tag"
        case .push: "Push"
        }
    }

    var systemImage: String {
        switch self {
        case .pull: "square.and.arrow.down"
        case .tag: "tag"
        case .push: "arrow.up.circle"
        }
    }
}

private struct PopularImageSuggestion: Identifiable {
    let reference: String
    let title: String
    let detail: String
    let symbol: String

    var id: String { reference }
}

// MARK: - ImageListItem display extensions

extension ImageListItem {
    var displayName: String {
        let slashParts = reference.split(separator: "/", omittingEmptySubsequences: false)
        return slashParts.last.map(String.init) ?? reference
    }

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

    var shortID: String {
        let trimmed = id.replacingOccurrences(of: "sha256:", with: "")
        return String(trimmed.prefix(12))
    }

    var variantDisplay: String {
        let count = max(variantCount, platforms.count)
        return count == 1 ? "1 variant" : "\(count) variants"
    }

    var totalSizeDisplay: String {
        if let totalVariantSizeBytes {
            return formatBytes(totalVariantSizeBytes)
        }
        if let size, let value = Int64(size) {
            return formatBytes(value)
        }
        return size ?? "-"
    }

    var createdDisplay: String {
        created ?? "-"
    }

    var registrySymbol: String {
        if reference.hasPrefix("ghcr.io/") { return "externaldrive.badge.icloud" }
        if reference.hasPrefix("docker.io/") { return "truck.box" }
        return "externaldrive"
    }
}

#if DEBUG
#Preview {
    ImagesWorkspaceView()
        .environmentObject(AppModel.preview)
        .frame(width: 1000, height: 680)
}
#endif
