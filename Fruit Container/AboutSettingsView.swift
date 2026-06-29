import SwiftUI

@MainActor
struct AboutSettingsView: View {
    let updater: any AppUpdaterProviding
    @AppStorage(.autoUpdateEnabledKey) private var autoUpdateEnabled = true
    @State private var hasSyncedUpdaterPreference = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            applicationSummary

            Divider()

            updateSettings

            Divider()

            links
        }
        .onAppear(perform: syncUpdaterPreferenceIfNeeded)
        .onChange(of: autoUpdateEnabled) { _, newValue in
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    private var applicationSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(appName)
                    .font(.headline)

                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var updateSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Check for updates automatically", isOn: $autoUpdateEnabled)

            HStack(spacing: 10) {
                Button("Check for Updates...", action: checkForUpdates)
                    .disabled(!updater.isAvailable)

                if let availabilityDescription = updater.availabilityDescription {
                    Text(availabilityDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var links: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("Repository")
                    .foregroundStyle(.secondary)
                Link(repositoryURL.host() ?? repositoryURL.absoluteString, destination: repositoryURL)
            }

            GridRow {
                Text("Developer")
                    .foregroundStyle(.secondary)
                Link(developerWebsiteURL.host() ?? developerWebsiteURL.absoluteString, destination: developerWebsiteURL)
            }
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Fruit Container"
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/apple/container")!
    }

    private var developerWebsiteURL: URL {
        URL(string: "https://github.com/apple/container")!
    }

    private func syncUpdaterPreferenceIfNeeded() {
        guard !hasSyncedUpdaterPreference else { return }
        updater.automaticallyChecksForUpdates = autoUpdateEnabled
        hasSyncedUpdaterPreference = true
    }

    private func checkForUpdates() {
        updater.checkForUpdates()
    }
}

#if DEBUG
#Preview {
    AboutSettingsView(updater: DisabledAppUpdater())
        .padding()
        .frame(width: 460)
}
#endif
