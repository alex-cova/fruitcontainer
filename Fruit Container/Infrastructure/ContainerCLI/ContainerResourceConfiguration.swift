import Foundation

struct ContainerResourceConfiguration: Equatable, Sendable {
    var cpus: Int?
    var memory: String?

    static let empty = ContainerResourceConfiguration(cpus: nil, memory: nil)

    var managedSnippet: String {
        var lines = ["[container]"]
        if let cpus {
            lines.append("cpus = \(cpus)")
        }
        if let memory {
            lines.append("memory = \"\(Self.escapeTOMLString(memory))\"")
        }
        return lines.joined(separator: "\n")
    }

    static func normalizedMemory(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isValidMemory(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let pattern = #"^\d+(?:\.\d+)?\s*(?:b|kb|k|mb|m|gb|g|tb|t)$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func escapeTOMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct ContainerResourceConfigurationStore: Sendable {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = ContainerResourceConfigurationStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("container", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    func load() throws -> ContainerResourceConfiguration {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return Self.parse(text)
    }

    func save(_ configuration: ContainerResourceConfiguration) throws {
        let existingText: String
        if fileManager.fileExists(atPath: fileURL.path) {
            existingText = try String(contentsOf: fileURL, encoding: .utf8)
        } else {
            existingText = ""
        }

        let updatedText = Self.render(configuration, preserving: existingText)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try updatedText.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func parse(_ text: String) -> ContainerResourceConfiguration {
        let lines = text.components(separatedBy: .newlines)
        guard let range = containerTableRange(in: lines) else {
            return .empty
        }

        var configuration = ContainerResourceConfiguration.empty
        for line in lines[range].dropFirst() {
            guard let assignment = activeAssignment(in: line) else { continue }
            switch assignment.key {
            case "cpus":
                configuration.cpus = Int(assignment.value)
            case "memory":
                configuration.memory = unquotedString(assignment.value)
            default:
                continue
            }
        }
        return configuration
    }

    static func render(_ configuration: ContainerResourceConfiguration, preserving text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        if text.isEmpty {
            lines = []
        }

        guard let range = containerTableRange(in: lines) else {
            var updated = lines
            if !updated.isEmpty, updated.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                updated.append("")
            }
            updated.append("[container]")
            appendManagedLines(for: configuration, to: &updated)
            return updated.joined(separator: "\n")
        }

        var rewrittenSection: [String] = [lines[range.lowerBound]]
        var wroteCPUs = false
        var wroteMemory = false

        for line in lines[range].dropFirst() {
            guard let assignment = activeAssignment(in: line) else {
                rewrittenSection.append(line)
                continue
            }

            switch assignment.key {
            case "cpus":
                if !wroteCPUs, let cpus = configuration.cpus {
                    rewrittenSection.append("cpus = \(cpus)")
                }
                wroteCPUs = true
            case "memory":
                if !wroteMemory, let memory = configuration.memory {
                    rewrittenSection.append("memory = \"\(ContainerResourceConfiguration.escapeTOMLString(memory))\"")
                }
                wroteMemory = true
            default:
                rewrittenSection.append(line)
            }
        }

        if !wroteCPUs, let cpus = configuration.cpus {
            rewrittenSection.append("cpus = \(cpus)")
        }
        if !wroteMemory, let memory = configuration.memory {
            rewrittenSection.append("memory = \"\(ContainerResourceConfiguration.escapeTOMLString(memory))\"")
        }

        return (Array(lines[..<range.lowerBound]) + rewrittenSection + Array(lines[range.upperBound...]))
            .joined(separator: "\n")
    }

    private static func appendManagedLines(
        for configuration: ContainerResourceConfiguration,
        to lines: inout [String]
    ) {
        if let cpus = configuration.cpus {
            lines.append("cpus = \(cpus)")
        }
        if let memory = configuration.memory {
            lines.append("memory = \"\(ContainerResourceConfiguration.escapeTOMLString(memory))\"")
        }
    }

    private static func containerTableRange(in lines: [String]) -> Range<Int>? {
        guard let start = lines.indices.first(where: { tableName(in: lines[$0]) == "container" }) else {
            return nil
        }

        let end = lines.indices.drop(while: { $0 <= start }).first { index in
            guard let tableName = tableName(in: lines[index]) else { return false }
            return !tableName.isEmpty
        } ?? lines.endIndex

        return start..<end
    }

    private static func tableName(in line: String) -> String? {
        let active = uncommented(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard active.hasPrefix("["), active.hasSuffix("]"), !active.hasPrefix("[[") else {
            return nil
        }
        return String(active.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func activeAssignment(in line: String) -> (key: String, value: String)? {
        let active = uncommented(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalsIndex = active.firstIndex(of: "=") else {
            return nil
        }

        let key = active[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = active[active.index(after: equalsIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    private static func uncommented(_ line: String) -> String {
        var isEscaped = false
        var isQuoted = false

        for index in line.indices {
            let character = line[index]
            if character == "\\" {
                isEscaped.toggle()
                continue
            }
            if character == "\"", !isEscaped {
                isQuoted.toggle()
            }
            if character == "#", !isQuoted {
                return String(line[..<index])
            }
            isEscaped = false
        }

        return line
    }

    private static func unquotedString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return trimmed
        }

        let body = trimmed.dropFirst().dropLast()
        return body
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
