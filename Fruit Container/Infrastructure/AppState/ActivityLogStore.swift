import Foundation

/// Persists the activity / audit log across app launches as a JSON file in
/// Application Support. All access is failure-tolerant: a missing or corrupt
/// store never surfaces an error into the UI, it simply yields an empty log.
enum ActivityLogStore {
    /// Maximum number of records retained on disk. Bounds file growth while
    /// keeping a generous audit window.
    static let maximumRecords = 500

    private static let directoryName = "Fruit Container"
    private static let fileName = "activity-log.json"

    static func load() -> [ActivityRecord] {
        guard let url = storeURL else { return [] }
        return load(from: url)
    }

    static func save(_ records: [ActivityRecord]) {
        guard let url = storeURL else { return }
        save(records, to: url)
    }

    /// Decodes records from an explicit URL. Returns `[]` for a missing or
    /// corrupt file. Exposed for testing against a temporary location.
    static func load(from url: URL) -> [ActivityRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try makeDecoder().decode([ActivityRecord].self, from: data)
        } catch {
            return []
        }
    }

    /// Encodes the most recent `maximumRecords` records to an explicit URL.
    /// Exposed for testing against a temporary location.
    static func save(_ records: [ActivityRecord], to url: URL) {
        let capped = Array(records.prefix(maximumRecords))
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try makeEncoder().encode(capped)
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence is best-effort; failures must not interrupt the app.
        }
    }

    private static var storeURL: URL? {
        guard let supportDirectory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return supportDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
