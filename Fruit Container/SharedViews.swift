import SwiftUI

struct ResourceHeader: View {
    let title: String
    let subtitle: String
    @Binding var searchText: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !searchText.isEmpty || title != "Activity" && title != "Registries" {
                searchField
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(FruitTheme.chromeFill)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Search \(title.lowercased())", text: $searchText)
                .textFieldStyle(.plain)
                .labelsHidden()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 260)
        .background(FruitTheme.controlBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(FruitTheme.hairline)
        }
        .accessibilityElement(children: .contain)
    }
}

struct Panel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FruitTheme.cardFill, in: RoundedRectangle(cornerRadius: FruitTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FruitTheme.cornerRadius, style: .continuous)
                .stroke(FruitTheme.hairline)
        }
    }
}

struct ActionableEmptyState: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String?
    var actionSystemImage: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 58)
                .background(FruitTheme.controlBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionSystemImage ?? "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.callout.weight(.medium))
        }
        .foregroundStyle(color == .secondary ? .secondary : color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct InspectorSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct KeyValueList: View {
    let values: [String: String]
    var emptyText = "None"

    var body: some View {
        if values.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(values.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(key)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(values[key] ?? "")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

struct CodeBlock: View {
    let text: String
    var emptyText = "No output."

    var body: some View {
        ScrollView(.horizontal) {
            Text(text.isEmpty ? emptyText : text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FruitTheme.controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FruitTheme.hairline)
        }
        .accessibilityLabel(text.isEmpty ? emptyText : text)
    }
}

struct FormField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var helper: String?
    var error: String?
    var isMonospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(isMonospaced ? Font.system(.body, design: .monospaced) : Font.body)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let helper {
                Text(helper)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FeedbackBar: View {
    let message: String
    let isError: Bool

    var body: some View {
        Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "info.circle")
            .font(.caption)
            .foregroundStyle(isError ? .red : .secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isError ? AnyShapeStyle(.red.opacity(0.10)) : FruitTheme.chromeFill)
            .accessibilityLabel(isError ? "Error: \(message)" : message)
    }
}

struct FutureRow: View {
    let title: String
    var status: String?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).fontWeight(.medium)
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FruitTheme.cardFill, in: Capsule())
                }
            }
            Text(detail).foregroundStyle(.secondary)
        }
    }
}

struct ImageMetadataPill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint == .secondary ? .secondary : tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((tint == .secondary ? Color.secondary : tint).opacity(0.12), in: Capsule())
    }
}

struct PlatformChip: View {
    let platform: String
    var compact = false

    var body: some View {
        Label(platform, systemImage: platformSymbol)
            .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 3 : 5)
            .background(FruitTheme.cardFill, in: Capsule())
    }

    private var platformSymbol: String {
        if platform.contains("arm64") { return "cpu" }
        if platform.contains("amd64") || platform.contains("386") { return "desktopcomputer" }
        if platform.contains("unknown") { return "questionmark.circle" }
        return "truck.box"
    }
}

struct CommandPreview: View {
    let command: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CodeBlock(text: command, emptyText: "Command preview unavailable.")

            Button {
                copyToPasteboard(command)
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Copy command")
            .accessibilityLabel("Copy command")
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = rows(for: subviews, width: width)
        return CGSize(width: width, height: rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * lineSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, width: bounds.width)
        var y = bounds.minY
        var index = 0

        for row in rows {
            var x = bounds.minX
            for _ in row.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width + spacing
                index += 1
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [FlowRow] {
        var rows: [FlowRow] = []
        var start = 0
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = currentWidth == 0 ? size.width : currentWidth + spacing + size.width

            if proposedWidth > width, currentWidth > 0 {
                rows.append(FlowRow(range: start..<index, height: currentHeight))
                start = index
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if start < subviews.endIndex {
            rows.append(FlowRow(range: start..<subviews.endIndex, height: currentHeight))
        }

        return rows
    }
}

struct FlowRow {
    let range: Range<Int>
    let height: CGFloat
}

struct ActivityRowView: View {
    let activity: ActivityRecord

    var body: some View {
        HStack(spacing: 10) {
            StatusBadge(text: activity.status.rawValue.capitalized, color: color)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title).fontWeight(.medium).lineLimit(1)
                Text(activity.commandDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var color: Color {
        switch activity.status {
        case .queued: .secondary
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .canceled: .orange
        }
    }
}
