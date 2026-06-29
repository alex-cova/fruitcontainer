import SwiftUI

struct ResourceHeader: View {
    let title: String
    let subtitle: String
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !searchText.isEmpty || title != "Activity" && title != "Registries" {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(FruitTheme.chromeFill)
    }
}

struct Panel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FruitTheme.cardFill, in: RoundedRectangle(cornerRadius: 8))
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
                .font(.callout)
        }
        .foregroundStyle(color)
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
            .background(FruitTheme.chromeFill)
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
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
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
