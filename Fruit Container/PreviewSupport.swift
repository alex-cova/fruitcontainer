#if DEBUG
import Foundation

// MARK: - Sample domain data for SwiftUI previews

extension ContainerSummary {
    static let previewSamples: [ContainerSummary] = [
        ContainerSummary(name: "web-frontend", imageName: "nginx:latest", state: .running),
        ContainerSummary(name: "api-server", imageName: "ghcr.io/acme/api:1.4.2", state: .running),
        ContainerSummary(name: "postgres", imageName: "postgres:16", state: .stopped),
        ContainerSummary(name: "redis-cache", imageName: "redis:7", state: .exited),
    ]
}

extension ImageSummary {
    static let previewSamples: [ImageSummary] = [
        ImageSummary(reference: "nginx:latest", sizeBytes: 187_000_000),
        ImageSummary(reference: "postgres:16", sizeBytes: 425_000_000),
        ImageSummary(reference: "ghcr.io/acme/api:1.4.2", sizeBytes: 96_500_000),
    ]
}

extension NetworkSummary {
    static let previewSamples: [NetworkSummary] = [
        NetworkSummary(name: "bridge", driver: "bridge", attachedContainerCount: 3),
        NetworkSummary(name: "internal", driver: "bridge", attachedContainerCount: 1),
        NetworkSummary(name: "host", driver: "host", attachedContainerCount: 0),
    ]
}

extension VolumeSummary {
    static let previewSamples: [VolumeSummary] = [
        VolumeSummary(name: "pgdata", mountpoint: "/var/lib/containers/volumes/pgdata", attachedContainerCount: 1),
        VolumeSummary(name: "cache", mountpoint: "/var/lib/containers/volumes/cache", attachedContainerCount: 0),
    ]
}

extension ActivityRecord {
    static let previewSamples: [ActivityRecord] = [
        ActivityRecord(
            title: "Run nginx:latest",
            commandDescription: "container run -d --name web-frontend nginx:latest",
            section: .containers,
            kind: .container,
            status: .succeeded,
            startedAt: .now.addingTimeInterval(-120),
            finishedAt: .now.addingTimeInterval(-118),
            summary: "Container started."
        ),
        ActivityRecord(
            title: "Pull postgres:16",
            commandDescription: "container image pull postgres:16",
            section: .images,
            kind: .image,
            status: .running,
            startedAt: .now.addingTimeInterval(-5)
        ),
        ActivityRecord(
            title: "Remove redis-cache",
            commandDescription: "container rm redis-cache",
            section: .containers,
            kind: .container,
            status: .failed,
            startedAt: .now.addingTimeInterval(-60),
            finishedAt: .now.addingTimeInterval(-59),
            errorMessage: "Container is still running."
        ),
    ]
}

extension ContainerMetricsEntry {
    static let previewSamples: [ContainerMetricsEntry] = [
        ContainerMetricsEntry(
            id: "web-frontend",
            containerID: "web-frontend",
            containerName: "web-frontend",
            cpuUsagePercent: 12.4,
            memoryUsageBytes: 128_000_000,
            memoryLimitBytes: 512_000_000,
            networkRxBytes: 4_200_000,
            networkTxBytes: 1_100_000,
            blockReadBytes: 900_000,
            blockWriteBytes: 350_000,
            processCount: 8,
            capturedAt: .now
        ),
        ContainerMetricsEntry(
            id: "api-server",
            containerID: "api-server",
            containerName: "api-server",
            cpuUsagePercent: 43.7,
            memoryUsageBytes: 256_000_000,
            memoryLimitBytes: 1_024_000_000,
            networkRxBytes: 12_500_000,
            networkTxBytes: 8_900_000,
            blockReadBytes: 2_400_000,
            blockWriteBytes: 1_700_000,
            processCount: 21,
            capturedAt: .now
        ),
    ]
}

extension ContainerMetricsHistoryPoint {
    static let previewSamples: [ContainerMetricsHistoryPoint] = (0..<20).map { index in
        let captured = Date.now.addingTimeInterval(Double(index - 20) * 3)
        return ContainerMetricsHistoryPoint(
            capturedAt: captured,
            totalCPUUsagePercent: 30 + Double((index * 7) % 40),
            totalMemoryUsageBytes: Int64(300_000_000 + (index % 6) * 25_000_000),
            totalMemoryLimitBytes: 1_536_000_000,
            containerCount: 2
        )
    }
}

@MainActor
extension AppModel {
    /// A fully populated model for previews. Activities are passed explicitly so
    /// the initializer does not read the on-disk activity log.
    static var preview: AppModel {
        AppModel(
            containers: ContainerSummary.previewSamples,
            images: ImageSummary.previewSamples,
            networks: NetworkSummary.previewSamples,
            volumes: VolumeSummary.previewSamples,
            registrySessionCount: 2,
            activities: ActivityRecord.previewSamples,
            containerMetrics: ContainerMetricsEntry.previewSamples,
            containerMetricsHistory: ContainerMetricsHistoryPoint.previewSamples,
            containerMetricsUpdatedAt: .now
        )
    }

    /// An empty model, useful for previewing empty/onboarding states.
    static var previewEmpty: AppModel {
        AppModel(activities: [])
    }
}
#endif
