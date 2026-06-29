import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    private let metricsRefreshInterval = 3.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusGrid
                metricsPanel
                nextActionPanel
                recentActivityPanel
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .topLeading)
        }
        .background(FruitTheme.pageBackground)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ControlGroup {
                    Button {
                        enqueueSystemAction(start: true)
                    } label: {
                        Label("Start Service", systemImage: "play.fill")
                    }
                    .disabled(appModel.hasActiveActivity(for: .system))

                    Button {
                        enqueueSystemAction(start: false)
                    } label: {
                        Label("Stop Service", systemImage: "stop.fill")
                    }
                    .disabled(appModel.hasActiveActivity(for: .system))
                }

            }
        }
        .task {
            if appModel.latestSystemHealthSnapshot == nil {
                await refresh()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.title.weight(.semibold))
                .foregroundStyle(serviceTint)
                .frame(width: 54, height: 54)
                .background(serviceTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Apple container at a glance")
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Service health, local resources, and recent operations without leaving macOS.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            StatusBadge(text: serviceValue, color: serviceTint)
        }
        .padding(.bottom, 4)
    }

    private var statusGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            MetricCard(
                title: "System Service",
                value: serviceValue,
                detail: serviceDetail,
                systemImage: "server.rack",
                tint: serviceTint
            )
            MetricCard(
                title: "CLI Version",
                value: appModel.latestSystemHealthSnapshot?.cliVersionDisplay ?? "Not found",
                detail: appModel.latestSystemHealthSnapshot?.executablePath ?? "Install Apple container to continue",
                systemImage: "terminal",
                tint: .blue
            )
            MetricCard(
                title: "Containers",
                value: "\(appModel.containers.count)",
                detail: "\(runningCount) running, \(stoppedCount) stopped",
                systemImage: "truck.box",
                tint: .green
            )
            MetricCard(
                title: "Images",
                value: "\(appModel.images.count)",
                detail: appModel.images.isEmpty ? "Pull an OCI image to begin" : "Local OCI-compatible images",
                systemImage: "photo.stack",
                tint: .indigo
            )
        }
    }

    private var nextActionPanel: some View {
        Panel(title: "Recommended Next Action", systemImage: "sparkles") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: nextActionIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(nextActionTint)
                    .frame(width: 34, height: 34)
                    .background(nextActionTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(nextActionTitle)
                        .font(.headline)
                    Text(nextActionDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var metricsPanel: some View {
        Panel(title: "Metrics", systemImage: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    MetricsSummaryChip(
                        title: "Updated",
                        value: containerMetricsUpdatedDisplay,
                        systemImage: "clock"
                    )
                    MetricsSummaryChip(
                        title: "Interval",
                        value: metricsRefreshIntervalDisplay,
                        systemImage: "timer"
                    )
                    MetricsSummaryChip(
                        title: "Containers",
                        value: "\(appModel.containerMetrics.count)",
                        systemImage: "truck.box"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if appModel.containerMetrics.isEmpty {
                    ActionableEmptyState(
                        title: "No Metrics Available",
                        systemImage: "chart.bar.xaxis",
                        message: "Run a container to start sampling CPU, memory, network, and process metrics.",
                        actionTitle: appModel.containers.isEmpty ? nil : "Open Containers",
                        actionSystemImage: "truck.box",
                        action: appModel.containers.isEmpty ? nil : { appModel.selectedFruitSection = .containers }
                    )
                    .frame(minHeight: 200)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                        MetricsChartCard(
                            title: "CPU Usage",
                            detail: cpuMetricsDetail
                        ) {
                            historicalCPUChart
                        }

                        MetricsChartCard(
                            title: "Memory Usage",
                            detail: memoryMetricsDetail
                        ) {
                            historicalMemoryChart
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(appModel.containerMetrics) { entry in
                            ContainerMetricsRow(entry: entry)
                            if entry.id != appModel.containerMetrics.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(FruitTheme.cardFill, in: RoundedRectangle(cornerRadius: FruitTheme.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FruitTheme.cornerRadius, style: .continuous)
                            .stroke(FruitTheme.hairline)
                    }
                }
            }
        }
    }

    private var recentActivityPanel: some View {
        Panel(title: "Recent Activity", systemImage: "clock.arrow.circlepath") {
            if appModel.activities.isEmpty {
                ActionableEmptyState(
                    title: "No Operations Yet",
                    systemImage: "clock",
                    message: "Commands you run from Fruit Container will appear here.",
                    actionTitle: "Open Logs",
                    actionSystemImage: "list.bullet.rectangle",
                    action: { appModel.selectedFruitSection = .activity }
                )
                .frame(minHeight: 140)
            } else {
                VStack(spacing: 0) {
                    ForEach(appModel.activities.prefix(5)) { activity in
                        ActivityRowView(activity: activity)
                        if activity.id != appModel.activities.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var runningCount: Int {
        appModel.containers.filter { $0.state == .running }.count
    }

    private var stoppedCount: Int {
        appModel.containers.count - runningCount
    }

    private var serviceValue: String {
        guard let snapshot = appModel.latestSystemHealthSnapshot else { return "Checking" }
        switch snapshot.compatibilityReport.state {
        case .unavailable: return "Not installed"
        case .untestedNewerMajor: return "Untested"
        case .unsupported: return "Unsupported"
        case .supported:
            switch snapshot.engineState {
            case .running: return "Running"
            case .stopped: return "Stopped"
            case .unknown: return "Unknown"
            }
        }
    }

    private var serviceDetail: String {
        appModel.latestSystemHealthSnapshot?.engineStatusDetail ?? "Collecting system status"
    }

    private var serviceTint: Color {
        guard let snapshot = appModel.latestSystemHealthSnapshot else { return .secondary }
        switch snapshot.compatibilityReport.state {
        case .unavailable, .unsupported: return .red
        case .untestedNewerMajor: return .orange
        case .supported:
            switch snapshot.engineState {
            case .running: return .green
            case .stopped: return .orange
            case .unknown: return .secondary
            }
        }
    }

    private var historicalCPUChart: some View {
        Chart(Array(recentContainerMetricsHistory.enumerated()), id: \.offset) { offset, point in
            BarMark(
                x: .value("Sample", offset + 1),
                y: .value("CPU %", max(point.totalCPUUsagePercent, 0))
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Color.blue)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisTick()
            }
        }
        .chartYAxisLabel("CPU %")
        .frame(minHeight: 220)
    }

    private var historicalMemoryChart: some View {
        Chart(Array(recentContainerMetricsHistory.enumerated()), id: \.offset) { offset, point in
            BarMark(
                x: .value("Sample", offset + 1),
                y: .value("Memory", Double(point.totalMemoryUsageBytes))
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Color.blue)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisTick()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                if let bytes = value.as(Double.self) {
                    AxisValueLabel(formatBytes(Int64(bytes)))
                }
            }
        }
        .chartYAxisLabel("Memory")
        .frame(minHeight: 220)
    }

    private var recentContainerMetricsHistory: [ContainerMetricsHistoryPoint] {
        let sampleCount = 12
        let history = Array(appModel.containerMetricsHistory.suffix(sampleCount))
        guard history.count < sampleCount else { return history }

        let interval = max(metricsRefreshInterval, 1)
        let endDate = history.first?.capturedAt ?? appModel.containerMetricsUpdatedAt ?? .now
        let missingCount = sampleCount - history.count
        let placeholders = (0..<missingCount).map { offset in
            ContainerMetricsHistoryPoint(
                capturedAt: endDate.addingTimeInterval(-interval * Double(missingCount - offset)),
                totalCPUUsagePercent: 0,
                totalMemoryUsageBytes: 0,
                totalMemoryLimitBytes: 0,
                containerCount: appModel.containerMetrics.count
            )
        }
        return placeholders + history
    }

    private var cpuMetricsDetail: String {
        if appModel.containerMetrics.contains(where: { $0.cpuUsagePercent != nil }) {
            return "Recent total usage sampled every \(metricsRefreshIntervalDisplay)."
        }
        return "Waiting for a second sample to calculate CPU usage."
    }

    private var memoryMetricsDetail: String {
        let totalUsage = appModel.containerMetrics.reduce(Int64(0)) { $0 + ($1.memoryUsageBytes ?? 0) }
        let totalLimit = appModel.containerMetrics.reduce(Int64(0)) { $0 + ($1.memoryLimitBytes ?? 0) }
        guard totalLimit > 0 else {
            return "Recent total usage across sampled containers."
        }
        return "\(formatBytes(totalUsage)) of \(formatBytes(totalLimit)) allocated."
    }

    private var containerMetricsUpdatedDisplay: String {
        guard let updatedAt = appModel.containerMetricsUpdatedAt else { return "Waiting" }
        return updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var metricsRefreshIntervalDisplay: String {
        "\(Int(metricsRefreshInterval))s"
    }

    private var nextActionTitle: String {
        guard let snapshot = appModel.latestSystemHealthSnapshot else { return "Check Apple container" }
        switch snapshot.compatibilityReport.state {
        case .unavailable: return "Install Apple container"
        case .untestedNewerMajor: return "Smoke test this container version"
        case .unsupported: return "Update Fruit Container compatibility policy"
        case .supported:
            if snapshot.engineState != .running { return "Start the system service" }
            if appModel.images.isEmpty { return "Pull your first image" }
            if appModel.containers.isEmpty { return "Run a container" }
            return "Review recent operations"
        }
    }

    private var nextActionDetail: String {
        guard let snapshot = appModel.latestSystemHealthSnapshot else {
            return "Fruit Container is checking for the `container` CLI and runtime service."
        }
        switch snapshot.compatibilityReport.state {
        case .unavailable:
            return snapshot.installGuidance?.summary ?? "Download the official signed package from apple/container releases, then run `container system start`."
        case .untestedNewerMajor(let reason):
            return reason
        case .unsupported(let reason):
            return reason
        case .supported:
            if snapshot.engineState != .running { return "The CLI is installed, but the runtime service is not reachable yet." }
            if appModel.images.isEmpty { return "Use Images to pull an OCI-compatible image from a registry." }
            if appModel.containers.isEmpty { return "Use Containers to run a local or remote image with Apple container." }
            return "Open Logs for command output, errors, and retry controls."
        }
    }

    private var nextActionIcon: String {
        serviceTint == .green ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var nextActionTint: Color { serviceTint }

    private func refresh() async {
        let snapshot = await containerCLIAdapter.collectSystemHealthSnapshot()
        let metrics = (try? await containerCLIAdapter.fetchContainerStats()) ?? []
        appModel.latestSystemHealthSnapshot = snapshot
        appModel.latestSystemHealthUpdatedAt = .now
        appModel.updateContainerMetrics(from: metrics)
    }

    private func enqueueSystemAction(start: Bool) {
        _ = appModel.enqueueActivity(
            title: start ? "Start system service" : "Stop system service",
            section: .system,
            kind: .system,
            commandDescription: start ? "container system start" : "container system stop"
        ) { _ in
            if start {
                try await containerCLIAdapter.startSystem()
            } else {
                try await containerCLIAdapter.stopSystem()
            }
            let snapshot = await containerCLIAdapter.collectSystemHealthSnapshot()
            let metrics = (try? await containerCLIAdapter.fetchContainerStats()) ?? []
            await MainActor.run {
                appModel.latestSystemHealthSnapshot = snapshot
                appModel.latestSystemHealthUpdatedAt = .now
                appModel.updateContainerMetrics(from: metrics)
            }
            return ActivityOperationOutcome(summary: start ? "System service started." : "System service stopped.")
        }
    }
}

// MARK: - Dashboard-specific subviews

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
            }
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(FruitTheme.cardFill, in: RoundedRectangle(cornerRadius: FruitTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FruitTheme.cornerRadius, style: .continuous)
                .stroke(FruitTheme.hairline)
        }
    }
}

private struct MetricsSummaryChip: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(FruitTheme.controlBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(FruitTheme.hairline)
        }
    }
}

private struct MetricsChartCard<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FruitTheme.controlBackground, in: RoundedRectangle(cornerRadius: FruitTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FruitTheme.cornerRadius, style: .continuous)
                .stroke(FruitTheme.hairline)
        }
    }
}

private struct ContainerMetricsRow: View {
    let entry: ContainerMetricsEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.containerName)
                    .font(.headline)
                Text(entry.containerID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text("CPU \(formatPercent(entry.cpuUsagePercent))")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(memoryDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(ioDisplay)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let processCount = entry.processCount {
                    Text("\(processCount) process\(processCount == 1 ? "" : "es")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var memoryDisplay: String {
        guard let usage = entry.memoryUsageBytes else { return "Memory unavailable" }
        if let limit = entry.memoryLimitBytes, limit > 0 {
            return "\(formatBytes(usage)) / \(formatBytes(limit))"
        }
        return formatBytes(usage)
    }

    private var ioDisplay: String {
        let rx = formatBytes(entry.networkRxBytes ?? 0)
        let tx = formatBytes(entry.networkTxBytes ?? 0)
        return "Net \(rx) in · \(tx) out"
    }
}

#if DEBUG
#Preview {
    DashboardView()
        .environmentObject(AppModel.preview)
        .frame(width: 980, height: 720)
}
#endif
