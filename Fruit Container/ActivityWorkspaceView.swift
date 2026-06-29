import SwiftUI

struct ActivityWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selection = Set<UUID>()
    @State private var searchText = ""

    private var filteredActivities: [ActivityRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appModel.activities }
        return appModel.activities.filter { matches($0, query: query) }
    }

    private var headerSubtitle: String {
        let total = appModel.activities.count
        let failed = appModel.activities.filter { $0.status == .failed }.count
        var subtitle = "\(total) \(total == 1 ? "operation" : "operations")"
        if failed > 0 { subtitle += " · \(failed) failed" }
        return subtitle
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ResourceHeader(title: "Logs", subtitle: headerSubtitle, searchText: $searchText)
                Divider()
                if appModel.activities.isEmpty {
                    ContentUnavailableView("No Operations", systemImage: "clock.arrow.circlepath", description: Text("Command history, errors, and outputs appear here."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredActivities.isEmpty {
                    ContentUnavailableView("No Matching Log Entries", systemImage: "magnifyingglass", description: Text("No operations match “\(searchText)”."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(filteredActivities, selection: $selection) {
                        TableColumn("Operation") { activity in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.title).fontWeight(.medium).lineLimit(1)
                                Text(activity.commandDescription).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        TableColumn("Status") { activity in
                            StatusBadge(text: activity.status.rawValue.capitalized, color: color(for: activity.status))
                        }
                        TableColumn("Type") { activity in
                            Text(activity.kind.rawValue.capitalized).foregroundStyle(.secondary)
                        }
                        TableColumn("Section") { activity in
                            Text(activity.section.title).foregroundStyle(.secondary)
                        }
                        TableColumn("Logged") { activity in
                            Text(activity.queuedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minWidth: 560)
            activityInspector
                .frame(minWidth: 360, idealWidth: 440)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ControlGroup {
                    Button { if let id = selection.first { appModel.cancelActivity(id: id) } } label: { Label("Cancel", systemImage: "xmark") }
                        .disabled(selectedActivity?.status.isActive != true)
                    Button { if let id = selection.first { appModel.retryActivity(id) } } label: { Label("Retry", systemImage: "arrow.clockwise") }
                        .disabled(selection.first.map { !appModel.canRetryActivity($0) } ?? true)
                }

                Button(role: .destructive) { appModel.clearCompletedActivities() } label: { Label("Clear Finished", systemImage: "xmark.bin") }
                    .disabled(!appModel.activities.contains { !$0.status.isActive })
            }
        }
    }

    private var selectedActivity: ActivityRecord? {
        guard let id = selection.first, selection.count == 1 else { return nil }
        return appModel.activities.first { $0.id == id }
    }

    private var activityInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let activity = selectedActivity {
                    Panel(title: "Summary", systemImage: "info.circle") {
                        DetailRow("Status", activity.status.rawValue.capitalized)
                        DetailRow("Queued", activity.queuedAt.formatted(date: .abbreviated, time: .shortened))
                        DetailRow("Started", activity.startedAt?.formatted(date: .omitted, time: .standard) ?? "-")
                        DetailRow("Finished", activity.finishedAt?.formatted(date: .omitted, time: .standard) ?? "-")
                        if let error = activity.errorMessage { DetailRow("Error", error) }
                    }
                    Panel(title: "Command", systemImage: "terminal") {
                        HStack {
                            Button("Copy") { copyToPasteboard(activity.commandDescription) }
                            Spacer()
                        }
                        Text(activity.commandDescription)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Panel(title: "Output", systemImage: "doc.text") {
                        Button("Copy Output") { copyToPasteboard(activity.outputLog) }
                            .disabled(activity.outputLog.isEmpty)
                        Text(activity.outputLog.isEmpty ? "No output captured for this operation." : activity.outputLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else {
                    ContentUnavailableView("Select an Operation", systemImage: "doc.text.magnifyingglass", description: Text("Inspect command text, status, and captured output."))
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(14)
        }
    }

    private func matches(_ activity: ActivityRecord, query: String) -> Bool {
        let haystacks = [
            activity.title,
            activity.commandDescription,
            activity.section.title,
            activity.kind.rawValue,
            activity.status.rawValue,
            activity.outputLog,
            activity.summary ?? "",
            activity.errorMessage ?? "",
        ]
        return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func color(for status: ActivityOperationStatus) -> Color {
        switch status {
        case .queued: .secondary
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .canceled: .orange
        }
    }
}

#if DEBUG
#Preview {
    ActivityWorkspaceView()
        .environmentObject(AppModel.preview)
        .frame(width: 1000, height: 640)
}
#endif
