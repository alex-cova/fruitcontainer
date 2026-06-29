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
                    ActionableEmptyState(
                        title: "No Operations",
                        systemImage: "clock.arrow.circlepath",
                        message: "Command history, errors, and output appear here after you run an operation."
                    )
                } else if filteredActivities.isEmpty {
                    ActionableEmptyState(
                        title: "No Matching Log Entries",
                        systemImage: "magnifyingglass",
                        message: "No operations match \"\(searchText)\".",
                        actionTitle: "Clear Search",
                        actionSystemImage: "xmark.circle",
                        action: { searchText = "" }
                    )
                } else {
                    Table(filteredActivities, selection: $selection) {
                        TableColumn("Operation") { activity in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.title).fontWeight(.medium).lineLimit(1)
                                Text(activity.commandDescription).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(activity.title), \(activity.status.rawValue), \(activity.commandDescription)")
                        }
                        .width(min: 230, ideal: 320)
                        TableColumn("Status") { activity in
                            StatusBadge(text: activity.status.rawValue.capitalized, color: color(for: activity.status))
                        }
                        .width(min: 100, ideal: 120, max: 140)
                        TableColumn("Type") { activity in
                            Text(activity.kind.rawValue.capitalized).foregroundStyle(.secondary)
                        }
                        .width(min: 86, ideal: 100, max: 120)
                        TableColumn("Section") { activity in
                            Text(activity.section.title).foregroundStyle(.secondary)
                        }
                        .width(min: 90, ideal: 110, max: 130)
                        TableColumn("Logged") { activity in
                            Text(activity.queuedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }
                        .width(min: 140, ideal: 170)
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
                            Button { copyToPasteboard(activity.commandDescription) } label: { Label("Copy Command", systemImage: "doc.on.doc") }
                            Spacer()
                        }
                        CodeBlock(text: activity.commandDescription)
                    }
                    Panel(title: "Output", systemImage: "doc.text") {
                        HStack {
                            Button { copyToPasteboard(activity.outputLog) } label: { Label("Copy Output", systemImage: "doc.on.doc") }
                                .disabled(activity.outputLog.isEmpty)
                            Spacer()
                        }
                        CodeBlock(text: activity.outputLog, emptyText: "No output captured for this operation.")
                    }
                } else {
                    ActionableEmptyState(
                        title: "Select an Operation",
                        systemImage: "doc.text.magnifyingglass",
                        message: "Inspect command text, status, and captured output."
                    )
                    .frame(minHeight: 260)
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
