import AppKit

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func commaList(_ text: String) -> [String] {
    text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}

func dictionaryList(_ text: String) -> [String: String] {
    Dictionary(uniqueKeysWithValues: commaList(text).compactMap { pair in
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    })
}

func formatBytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

func formatPercent(_ value: Double?) -> String {
    guard let value else { return "Sampling…" }
    return "\(value.formatted(.number.precision(.fractionLength(1))))%"
}

func shellWords(_ text: String) -> [String] {
    text.split(separator: " ").map(String.init)
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
