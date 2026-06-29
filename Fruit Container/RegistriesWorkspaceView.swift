import SwiftUI

struct RegistriesWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var registries: [RegistryEntry] = []
    @State private var selection: RegistryEntry.ID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    var body: some View {
        VStack(spacing: 0) {
            ResourceHeader(title: "Registries", subtitle: "\(registries.count) authenticated sessions", searchText: .constant(""))
            Divider()
            if isLoading && registries.isEmpty {
                ProgressView("Loading registries...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if registries.isEmpty {
                ContentUnavailableView("No Registry Sessions", systemImage: "externaldrive.badge.wifi", description: Text("Login to a registry when a pull or push requires credentials."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(registries, selection: $selection) {
                    TableColumn("Hostname") { Text($0.hostname).lineLimit(1) }
                    TableColumn("Username") { Text($0.username.isEmpty ? "-" : $0.username).foregroundStyle($0.username.isEmpty ? .secondary : .primary) }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
            if let errorMessage {
                FeedbackBar(message: errorMessage, isError: true)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingLogin = true } label: { Label("Login", systemImage: "plus") }
                Button { logoutSelected() } label: { Label("Logout", systemImage: "rectangle.portrait.and.arrow.right") }.disabled(selection == nil)
            }
        }
        .sheet(isPresented: $showingLogin) {
            RegistryLoginSheet { server, username, password in
                enqueueRegistryAction(title: "Login \(server)", command: "container registry login \(server)") {
                    try await containerCLIAdapter.loginRegistry(
                        server: server,
                        username: username.nilIfEmpty,
                        password: password.nilIfEmpty,
                        usePasswordStdin: password.nilIfEmpty != nil
                    )
                }
            }
        }
        .task {
            if appModel.cachedRegistryItems.isEmpty {
                await reload()
            } else {
                syncRegistriesFromCache()
            }
        }
        .onChange(of: appModel.registriesRefreshRevision) { _, _ in
            syncRegistriesFromCache()
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let output = try await containerCLIAdapter.listRegistries(format: "json")
            registries = RegistryEntry.parse(output)
            appModel.cachedRegistryItems = registries
            appModel.registrySessionCount = registries.count
            appModel.bumpRefreshRevision(for: .registries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncRegistriesFromCache() {
        registries = appModel.cachedRegistryItems
        if let selection, !registries.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    private func logoutSelected() {
        guard let selected = selection, let entry = registries.first(where: { $0.id == selected }) else { return }
        enqueueRegistryAction(title: "Logout \(entry.hostname)", command: "container registry logout \(entry.hostname)") {
            try await containerCLIAdapter.logoutRegistry(registry: entry.hostname)
        }
    }

    private func enqueueRegistryAction(title: String, command: String, operation: @escaping @Sendable () async throws -> Void) {
        _ = appModel.enqueueActivity(title: title, section: .registries, kind: .image, commandDescription: command) { _ in
            try await operation()
            return ActivityOperationOutcome(summary: "Completed.")
        }
    }
}

// MARK: - Registry model

struct RegistryEntry: Identifiable, Hashable {
    let id: String
    let hostname: String
    let username: String

    static func parse(_ output: String) -> [RegistryEntry] {
        guard let data = output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return rows.compactMap { row in
            let normalized = Dictionary(uniqueKeysWithValues: row.map { ($0.key.lowercased(), $0.value) })
            let host = (normalized["hostname"] ?? normalized["server"] ?? normalized["registry"] ?? normalized["host"]) as? String
            guard let host, !host.isEmpty else { return nil }
            let username = (normalized["username"] ?? normalized["user"]) as? String ?? ""
            return RegistryEntry(id: host, hostname: host, username: username)
        }
    }
}

// MARK: - Registry Login Sheet

private struct RegistryLoginSheet: View {
    let onLogin: (_ server: String, _ username: String, _ password: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Registry server", text: $server)
                TextField("Username", text: $username)
                SecureField("Password or token", text: $password)
            }
            .formStyle(.grouped)
            .navigationTitle("Registry Login")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Login") {
                        onLogin(server, username, password)
                        dismiss()
                    }
                    .disabled(server.nilIfEmpty == nil)
                }
            }
        }
        .frame(width: 460, height: 260)
    }
}

#if DEBUG
#Preview {
    RegistriesWorkspaceView()
        .environmentObject(AppModel.preview)
        .frame(width: 900, height: 560)
}
#endif
