import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    let updater: any AppUpdaterProviding
    @AppStorage(.showSidebarBadgesKey) private var showSidebarBadges = true

    var body: some View {
        NavigationSplitView {
            List(FruitSection.allCases, selection: $appModel.selectedFruitSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .badge(badge(for: section))
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Fruit Container")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            Group {
                switch appModel.selectedFruitSection ?? .dashboard {
                case .dashboard:
                    DashboardView()
                case .containers:
                    ContainersWorkspaceView()
                case .images:
                    ImagesWorkspaceView()
                case .registries:
                    RegistriesWorkspaceView()
                case .networks:
                    NetworksWorkspaceView()
                case .volumes:
                    VolumesWorkspaceView()
                case .activity:
                    ActivityWorkspaceView()
                case .settings:
                    SettingsWorkspaceView(updater: updater)
                }
            }
            .navigationTitle((appModel.selectedFruitSection ?? .dashboard).title)
            .background(FruitTheme.pageBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .background(FruitTheme.pageBackground)
    }

    private func badge(for section: FruitSection) -> Int {
        guard showSidebarBadges else { return 0 }

        return switch section {
        case .dashboard, .settings:
            0
        case .containers:
            appModel.containers.count
        case .images:
            appModel.images.count
        case .registries:
            appModel.registrySessionCount
        case .networks:
            appModel.networks.count
        case .volumes:
            appModel.volumes.count
        case .activity:
            appModel.activities.filter(\.status.isActive).count
        }
    }
}

enum FruitSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case dashboard
    case containers
    case images
    case registries
    case networks
    case volumes
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .containers: "Containers"
        case .images: "Images"
        case .registries: "Registries"
        case .networks: "Networks"
        case .volumes: "Volumes"
        case .activity: "Logs"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .containers: "truck.box"
        case .images: "photo.stack"
        case .registries: "externaldrive.badge.wifi"
        case .networks: "network"
        case .volumes: "internaldrive"
        case .activity: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

enum FruitTheme {
    static let pageBackground = Color(nsColor: .textBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let hairline = Color(nsColor: .separatorColor).opacity(0.55)
    static let selectedFill = Color.accentColor.opacity(0.12)
    static let cornerRadius: CGFloat = 12
    static let cardFill = AnyShapeStyle(.quaternary)
    static let chromeFill = AnyShapeStyle(.bar)
}

#if DEBUG
#Preview {
    ContentView(updater: DisabledAppUpdater())
        .environmentObject(AppModel.preview)
        .frame(width: 1100, height: 720)
}
#endif
