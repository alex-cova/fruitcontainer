import Foundation

@MainActor
final class AppRefreshController {
    private let appModel: AppModel
    private let containerCLIAdapter: ContainerCLIAdapter

    private var refreshTask: Task<Void, Never>?

    init(appModel: AppModel, containerCLIAdapter: ContainerCLIAdapter) {
        self.appModel = appModel
        self.containerCLIAdapter = containerCLIAdapter
    }

    func startIfNeeded() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAll()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: RefreshInterval.uiRefresh)
                guard !Task.isCancelled else { return }
                await self.refreshAll()
            }
        }
    }

    private func refreshAll() async {
        async let containersResult = try? containerCLIAdapter.listContainers()
        async let imagesResult = try? containerCLIAdapter.listImages()
        async let networksResult = try? containerCLIAdapter.listNetworks()
        async let volumesResult = try? containerCLIAdapter.listVolumes()
        async let registriesResult = try? containerCLIAdapter.listRegistries(format: "json", quiet: false)
        async let relationshipScan = containerCLIAdapter.scanResourceRelationships()
        async let systemHealthSnapshot = containerCLIAdapter.collectSystemHealthSnapshot()
        async let containerMetricsResult = try? containerCLIAdapter.fetchContainerStats()

        let (containers, images, networks, volumes, registries, scan, snapshot, metrics) = await (
            containersResult,
            imagesResult,
            networksResult,
            volumesResult,
            registriesResult,
            relationshipScan,
            systemHealthSnapshot,
            containerMetricsResult
        )
        if let containers {
            if case .parsed(let value, _) = containers {
                appModel.cachedContainerItems = value
                appModel.bumpRefreshRevision(for: .containers)
            }
            appModel.updateContainerSummary(from: containers)
        }

        if let images {
            if case .parsed(let value, _) = images {
                appModel.cachedImageItems = value
                appModel.bumpRefreshRevision(for: .images)
            }
            appModel.updateImageSummary(from: images)
        }

        if let networks {
            if case .parsed(let value, _) = networks {
                appModel.cachedNetworkItems = value
                appModel.bumpRefreshRevision(for: .networks)
            }
            appModel.updateNetworkSummary(from: networks, relationships: scan.hints)
        }

        if let volumes {
            if case .parsed(let value, _) = volumes {
                appModel.cachedVolumeItems = value
                appModel.bumpRefreshRevision(for: .volumes)
            }
            appModel.updateVolumeSummary(from: volumes, relationships: scan.hints)
        }

        if let registries {
            let registryItems = RegistryEntry.parse(registries)
            appModel.cachedRegistryItems = registryItems
            appModel.registrySessionCount = registryItems.count
            appModel.bumpRefreshRevision(for: .registries)
        }

        if networks == nil, !appModel.cachedNetworkItems.isEmpty {
            appModel.updateNetworks(from: appModel.cachedNetworkItems, relationships: scan.hints)
            appModel.bumpRefreshRevision(for: .networks)
        }

        if volumes == nil, !appModel.cachedVolumeItems.isEmpty {
            appModel.updateVolumes(from: appModel.cachedVolumeItems, relationships: scan.hints)
            appModel.bumpRefreshRevision(for: .volumes)
        }

        appModel.latestSystemHealthSnapshot = snapshot
        appModel.latestSystemHealthUpdatedAt = .now
        appModel.bumpRefreshRevision(for: .system)

        if let samples = metrics {
            appModel.updateContainerMetrics(from: samples)
        } else {
            appModel.clearContainerMetrics()
        }
    }
}

private enum RefreshInterval {
    static let uiRefresh: UInt64 = 3_000_000_000
}
