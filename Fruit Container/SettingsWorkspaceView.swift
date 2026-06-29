import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    let updater: any AppUpdaterProviding
    @AppStorage(.appearancePreferenceKey) private var appearancePreferenceRaw = AppearancePreference.dark.rawValue
    @AppStorage(.showMenuBarExtraKey) private var showMenuBarExtra = true
    @AppStorage(.showSidebarBadgesKey) private var showSidebarBadges = true
    @State private var diagnosticsOptions = DiagnosticsBundleOptions()
    @State private var isRefreshingCapabilities = false
    @State private var settingsMessage: String?
    @State private var settingsMessageIsError = false
    @State private var loginLaunchController = LoginLaunchController.shared
    @State private var openAtLogin = LoginLaunchController.shared.isOpenAtLoginEnabled
    @State private var isUpdatingOpenAtLogin = false
    @State private var loginLaunchErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let settingsMessage {
                    FeedbackBar(message: settingsMessage, isError: settingsMessageIsError)
                }
                Panel(title: "General", systemImage: "gearshape") {
                    generalSettings
                }
                Panel(title: "Apple container Compatibility", systemImage: "apple.logo") {
                    Text("Fruit Container uses the installed `container` CLI as the source of truth. It discovers the executable, checks `container system version`, and reports the service state from `container system status`.")
                        .foregroundStyle(.secondary)
                    DetailRow("Executable", appModel.latestSystemHealthSnapshot?.executablePath ?? "Not found")
                    DetailRow("Version", appModel.latestSystemHealthSnapshot?.cliVersionDisplay ?? "Unavailable")
                    DetailRow("Install Source", appModel.latestSystemHealthSnapshot?.installSource?.displayName ?? "Unknown")
                }
                Panel(title: "Container CLI Maintenance", systemImage: "arrow.down.app") {
                    ContainerCLIMaintenanceSettingsView()
                }
                Panel(title: "Container Resource Defaults", systemImage: "slider.horizontal.3") {
                    ContainerResourcesSettingsView()
                }
                Panel(title: "Diagnostics", systemImage: "stethoscope") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button {
                                copyRedactedSummary()
                            } label: {
                                Label("Copy Redacted Summary", systemImage: "doc.on.doc")
                            }
                            .disabled(appModel.hasActiveActivity(for: .diagnostics))

                            Button {
                                exportSupportBundle()
                            } label: {
                                Label("Export Support Bundle", systemImage: "square.and.arrow.down")
                            }
                            .disabled(appModel.hasActiveActivity(for: .diagnostics))
                        }

                        Toggle("Include system logs", isOn: $diagnosticsOptions.includeSystemLogs)
                        Picker("Log Window", selection: $diagnosticsOptions.logWindow) {
                            ForEach(Array(DiagnosticsLogWindow.allCases), id: \.self) { window in
                                Text(window.title).tag(window)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!diagnosticsOptions.includeSystemLogs)

                        DetailRow("Last Export", appModel.latestDiagnosticsBundlePath.map { ($0 as NSString).lastPathComponent } ?? "None")
                        DetailRow("Last Update", appModel.latestDiagnosticsUpdatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")

                        if let summary = appModel.latestDiagnosticsSummary {
                            Text(summary)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(8)
                        }
                    }
                }
                Panel(title: "Future Work", systemImage: "wrench.and.screwdriver") {
                    FutureRow(
                        title: "Machines",
                        status: appModel.commandCapabilities.machine.displayName,
                        detail: "Keep this as discovery-only until real machine adapter methods and output parsers exist."
                    )
                    FutureRow(
                        title: "Builds",
                        status: appModel.commandCapabilities.build.displayName,
                        detail: "Keep this as discovery-only until a build request model and parser are implemented."
                    )
                    if let checkedAt = appModel.commandCapabilities.checkedAt {
                        Text("Last checked \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Panel(title: "Platform Notes", systemImage: "cpu") {
                    Text("Upstream Apple documentation describes `container` as optimized for Apple silicon and supported on macOS 26. Fruit Container should continue to show exact command failures and installed CLI details rather than assuming every Mac is compatible.")
                        .foregroundStyle(.secondary)
                }
                Panel(title: "About", systemImage: "info.circle") {
                    AboutSettingsView(updater: updater)
                        .frame(maxWidth: 620, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .topLeading)
        }
        .task {
            if appModel.commandCapabilities.checkedAt == nil {
                await refreshCapabilities()
            }
            syncOpenAtLoginState()
        }
        .alert("Open at Login", isPresented: loginLaunchErrorIsPresented) {
            Button("OK", role: .cancel) {
                loginLaunchErrorMessage = nil
            }
        } message: {
            Text(loginLaunchErrorMessage ?? "Fruit Container could not update the login item setting.")
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Show sidebar badges", isOn: $showSidebarBadges)

            Picker("Appearance", selection: $appearancePreferenceRaw) {
                ForEach(AppearancePreference.allCases) { preference in
                    Text(preference.title).tag(preference.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show menu bar extra", isOn: $showMenuBarExtra)

                Text(menuBarDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Open at Login", isOn: openAtLoginBinding)
                    .disabled(isUpdatingOpenAtLogin)

                Text(openAtLoginDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if loginLaunchController.needsApproval {
                    Button("Open Login Items Settings") {
                        loginLaunchController.openLoginItemsSettings()
                    }
                }
            }
        }
    }

    private var menuBarDescription: String {
        if showMenuBarExtra {
            return "Shows a compact runtime and resource summary in the macOS menu bar. Closing the main window keeps the app running there."
        }

        return "Hides the menu bar extra. Closing the main window quits the app."
    }

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { openAtLogin },
            set: { newValue in
                let previousValue = openAtLogin
                openAtLogin = newValue
                isUpdatingOpenAtLogin = true

                Task { @MainActor in
                    defer { isUpdatingOpenAtLogin = false }

                    do {
                        try loginLaunchController.setOpenAtLoginEnabled(newValue)
                        syncOpenAtLoginState()
                    } catch {
                        openAtLogin = previousValue
                        loginLaunchErrorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var loginLaunchErrorIsPresented: Binding<Bool> {
        Binding(
            get: { loginLaunchErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    loginLaunchErrorMessage = nil
                }
            }
        )
    }

    private var openAtLoginDescription: String {
        if loginLaunchController.needsApproval {
            return "macOS requires approval in System Settings before Fruit Container can launch automatically."
        }

        if openAtLogin {
            if showMenuBarExtra {
                return "Starts in the menu bar when you log in instead of opening the main window."
            }

            return "Launches when you log in, and opens the main window because the menu bar extra is turned off."
        }

        if showMenuBarExtra {
            return "Keeps launch manual. If enabled later, login launches will start in the menu bar."
        }

        return "Keeps launch manual until you open the app yourself."
    }

    private func syncOpenAtLoginState() {
        loginLaunchController.refreshStatus()
        openAtLogin = loginLaunchController.isOpenAtLoginEnabled
    }

    private func refreshCapabilities() async {
        isRefreshingCapabilities = true
        defer { isRefreshingCapabilities = false }

        async let build = containerCLIAdapter.supportsCommand(["build"])
        async let machine = containerCLIAdapter.supportsCommand(["machine"])
        appModel.commandCapabilities = CommandCapabilitySnapshot(
            build: await build ? .available : .unavailable,
            machine: await machine ? .available : .unavailable,
            checkedAt: .now
        )
    }

    private func exportSupportBundle() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.zip]
        panel.nameFieldStringValue = defaultDiagnosticsArchiveName

        guard panel.runModal() == .OK, let url = panel.url else { return }

        settingsMessage = nil
        let options = diagnosticsOptions

        _ = appModel.enqueueActivity(
            title: "Export support bundle",
            section: .diagnostics,
            kind: .diagnostics,
            commandDescription: "diagnostics export \(url.lastPathComponent)",
            isRetryable: false
        ) { activityID in
            let operationSnapshot = await MainActor.run {
                appModel.makeDiagnosticsOperationSnapshot()
            }
            let collection = await DiagnosticsSupportBundleBuilder.collect(
                options: options,
                adapter: containerCLIAdapter,
                operationSnapshot: operationSnapshot
            ) { message in
                await MainActor.run {
                    appModel.appendActivityOutput(id: activityID, chunk: "\(message)\n")
                }
            }

            let exportResult = try DiagnosticsSupportBundleBuilder.exportBundle(collection: collection, to: url)
            await MainActor.run {
                appModel.recordDiagnosticsBundleExport(
                    path: exportResult.archiveURL.path,
                    summary: exportResult.summary
                )
            }

            let warningSuffix = exportResult.warningCount > 0 ? " with \(exportResult.warningCount) warning(s)." : "."
            return ActivityOperationOutcome(summary: "Exported support bundle to \(url.lastPathComponent)\(warningSuffix)")
        }
    }

    private func copyRedactedSummary() {
        settingsMessage = nil
        let options = diagnosticsOptions

        _ = appModel.enqueueActivity(
            title: "Copy redacted summary",
            section: .diagnostics,
            kind: .diagnostics,
            commandDescription: "diagnostics summary copy"
        ) { activityID in
            let operationSnapshot = await MainActor.run {
                appModel.makeDiagnosticsOperationSnapshot()
            }
            let collection = await DiagnosticsSupportBundleBuilder.collect(
                options: options,
                adapter: containerCLIAdapter,
                operationSnapshot: operationSnapshot
            ) { message in
                await MainActor.run {
                    appModel.appendActivityOutput(id: activityID, chunk: "\(message)\n")
                }
            }

            let summary = DiagnosticsSupportBundleBuilder.makeRedactedSummary(from: collection)
            await MainActor.run {
                copyToPasteboard(summary)
                appModel.recordDiagnosticsSummary(summary)
            }

            let warningSuffix = collection.warnings.isEmpty ? "." : " with \(collection.warnings.count) warning(s)."
            return ActivityOperationOutcome(summary: "Copied redacted troubleshooting summary\(warningSuffix)")
        }
    }

    private var defaultDiagnosticsArchiveName: String {
        let stamp = Date.now.formatted(.dateTime.year().month().day().hour().minute().second())
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "fruit-container-support-\(stamp).zip"
    }
}

// MARK: - Settings subviews

struct ContainerCLIMaintenanceSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update an existing Apple container installation with the local update script, or install the latest signed package when the CLI is not detected.")
                .foregroundStyle(.secondary)

            DetailRow("Update script", "/usr/local/bin/update-container.sh")
            DetailRow("Latest signed package", "container \(ContainerCLIAdapter.latestSignedInstallerVersion)")

            HStack {
                Button {
                    updateContainer()
                } label: {
                    Label("Update container", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(appModel.hasActiveActivity(for: .system))

                if shouldOfferInstall {
                    Button {
                        installContainer()
                    } label: {
                        Label("Install Signed Package", systemImage: "square.and.arrow.down")
                    }
                    .disabled(appModel.hasActiveActivity(for: .system))
                }

                Spacer()
            }

            if shouldOfferInstall {
                FeedbackBar(message: "`container` was not detected. Download the signed Apple package and complete installation in Installer.", isError: false)
            }

            if let message {
                FeedbackBar(message: message, isError: messageIsError)
            }
        }
        .task {
            if appModel.latestSystemHealthSnapshot == nil {
                let snapshot = await containerCLIAdapter.collectSystemHealthSnapshot()
                appModel.latestSystemHealthSnapshot = snapshot
                appModel.latestSystemHealthUpdatedAt = .now
            }
        }
    }

    private var shouldOfferInstall: Bool {
        guard let snapshot = appModel.latestSystemHealthSnapshot else {
            return false
        }
        if snapshot.executablePath == nil {
            return true
        }
        if case .unavailable = snapshot.compatibilityReport.state {
            return true
        }
        return false
    }

    private func updateContainer() {
        message = "Update queued. Open Logs for command output."
        messageIsError = false

        _ = appModel.enqueueActivity(
            title: "Update container CLI",
            section: .system,
            kind: .system,
            commandDescription: "/usr/local/bin/update-container.sh"
        ) { _ in
            try await containerCLIAdapter.updateContainerCommand()
            let snapshot = await containerCLIAdapter.collectSystemHealthSnapshot()
            await MainActor.run {
                appModel.latestSystemHealthSnapshot = snapshot
                appModel.latestSystemHealthUpdatedAt = .now
            }
            return ActivityOperationOutcome(summary: "Container update completed.")
        }
    }

    private func installContainer() {
        message = "Downloading signed installer package."
        messageIsError = false

        _ = appModel.enqueueActivity(
            title: "Install container CLI",
            section: .system,
            kind: .system,
            commandDescription: "curl -L \(ContainerCLIAdapter.latestSignedInstallerURL.absoluteString)"
        ) { _ in
            let packageURL = try await containerCLIAdapter.downloadLatestSignedInstaller()
            await MainActor.run {
                _ = NSWorkspace.shared.open(packageURL)
            }
            return ActivityOperationOutcome(summary: "Downloaded signed installer and opened Installer.")
        }
    }
}

struct ContainerResourcesSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    private let store = ContainerResourceConfigurationStore()

    @State private var originalConfiguration = ContainerResourceConfiguration.empty
    @State private var cpusText = ""
    @State private var memoryText = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var needsRestart = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set the default CPU and memory limits used when new containers are created without explicit resource flags.")
                .foregroundStyle(.secondary)

            DetailRow("User config", store.fileURL.path)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("CPUs")
                        .foregroundStyle(.secondary)
                    TextField("Default", text: $cpusText)
                        .frame(width: 120)
                    Text("Positive integer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    Text("Memory")
                        .foregroundStyle(.secondary)
                    TextField("Default", text: $memoryText)
                        .frame(width: 120)
                    Text("Examples: 512m, 2048mb, 4g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .textFieldStyle(.roundedBorder)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    loadConfiguration()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading || isSaving)

                Button {
                    saveConfiguration()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!canSave || isSaving)

                Button {
                    restartService()
                } label: {
                    Label("Restart Service", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(appModel.hasActiveActivity(for: .system))

                Spacer()
            }

            if needsRestart {
                FeedbackBar(message: "Saved changes will take effect after the container service restarts.", isError: false)
            }

            if let message {
                FeedbackBar(message: message, isError: messageIsError)
            }

            Divider()

            Text(configurationPreview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .task {
            loadConfiguration()
        }
    }

    private var validationMessage: String? {
        let cpu = cpusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cpu.isEmpty, Int(cpu).map({ $0 > 0 }) != true {
            return "CPUs must be blank or a positive integer."
        }

        if !ContainerResourceConfiguration.isValidMemory(memoryText) {
            return "Memory must be blank or include a size unit such as m, mb, g, or gb."
        }

        return nil
    }

    private var editedConfiguration: ContainerResourceConfiguration? {
        let cpu = cpusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cpus: Int?
        if cpu.isEmpty {
            cpus = nil
        } else if let value = Int(cpu), value > 0 {
            cpus = value
        } else {
            return nil
        }

        guard ContainerResourceConfiguration.isValidMemory(memoryText) else {
            return nil
        }

        return ContainerResourceConfiguration(
            cpus: cpus,
            memory: ContainerResourceConfiguration.normalizedMemory(memoryText)
        )
    }

    private var canSave: Bool {
        guard let editedConfiguration else { return false }
        return editedConfiguration != originalConfiguration
    }

    private var configurationPreview: String {
        editedConfiguration?.managedSnippet ?? "[container]\n# Invalid resource values"
    }

    private func loadConfiguration() {
        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            let configuration = try store.load()
            originalConfiguration = configuration
            cpusText = configuration.cpus.map(String.init) ?? ""
            memoryText = configuration.memory ?? ""
            needsRestart = false
            message = "Loaded \(store.fileURL.path)"
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func saveConfiguration() {
        guard let editedConfiguration else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }

        do {
            try store.save(editedConfiguration)
            originalConfiguration = editedConfiguration
            needsRestart = true
            message = "Saved container resource defaults."
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func restartService() {
        needsRestart = false
        message = "Restart queued. Open Logs for command output."
        messageIsError = false

        _ = appModel.enqueueActivity(
            title: "Restart system service",
            section: .system,
            kind: .system,
            commandDescription: "container system stop; container system start --disable-kernel-install"
        ) { _ in
            try await containerCLIAdapter.stopSystem()
            try await containerCLIAdapter.startSystem()
            let snapshot = await containerCLIAdapter.collectSystemHealthSnapshot()
            await MainActor.run {
                appModel.latestSystemHealthSnapshot = snapshot
                appModel.latestSystemHealthUpdatedAt = .now
            }
            return ActivityOperationOutcome(summary: "System service restarted.")
        }
    }
}

#if DEBUG
#Preview {
    SettingsWorkspaceView(updater: DisabledAppUpdater())
        .environmentObject(AppModel.preview)
        .frame(width: 900, height: 720)
}
#endif
