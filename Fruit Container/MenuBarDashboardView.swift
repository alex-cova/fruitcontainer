import AppKit
import SwiftUI

struct MenuBarDashboardView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter
    @AppStorage(.appearancePreferenceKey) private var appearancePreferenceRaw = AppearancePreference.dark.rawValue

    @State private var selectedContainerID: ContainerSummary.ID?

    private let refreshController: AppRefreshController

    init(refreshController: AppRefreshController) {
        self.refreshController = refreshController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            resourcesSection
            actionSection
        }
        .padding(10)
        .frame(width: 340, alignment: .leading)
        .foregroundStyle(FruitDarkPalette.primaryText)
        .background(FruitDarkPalette.popoverBackground)
        .colorScheme(effectiveColorScheme)
        .onAppear {
            DispatchQueue.main.async {
                refreshController.startIfNeeded()
            }
        }
    }

    private var effectiveColorScheme: ColorScheme {
        AppearancePreference(rawValue: appearancePreferenceRaw)?.colorScheme ?? systemColorScheme
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🍎 Fruit Container")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FruitDarkPalette.primaryText)

                HStack(spacing: 6) {
                    Circle()
                        .fill(engineStateColor)
                        .frame(width: 7, height: 7)

                    Text(engineStateDisplay)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FruitDarkPalette.secondaryText)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(FruitDarkPalette.tertiaryText)

                    Text(systemHealthUpdatedDisplay)
                        .font(.caption)
                        .foregroundStyle(FruitDarkPalette.secondaryText)
                }
            }

            Spacer(minLength: 0)

            startSystemControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FruitDarkPalette.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(FruitDarkPalette.cardBorder(cornerRadius: 8))
    }

    /// Surfaces a "Start" button in the header whenever the runtime service is
    /// not running, so the system can be brought up without opening the main
    /// window. While the start operation is in flight a spinner replaces it,
    /// driven off the published activity log so it clears on completion.
    @ViewBuilder
    private var startSystemControl: some View {
        if isSystemStartInFlight {
            ProgressView()
                .controlSize(.small)
        } else if appModel.latestSystemHealthSnapshot?.engineState != .running {
            Button {
                startSystem()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Start the system service")
        }
    }

    private var isSystemStartInFlight: Bool {
        appModel.activities.contains { activity in
            activity.status.isActive && activity.commandDescription == "container system start"
        }
    }

    private var resourcesSection: some View {
        VStack(spacing: 0) {
            resourceRow(
                target: .containers,
                title: "Containers",
                value: "\(appModel.containers.count)",
                detail: "\(runningContainerCount) running",
                symbol: "truck.box",
                tint: FruitDarkPalette.blueAccent
            )
            if !appModel.containers.isEmpty {
                separator
                containerList
            }
            separator
            Spacer()
          
        }
        .background(FruitDarkPalette.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(FruitDarkPalette.cardBorder(cornerRadius: 8))
    }

    private var containerList: some View {
        VStack(spacing: 0) {
            ForEach(Array(appModel.containers.enumerated()), id: \.element.id) { index, container in
                if index > 0 {
                    separator
                }
                containerRow(container)
            }
        }
    }

    private func containerRow(_ container: ContainerSummary) -> some View {
        let isSelected = selectedContainerID == container.id
        let inFlightVerb = inFlightLifecycleVerb(for: container)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedContainerID = isSelected ? nil : container.id
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(stateColor(container.state))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FruitDarkPalette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(inFlightVerb ?? container.state.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(inFlightVerb == nil ? FruitDarkPalette.secondaryText : FruitDarkPalette.blueAccent)
                }

                Spacer(minLength: 8)

                if inFlightVerb != nil {
                    ProgressView()
                        .controlSize(.small)
                } else if isSelected {
                    lifecycleButton(for: container)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? FruitDarkPalette.controlBackground : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(container.name)
    }

    /// Returns "Starting…" or "Stopping…" when a queued or running lifecycle
    /// operation is targeting this container, otherwise `nil`. Derived from the
    /// published activity log so the indicator clears automatically on completion.
    private func inFlightLifecycleVerb(for container: ContainerSummary) -> String? {
        let startCommand = "container start \(container.name)"
        let stopCommand = "container stop \(container.name)"

        guard let activity = appModel.activities.first(where: { activity in
            activity.status.isActive
                && (activity.commandDescription == startCommand || activity.commandDescription == stopCommand)
        }) else {
            return nil
        }

        return activity.commandDescription == startCommand ? "Starting…" : "Stopping…"
    }

    private func lifecycleButton(for container: ContainerSummary) -> some View {
        let isRunning = container.state == .running
        let tint: Color = isRunning ? .orange : .green

        return Button {
            toggleLifecycle(for: container)
        } label: {
            Label(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(isRunning ? "Stop \(container.name)" : "Start \(container.name)")
    }


    private var actionSection: some View {
        HStack(spacing: 8) {
            menuActionButton("Open", systemImage: "macwindow") { showMainWindow() }
            menuActionButton("Settings", systemImage: "gearshape") { showSettings() }
            menuActionButton("Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(FruitDarkPalette.separator)
            .frame(height: 1)
    }

    private func toggleLifecycle(for container: ContainerSummary) {
        let isRunning = container.state == .running
        let id = container.name
        let verb = isRunning ? "Stop" : "Start"
        let command = isRunning ? "stop" : "start"
        let adapter = containerCLIAdapter
        let model = appModel

        _ = appModel.enqueueActivity(
            title: "\(verb) \(container.name)",
            section: .containers,
            kind: .container,
            commandDescription: "container \(command) \(id)"
        ) { _ in
            if isRunning {
                try await adapter.stopContainers(ids: [id])
            } else {
                try await adapter.startContainers(ids: [id])
            }
            // The CLI returns before the container settles into its new state, so
            // poll the list until the expected state is reached (or we time out).
            // The activity stays active — keeping the "Starting…/Stopping…" label
            // visible — until the change is real, then the row reflects the final
            // state the moment the spinner clears.
            for attempt in 0..<15 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                guard let result = try? await adapter.listContainers() else { continue }
                await MainActor.run {
                    model.updateContainerSummary(from: result)
                }
                guard case .parsed(let items, _) = result else { continue }
                let currentState: ContainerState? = await MainActor.run {
                    items.first { $0.name == id }.map { ContainerState(cliState: $0.state) }
                }
                let reachedTarget = isRunning ? (currentState != .running) : (currentState == .running)
                if reachedTarget {
                    break
                }
            }
            return ActivityOperationOutcome(summary: "\(verb)ed container \(container.name).")
        }
    }

    private func startSystem() {
        let adapter = containerCLIAdapter
        let model = appModel

        _ = appModel.enqueueActivity(
            title: "Start system service",
            section: .system,
            kind: .system,
            commandDescription: "container system start"
        ) { _ in
            try await adapter.startSystem()
            let snapshot = await adapter.collectSystemHealthSnapshot()
            let metrics = (try? await adapter.fetchContainerStats()) ?? []
            await MainActor.run {
                model.latestSystemHealthSnapshot = snapshot
                model.latestSystemHealthUpdatedAt = .now
                model.updateContainerMetrics(from: metrics)
            }
            return ActivityOperationOutcome(summary: "System service started.")
        }
    }

    private func stateColor(_ state: ContainerState) -> Color {
        switch state {
        case .running:
            .green
        case .paused:
            .orange
        case .created:
            FruitDarkPalette.blueAccent
        case .stopped, .exited:
            FruitDarkPalette.secondaryText
        case .unknown:
            FruitDarkPalette.tertiaryText
        }
    }

    private var runningContainerCount: Int {
        appModel.containers.filter { $0.state == .running }.count
    }

    private var attachedNetworkCount: Int {
        appModel.networks.filter { $0.attachedContainerCount > 0 }.count
    }

    private var referencedVolumeCount: Int {
        appModel.volumes.filter { $0.attachedContainerCount > 0 }.count
    }

    private var runningOperationCount: Int {
        appModel.activities.filter { $0.status == .running }.count
    }

    private var failedOperationCount: Int {
        appModel.activities.filter { $0.status == .failed }.count
    }

    private var engineStateDisplay: String {
        switch appModel.latestSystemHealthSnapshot?.engineState {
        case .running:
            "Running"
        case .stopped:
            "Stopped"
        case .unknown, .none:
            "Unknown"
        }
    }

    private var engineStateColor: Color {
        switch appModel.latestSystemHealthSnapshot?.engineState {
        case .running:
            .green
        case .stopped:
            .orange
        case .unknown, .none:
            .secondary
        }
    }

    private var preflightCounts: (pass: Int, warning: Int, failure: Int) {
        guard let snapshot = appModel.latestSystemHealthSnapshot else {
            return (0, 0, 0)
        }

        return (
            snapshot.preflightChecks.filter { $0.severity == .pass }.count,
            snapshot.preflightChecks.filter { $0.severity == .warning }.count,
            snapshot.preflightChecks.filter { $0.severity == .failure }.count
        )
    }

    private var systemHealthUpdatedDisplay: String {
        guard let timestamp = appModel.latestSystemHealthUpdatedAt else {
            return "No snapshot"
        }
        return timestamp.formatted(date: .omitted, time: .shortened)
    }

    private var operationsDisplay: String {
        "\(runningOperationCount) running · \(failedOperationCount) failed"
    }

    private func runtimeRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(FruitDarkPalette.secondaryText)

            Spacer(minLength: 0)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(FruitDarkPalette.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func preflightChip(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(value)")
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color.opacity(0.72))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(color)
    }

    private func menuActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(FruitDarkPalette.primaryText)
        .background(FruitDarkPalette.controlBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay(FruitDarkPalette.cardBorder(cornerRadius: 7))
        .help(title)
    }

    private func resourceRow(
        target: FruitSection,
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        Button {
            showMainWindow(selecting: target)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FruitDarkPalette.primaryText)
                }

                Spacer(minLength: 10)

            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(target.title)")
    }

    private func showMainWindow(selecting section: FruitSection? = nil) {
        if let section {
            appModel.selectedFruitSection = section
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: AppSceneID.mainWindow)
    }

    private func showSettings() {
        showMainWindow(selecting: .settings)
    }
}

private enum FruitDarkPalette {
    static let popoverBackground = Color(nsColor: .textBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let controlBackground = Color(nsColor: .windowBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let blueAccent = Color.blue
    static let purpleAccent = Color.purple
    static let cyanAccent = Color.cyan
    static let greenAccent = Color.green

    static func cardBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(separator, lineWidth: 0.5)
    }
}

#if DEBUG
#Preview {
    let model = AppModel.preview
    return MenuBarDashboardView(
        refreshController: AppRefreshController(
            appModel: model,
            containerCLIAdapter: AppDependencies.containerCLIAdapter
        )
    )
    .environmentObject(model)
}
#endif
