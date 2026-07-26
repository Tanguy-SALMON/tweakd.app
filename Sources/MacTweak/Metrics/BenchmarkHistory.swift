//
//  BenchmarkHistory.swift
//  MacTweak
//
//  Long-term storage for benchmark runs, so a score means something beyond the
//  current session. The A/B chart in the Benchmark view answers "did that tweak
//  help?"; this answers the slower question — "is this Mac getting worse?" —
//  which you can only see across weeks.
//
//  Stored as pretty-printed JSON with ISO-8601 dates at
//  ~/Library/Application Support/MacTweak/benchmark-history.json, so the trail
//  is readable and greppable by hand, like the audit log.
//

import Foundation

/// One persisted benchmark run.
struct BenchmarkRecord: Codable, Identifiable, Equatable, Sendable {

    /// How the run was started. Worth recording: a scheduled run happens on an
    /// idle-ish Mac by design, while a manual one can be fired mid-Xcode-build,
    /// so mixing them without a marker makes the trend look noisier than it is.
    enum Trigger: String, Codable, Sendable {
        case manual
        case scheduled

        var icon: String { self == .scheduled ? "clock" : "hand.tap" }
        var label: String { self == .scheduled ? "Scheduled" : "Manual" }
    }

    let id: UUID
    let date: Date
    let trigger: Trigger
    let singleCore: Double
    let multiCore: Double
    let memoryBandwidth: Double
    let disk: Double

    var overall: Double {
        Bench.score(singleCore: singleCore, multiCore: multiCore,
                    memory: memoryBandwidth, disk: disk)
    }
}

/// Reads and writes the history file. All members are `nonisolated` so the
/// engine can do file I/O off the main actor.
enum BenchmarkHistoryStore {

    /// Roughly a year of daily runs. Old points stop being comparable anyway —
    /// by then it's a different macOS on a differently-full disk.
    static let maxRecords = 400

    nonisolated static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MacTweak/benchmark-history.json")
    }

    nonisolated static func load() -> [BenchmarkRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A corrupt or half-written file must not take the page down: an empty
        // history is a recoverable annoyance, a crash loop is not.
        guard let records = try? decoder.decode([BenchmarkRecord].self, from: data) else { return [] }
        return records.sorted { $0.date < $1.date }
    }

    nonisolated static func save(_ records: [BenchmarkRecord]) {
        let trimmed = records.suffix(maxRecords)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Array(trimmed)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    nonisolated static func deleteFile() {
        try? FileManager.default.removeItem(at: url)
    }
}
