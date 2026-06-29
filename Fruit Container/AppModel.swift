import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSidebarSection: SidebarSection?
    @Published var selectedFruitSection: FruitSection?
    @Published var containers: [ContainerSummary]
    @Published var images: [ImageSummary]
    @Published var networks: [NetworkSummary]
    @Published var volumes: [VolumeSummary]
    @Published var registrySessionCount: Int
    @Published var activities: [ActivityRecord]
    @Published var latestDiagnosticsBundlePath: String?
    @Published var latestDiagnosticsSummary: String?
    @Published var latestDiagnosticsUpdatedAt: Date?
    @Published var latestSystemHealthSnapshot: SystemHealthSnapshot?
    @Published var latestSystemHealthUpdatedAt: Date?
    @Published var containerMetrics: [ContainerMetricsEntry]
    @Published var containerMetricsHistory: [ContainerMetricsHistoryPoint]
    @Published var containerMetricsUpdatedAt: Date?
    @Published var commandCapabilities = CommandCapabilitySnapshot()
    @Published var cachedRegistryItems: [RegistryEntry]
    var cachedContainerItems: [ContainerListItem]
    var cachedImageItems: [ImageListItem]
    var cachedNetworkItems: [NetworkListItem]
    var cachedVolumeItems: [VolumeListItem]

    @Published var systemRefreshRevision = 0
    @Published var containersRefreshRevision = 0
    @Published var imagesRefreshRevision = 0
    @Published var registriesRefreshRevision = 0
    @Published var networksRefreshRevision = 0
    @Published var volumesRefreshRevision = 0
    @Published var activityRefreshRevision = 0
    @Published var diagnosticsRefreshRevision = 0

    private var registeredActivityActions: [UUID: RegisteredActivityAction] = [:]
    private var pendingActivityIDs: [UUID] = []
    private var runningActivityID: UUID?
    private var runningActivityTask: Task<Void, Never>?
    private var previousContainerStatsByID: [String: ContainerStatsSample] = [:]
    private var cancellables: Set<AnyCancellable> = []

    private let maximumContainerMetricsHistoryPoints = 40

    init(
        selectedSidebarSection: SidebarSection? = .home,
        selectedFruitSection: FruitSection? = .dashboard,
        containers: [ContainerSummary] = [],
        images: [ImageSummary] = [],
        networks: [NetworkSummary] = [],
        volumes: [VolumeSummary] = [],
        registrySessionCount: Int = 0,
        activities: [ActivityRecord] = [],
        containerMetrics: [ContainerMetricsEntry] = [],
        containerMetricsHistory: [ContainerMetricsHistoryPoint] = [],
        containerMetricsUpdatedAt: Date? = nil,
        cachedContainerItems: [ContainerListItem] = [],
        cachedImageItems: [ImageListItem] = [],
        cachedRegistryItems: [RegistryEntry] = [],
        cachedNetworkItems: [NetworkListItem] = [],
        cachedVolumeItems: [VolumeListItem] = []
    ) {
        self.selectedSidebarSection = selectedSidebarSection
        self.selectedFruitSection = selectedFruitSection
        self.containers = containers
        self.images = images
        self.networks = networks
        self.volumes = volumes
        self.registrySessionCount = registrySessionCount
        if activities.isEmpty {
            self.activities = AppModel.reconcileLoadedActivities(ActivityLogStore.load())
        } else {
            self.activities = activities
        }
        self.containerMetrics = containerMetrics
        self.containerMetricsHistory = containerMetricsHistory
        self.containerMetricsUpdatedAt = containerMetricsUpdatedAt
        self.cachedContainerItems = cachedContainerItems
        self.cachedImageItems = cachedImageItems
        self.cachedRegistryItems = cachedRegistryItems
        self.cachedNetworkItems = cachedNetworkItems
        self.cachedVolumeItems = cachedVolumeItems

        $activities
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { records in
                ActivityLogStore.save(records)
            }
            .store(in: &cancellables)
    }

    /// Records loaded from disk belong to a previous process whose execution
    /// closures no longer exist. Any that were still active (queued/running)
    /// can never resume, so normalize them to canceled with an explanatory note
    /// to keep the queue state machine and sidebar active-count badge correct.
    private static func reconcileLoadedActivities(_ records: [ActivityRecord]) -> [ActivityRecord] {
        records.map { record in
            guard record.status.isActive else { return record }
            var reconciled = record
            reconciled.status = .canceled
            reconciled.finishedAt = reconciled.finishedAt ?? .now
            reconciled.errorMessage = "Interrupted by app restart."
            return reconciled
        }
    }

    func badgeCount(for section: SidebarSection) -> Int {
        switch section {
        case .home:
            0
        case .system:
            0
        case .containers:
            containers.count
        case .images:
            images.count
        case .registries:
            registrySessionCount
        case .networks:
            networks.count
        case .volumes:
            volumes.count
        case .activity:
            activities.filter { $0.status.isActive }.count
        case .diagnostics:
            activities.filter { $0.section == .diagnostics && $0.status.isActive }.count
        }
    }

    func updateContainers(from items: [ContainerListItem]) {
        var existingByName: [String: ContainerSummary] = [:]
        for item in containers {
            existingByName[item.name] = item
        }
        containers = items.map { item in
            let existing = existingByName[item.name]
            return ContainerSummary(
                id: existing?.id ?? UUID(),
                name: item.name,
                imageName: item.image ?? "Unknown image",
                state: ContainerState(cliState: item.state),
                createdAt: existing?.createdAt ?? .now
            )
        }
    }

    func updateContainerSummary(from result: NonCriticalDecodeResult<[ContainerListItem]>) {
        switch result {
        case .parsed(let value, _):
            updateContainers(from: value)
        case .raw:
            break
        }
    }

    func updateImages(from items: [ImageListItem]) {
        var existingByReference: [String: ImageSummary] = [:]
        for item in images {
            existingByReference[item.reference] = item
        }
        images = items.map { item in
            let existing = existingByReference[item.reference]
            return ImageSummary(
                id: existing?.id ?? UUID(),
                reference: item.reference,
                sizeBytes: existing?.sizeBytes ?? 0
            )
        }
    }

    func updateImageSummary(from result: NonCriticalDecodeResult<[ImageListItem]>) {
        switch result {
        case .parsed(let value, _):
            updateImages(from: value)
        case .raw:
            break
        }
    }

    func updateNetworks(from items: [NetworkListItem], relationships: [ResourceRelationshipHint] = []) {
        var existingByName: [String: NetworkSummary] = [:]
        for item in networks {
            existingByName[item.name] = item
        }
        var attachedContainerIDs: [String: Set<String>] = [:]
        for hint in relationships {
            for networkName in hint.networks {
                attachedContainerIDs[networkName, default: []].insert(hint.containerID)
            }
        }

        networks = items.map { item in
            let existing = existingByName[item.name]
            return NetworkSummary(
                id: existing?.id ?? UUID(),
                name: item.name,
                driver: item.plugin ?? item.mode ?? "Unknown",
                attachedContainerCount: attachedContainerIDs[item.name, default: []].count
            )
        }
    }

    func updateNetworkSummary(
        from result: NonCriticalDecodeResult<[NetworkListItem]>,
        relationships: [ResourceRelationshipHint]
    ) {
        switch result {
        case .parsed(let value, _):
            updateNetworks(from: value, relationships: relationships)
        case .raw:
            break
        }
    }

    func updateVolumes(from items: [VolumeListItem], relationships: [ResourceRelationshipHint] = []) {
        var existingByName: [String: VolumeSummary] = [:]
        for item in volumes {
            existingByName[item.name] = item
        }
        var attachedContainerIDs: [String: Set<String>] = [:]
        for hint in relationships {
            for volume in hint.volumeMounts {
                attachedContainerIDs[volume.name, default: []].insert(hint.containerID)
            }
        }

        volumes = items.map { item in
            let existing = existingByName[item.name]
            return VolumeSummary(
                id: existing?.id ?? UUID(),
                name: item.name,
                mountpoint: item.source ?? existing?.mountpoint ?? "",
                attachedContainerCount: attachedContainerIDs[item.name, default: []].count
            )
        }
    }

    func updateVolumeSummary(
        from result: NonCriticalDecodeResult<[VolumeListItem]>,
        relationships: [ResourceRelationshipHint]
    ) {
        switch result {
        case .parsed(let value, _):
            updateVolumes(from: value, relationships: relationships)
        case .raw:
            break
        }
    }

    func updateContainerMetrics(from samples: [ContainerStatsSample]) {
        guard !samples.isEmpty else {
            clearContainerMetrics()
            return
        }

        let namesByID = Dictionary(uniqueKeysWithValues: cachedContainerItems.map { ($0.id, $0.name) })
        let capturedAt = samples.map(\.capturedAt).max() ?? .now

        let unsortedEntries: [ContainerMetricsEntry] = samples.map { sample in
                let previous = previousContainerStatsByID[sample.containerID]
                return ContainerMetricsEntry(
                    id: sample.containerID,
                    containerID: sample.containerID,
                    containerName: namesByID[sample.containerID] ?? sample.containerID,
                    cpuUsagePercent: cpuUsagePercent(for: sample, previous: previous),
                    memoryUsageBytes: sample.memoryUsageBytes,
                    memoryLimitBytes: sample.memoryLimitBytes,
                    networkRxBytes: sample.networkRxBytes,
                    networkTxBytes: sample.networkTxBytes,
                    blockReadBytes: sample.blockReadBytes,
                    blockWriteBytes: sample.blockWriteBytes,
                    processCount: sample.processCount,
                    capturedAt: sample.capturedAt
                )
            }
        let entries = unsortedEntries.sorted { lhs, rhs in
            lhs.containerName.localizedStandardCompare(rhs.containerName) == .orderedAscending
        }

        previousContainerStatsByID = Dictionary(uniqueKeysWithValues: samples.map { ($0.containerID, $0) })
        containerMetrics = entries
        containerMetricsUpdatedAt = capturedAt

        let totalCPU = entries.reduce(0) { $0 + ($1.cpuUsagePercent ?? 0) }
        let totalMemory = entries.reduce(Int64(0)) { $0 + ($1.memoryUsageBytes ?? 0) }
        let totalMemoryLimit = entries.reduce(Int64(0)) { $0 + ($1.memoryLimitBytes ?? 0) }

        containerMetricsHistory.append(
            ContainerMetricsHistoryPoint(
                capturedAt: capturedAt,
                totalCPUUsagePercent: totalCPU,
                totalMemoryUsageBytes: totalMemory,
                totalMemoryLimitBytes: totalMemoryLimit,
                containerCount: entries.count
            )
        )
        if containerMetricsHistory.count > maximumContainerMetricsHistoryPoints {
            containerMetricsHistory.removeFirst(containerMetricsHistory.count - maximumContainerMetricsHistoryPoints)
        }
    }

    func clearContainerMetrics() {
        containerMetrics = []
        containerMetricsHistory = []
        containerMetricsUpdatedAt = nil
        previousContainerStatsByID = [:]
    }

    func enqueueActivity(
        title: String,
        section: SidebarSection,
        kind: ActivityOperationKind,
        commandDescription: String,
        isRetryable: Bool = true,
        retrySourceID: UUID? = nil,
        execute: @escaping @Sendable (_ activityID: UUID) async throws -> ActivityOperationOutcome
    ) -> UUID {
        let id = UUID()
        let record = ActivityRecord(
            id: id,
            retrySourceID: retrySourceID,
            title: title,
            commandDescription: commandDescription,
            section: section,
            kind: kind,
            isRetryable: isRetryable
        )
        activities.insert(record, at: 0)
        registeredActivityActions[id] = RegisteredActivityAction(
            title: title,
            section: section,
            kind: kind,
            commandDescription: commandDescription,
            isRetryable: isRetryable,
            execute: execute
        )
        pendingActivityIDs.append(id)
        bumpRefreshRevision(for: .activity)
        scheduleNextActivityIfNeeded()
        return id
    }

    func appendActivityOutput(id: UUID, chunk: String, maxCharacters: Int = 120_000) {
        guard let index = activityIndex(for: id), !chunk.isEmpty else { return }
        activities[index].outputLog.append(chunk)
        if activities[index].outputLog.count > maxCharacters {
            activities[index].outputLog = String(activities[index].outputLog.suffix(maxCharacters))
        }
    }

    func retryActivity(_ id: UUID) {
        guard canRetryActivity(id) else { return }
        guard let existing = activities.first(where: { $0.id == id }) else { return }
        guard let registration = registeredActivityActions[id] else { return }

        _ = enqueueActivity(
            title: "Retry \(existing.title)",
            section: registration.section,
            kind: registration.kind,
            commandDescription: registration.commandDescription,
            isRetryable: registration.isRetryable,
            retrySourceID: id,
            execute: registration.execute
        )
    }

    func canRetryActivity(_ id: UUID) -> Bool {
        guard let activity = activities.first(where: { $0.id == id }) else { return false }
        return activity.canRetry && registeredActivityActions[id] != nil
    }

    func cancelActivity(id: UUID) {
        if runningActivityID == id {
            runningActivityTask?.cancel()
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard self.runningActivityID == id else { return }
                self.appendActivityOutput(id: id, chunk: "\nOperation cancelled.\n")
                self.finishActivity(
                    id: id,
                    status: .canceled,
                    summary: nil,
                    errorMessage: "Operation cancelled."
                )
                self.activityDidExit(id: id)
            }
            return
        }

        guard let queueIndex = pendingActivityIDs.firstIndex(of: id) else { return }
        pendingActivityIDs.remove(at: queueIndex)
        finishActivity(
            id: id,
            status: .canceled,
            summary: "Canceled before execution.",
            errorMessage: nil
        )
    }

    func cancelLatestActiveActivity(in section: SidebarSection) {
        guard let activity = activities.first(where: { $0.section == section && $0.status.isActive }) else { return }
        cancelActivity(id: activity.id)
    }

    func clearCompletedActivities() {
        let removableIDs = Set(activities.filter { !$0.status.isActive }.map(\.id))
        activities.removeAll { removableIDs.contains($0.id) }
        for id in removableIDs {
            registeredActivityActions.removeValue(forKey: id)
        }
        bumpRefreshRevision(for: .activity)
    }

    func hasActiveActivity(for section: SidebarSection) -> Bool {
        activities.contains { $0.section == section && $0.status.isActive }
    }

    func activeActivityCount(for section: SidebarSection) -> Int {
        activities.filter { $0.section == section && $0.status.isActive }.count
    }

    func latestActivity(for section: SidebarSection) -> ActivityRecord? {
        activities.first { $0.section == section }
    }

    func makeDiagnosticsOperationSnapshot(
        maxActivities: Int = 40
    ) -> DiagnosticsOperationSnapshot {
        DiagnosticsOperationSnapshot(
            activities: Array(activities.prefix(maxActivities))
        )
    }

    func recordDiagnosticsSummary(_ summary: String) {
        latestDiagnosticsSummary = summary
        latestDiagnosticsUpdatedAt = .now
        bumpRefreshRevision(for: .diagnostics)
    }

    func recordDiagnosticsBundleExport(path: String, summary: String) {
        latestDiagnosticsBundlePath = path
        latestDiagnosticsSummary = summary
        latestDiagnosticsUpdatedAt = .now
        bumpRefreshRevision(for: .diagnostics)
    }

    func refreshRevision(for section: SidebarSection) -> Int {
        switch section {
        case .home:
            systemRefreshRevision
        case .system:
            systemRefreshRevision
        case .containers:
            containersRefreshRevision
        case .images:
            imagesRefreshRevision
        case .registries:
            registriesRefreshRevision
        case .networks:
            networksRefreshRevision
        case .volumes:
            volumesRefreshRevision
        case .activity:
            activityRefreshRevision
        case .diagnostics:
            diagnosticsRefreshRevision
        }
    }

    func bumpRefreshRevision(for section: SidebarSection) {
        switch section {
        case .home:
            systemRefreshRevision += 1
        case .system:
            systemRefreshRevision += 1
        case .containers:
            containersRefreshRevision += 1
        case .images:
            imagesRefreshRevision += 1
        case .registries:
            registriesRefreshRevision += 1
        case .networks:
            networksRefreshRevision += 1
        case .volumes:
            volumesRefreshRevision += 1
        case .activity:
            activityRefreshRevision += 1
        case .diagnostics:
            diagnosticsRefreshRevision += 1
        }
    }

    func summary(for section: SidebarSection) -> [String] {
        switch section {
        case .home:
            return [
                "Containers: \(containers.count)",
                "Images: \(images.count)",
                "Networks: \(networks.count)",
                "Volumes: \(volumes.count)",
            ]
        case .system:
            return [
                "App shell initialized with sidebar/main/detail layout.",
                "Global command runner supports cancellation and timeout.",
                "Unified command errors are standardized as AppError.",
            ]
        case .containers:
            return ["Total containers: \(containers.count)"]
        case .images:
            return ["Total images: \(images.count)"]
        case .registries:
            return [
                "Registry sessions logged in: \(registrySessionCount)",
                "Active registry operations: \(activities.filter { $0.section == .registries && $0.status.isActive }.count)",
                "Completed registry operations this session: \(activities.filter { $0.section == .registries && !$0.status.isActive }.count)",
            ]
        case .networks:
            return [
                "Total networks: \(networks.count)",
                "Networks with container attachments: \(networks.filter { $0.attachedContainerCount > 0 }.count)",
            ]
        case .volumes:
            return [
                "Total volumes: \(volumes.count)",
                "Volumes referenced by containers: \(volumes.filter { $0.attachedContainerCount > 0 }.count)",
            ]
        case .activity:
            return [
                "Queued or running operations: \(activities.filter { $0.status.isActive }.count)",
                "Failed operations this session: \(activities.filter { $0.status == .failed }.count)",
                "Completed operations this session: \(activities.filter { !$0.status.isActive }.count)",
            ]
        case .diagnostics:
            var rows = [
                "Active diagnostics jobs: \(activities.filter { $0.section == .diagnostics && $0.status.isActive }.count)"
            ]
            if let latestDiagnosticsBundlePath {
                rows.append("Last support bundle: \((latestDiagnosticsBundlePath as NSString).lastPathComponent)")
            } else {
                rows.append("Last support bundle: none exported")
            }
            if let latestDiagnosticsUpdatedAt {
                rows.append(
                    "Last diagnostics update: \(latestDiagnosticsUpdatedAt.formatted(date: .abbreviated, time: .shortened))"
                )
            }
            return rows
        }
    }

    private func scheduleNextActivityIfNeeded() {
        guard runningActivityTask == nil else { return }
        guard !pendingActivityIDs.isEmpty else { return }

        var nextID: UUID?
        var registration: RegisteredActivityAction?

        while !pendingActivityIDs.isEmpty, registration == nil {
            let candidate = pendingActivityIDs.removeFirst()
            if let action = registeredActivityActions[candidate] {
                nextID = candidate
                registration = action
            }
        }

        guard let nextID, let registration else { return }

        runningActivityID = nextID
        markActivityRunning(id: nextID)

        runningActivityTask = Task { [registration] in
            do {
                let outcome = try await registration.execute(nextID)
                guard self.runningActivityID == nextID else { return }
                self.finishActivity(
                    id: nextID,
                    status: .succeeded,
                    summary: outcome.summary,
                    errorMessage: nil
                )
            } catch let error as AppError {
                guard self.runningActivityID == nextID else { return }
                let status: ActivityOperationStatus
                switch error {
                case .commandCancelled:
                    status = .canceled
                default:
                    status = .failed
                }
                self.appendActivityOutput(id: nextID, chunk: "\n\(error.localizedDescription)\n")
                self.finishActivity(
                    id: nextID,
                    status: status,
                    summary: nil,
                    errorMessage: error.localizedDescription
                )
            } catch is CancellationError {
                guard self.runningActivityID == nextID else { return }
                self.appendActivityOutput(id: nextID, chunk: "\nOperation cancelled.\n")
                self.finishActivity(
                    id: nextID,
                    status: .canceled,
                    summary: nil,
                    errorMessage: "Operation cancelled."
                )
            } catch {
                guard self.runningActivityID == nextID else { return }
                self.appendActivityOutput(id: nextID, chunk: "\n\(error.localizedDescription)\n")
                self.finishActivity(
                    id: nextID,
                    status: .failed,
                    summary: nil,
                    errorMessage: error.localizedDescription
                )
            }

            if self.runningActivityID == nextID {
                self.activityDidExit(id: nextID)
            }
        }
    }

    private func markActivityRunning(id: UUID) {
        guard let index = activityIndex(for: id) else { return }
        activities[index].status = .running
        activities[index].startedAt = .now
        activities[index].finishedAt = nil
        activities[index].summary = nil
        activities[index].errorMessage = nil
        bumpRefreshRevision(for: .activity)
    }

    private func finishActivity(
        id: UUID,
        status: ActivityOperationStatus,
        summary: String?,
        errorMessage: String?
    ) {
        guard let index = activityIndex(for: id) else { return }
        activities[index].status = status
        activities[index].finishedAt = .now
        activities[index].summary = summary
        activities[index].errorMessage = errorMessage
        if status == .succeeded {
            activities[index].errorMessage = nil
        }
        bumpRefreshRevision(for: .activity)
    }

    private func activityDidExit(id: UUID) {
        runningActivityID = nil
        runningActivityTask = nil

        if let activity = activities.first(where: { $0.id == id }), !activity.canRetry {
            registeredActivityActions.removeValue(forKey: id)
        }

        scheduleNextActivityIfNeeded()
    }

    private func cpuUsagePercent(
        for current: ContainerStatsSample,
        previous: ContainerStatsSample?
    ) -> Double? {
        guard
            let previous,
            let currentCPUUsage = current.cpuUsageUsec,
            let previousCPUUsage = previous.cpuUsageUsec
        else {
            return nil
        }

        let elapsedUsec = current.capturedAt.timeIntervalSince(previous.capturedAt) * 1_000_000
        let deltaCPUUsage = Double(currentCPUUsage - previousCPUUsage)
        guard elapsedUsec > 0, deltaCPUUsage >= 0 else { return nil }
        return (deltaCPUUsage / elapsedUsec) * 100
    }

    private func activityIndex(for id: UUID) -> Int? {
        activities.firstIndex(where: { $0.id == id })
    }
}

private struct RegisteredActivityAction {
    let title: String
    let section: SidebarSection
    let kind: ActivityOperationKind
    let commandDescription: String
    let isRetryable: Bool
    let execute: @Sendable (_ activityID: UUID) async throws -> ActivityOperationOutcome
}
