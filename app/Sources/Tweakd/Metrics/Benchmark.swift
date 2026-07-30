//
//  Benchmark.swift
//  tweakd
//
//  Small, honest micro-benchmarks so you can measure the gain from a tweak.
//  Run a baseline, apply tweaks, run again — the Benchmark view diffs them.
//  Scores are normalized so higher is always better.
//

import Foundation

struct BenchmarkResult: Identifiable, Equatable {
    let id: Int
    let label: String
    let singleCore: Double     // Mops/s
    let multiCore: Double      // Mops/s
    let memoryBandwidth: Double // MB/s
    let disk: Double            // MB/s

    /// A single blended figure of merit.
    var overall: Double {
        Bench.score(singleCore: singleCore, multiCore: multiCore,
                    memory: memoryBandwidth, disk: disk)
    }
}

/// Defeats the optimizer so timed loops actually run.
enum BenchSink { nonisolated(unsafe) static var value: Double = 0 }

@MainActor
final class BenchmarkEngine: ObservableObject {
    @Published private(set) var results: [BenchmarkResult] = []
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentTask: String = ""
    private var counter = 0

    // MARK: Persisted history

    /// Every run ever recorded, oldest first — the timeline's data source.
    @Published private(set) var history: [BenchmarkRecord] = []

    // MARK: Daily schedule

    /// Opt-in daily run. Off by default: a benchmark saturates every core for
    /// a few seconds, and doing that unasked on someone's machine is rude.
    @Published var dailyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(dailyEnabled, forKey: Keys.daily)
            dailyEnabled ? startScheduler() : stopScheduler()
            if !dailyEnabled { scheduleNote = nil }
        }
    }

    /// Hour of day (0–23) the run is due. Defaults to noon.
    @Published var dailyHour: Int {
        didSet {
            UserDefaults.standard.set(dailyHour, forKey: Keys.hour)
            // A new time is a new appointment — let today's fire again.
            lastAttemptDay = nil
            scheduleNote = nil
        }
    }

    /// Why the scheduler is waiting, when it is. Nil when there's nothing to say.
    @Published private(set) var scheduleNote: String?

    private enum Keys {
        static let daily = "benchmark.daily"
        static let hour = "benchmark.dailyHour"
        static let lastAttempt = "benchmark.lastAttemptDay"
    }

    /// Checked every 5 minutes rather than fired by a one-shot timer at the
    /// due time: a laptop is usually asleep at some point, and a sleeping Mac
    /// silently swallows a scheduled fire. Polling catches up after a wake.
    private let checkInterval: TimeInterval = 300
    /// How late a missed run may still happen. Past this, skip the day — a
    /// "noon" benchmark recorded at 11pm on a warm machine is not comparable.
    private let graceWindow: TimeInterval = 4 * 3600
    private var scheduleTimer: Timer?
    /// Day we last ran *or* deliberately gave up on, so neither repeats.
    private var lastAttemptDay: Date? {
        didSet { UserDefaults.standard.set(lastAttemptDay, forKey: Keys.lastAttempt) }
    }

    init() {
        dailyEnabled = UserDefaults.standard.bool(forKey: Keys.daily)
        dailyHour = UserDefaults.standard.object(forKey: Keys.hour) as? Int ?? 12
        lastAttemptDay = UserDefaults.standard.object(forKey: Keys.lastAttempt) as? Date
        let loaded = BenchmarkHistoryStore.load()
        history = loaded
        if dailyEnabled { startScheduler() }
    }

    var latest: BenchmarkResult? { results.last }
    var baseline: BenchmarkResult? { results.first }

    func run(label: String, trigger: BenchmarkRecord.Trigger = .manual) async {
        guard !isRunning else { return }
        isRunning = true
        progress = 0
        defer { isRunning = false; currentTask = "" }

        currentTask = "Single-core CPU"
        let sc = await Task.detached(priority: .userInitiated) { Bench.singleCore() }.value
        progress = 0.25

        currentTask = "Multi-core CPU"
        let mc = await Task.detached(priority: .userInitiated) { Bench.multiCore() }.value
        progress = 0.5

        currentTask = "Memory bandwidth"
        let mb = await Task.detached(priority: .userInitiated) { Bench.memoryBandwidth() }.value
        progress = 0.75

        currentTask = "Disk I/O"
        let dk = await Task.detached(priority: .userInitiated) { Bench.disk() }.value
        progress = 1

        // Only manual runs join the A/B session. A scheduled run landing in
        // `results` would silently redefine "After tweaks" — you'd set a
        // baseline in the morning and have noon's run become the thing your
        // tweaks are measured against.
        if trigger == .manual {
            counter += 1
            results.append(BenchmarkResult(id: counter, label: label,
                                           singleCore: sc, multiCore: mc,
                                           memoryBandwidth: mb, disk: dk))
        }

        let record = BenchmarkRecord(id: UUID(), date: Date(), trigger: trigger,
                                     singleCore: sc, multiCore: mc,
                                     memoryBandwidth: mb, disk: dk)
        history.append(record)
        persistHistory()
        Log.audit("benchmark.run", [
            "trigger": trigger.rawValue,
            "overall": String(format: "%.0f", record.overall),
        ], result: .ok)
    }

    /// Clears the current A/B session only. History is deliberately untouched —
    /// "Clear" next to the run button means "start a fresh comparison", not
    /// "throw away a year of measurements".
    func clear() { results.removeAll() }

    func clearHistory() {
        history.removeAll()
        Task.detached { BenchmarkHistoryStore.deleteFile() }
    }

    func nextLabel() -> String {
        switch results.count {
        case 0: return "Baseline"
        case 1: return "After tweaks"
        default: return "Run \(results.count + 1)"
        }
    }

    private func persistHistory() {
        let snapshot = history
        Task.detached { BenchmarkHistoryStore.save(snapshot) }
    }

    // MARK: - Scheduling

    /// When the next daily run is due (today's slot if still ahead, else tomorrow's).
    var nextDueDate: Date? {
        guard dailyEnabled else { return nil }
        let cal = Calendar.current
        let now = Date()
        guard let todaySlot = cal.date(bySettingHour: dailyHour, minute: 0, second: 0, of: now) else { return nil }
        let doneToday = lastAttemptDay.map { cal.isDate($0, inSameDayAs: now) } ?? false
        if !doneToday, now < todaySlot { return todaySlot }
        return cal.date(byAdding: .day, value: 1, to: todaySlot)
    }

    private func startScheduler() {
        guard scheduleTimer == nil else { return }
        // No immediate fire: the first tick is one interval away, which doubles
        // as a grace period so launching the app at 3pm doesn't peg all cores
        // while the login items are still settling.
        let t = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkSchedule() }
        }
        RunLoop.main.add(t, forMode: .common)
        scheduleTimer = t
    }

    private func stopScheduler() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
    }

    private func checkSchedule() async {
        guard dailyEnabled, !isRunning else { return }
        let cal = Calendar.current
        let now = Date()
        guard let due = cal.date(bySettingHour: dailyHour, minute: 0, second: 0, of: now),
              now >= due else { return }
        if let last = lastAttemptDay, cal.isDate(last, inSameDayAs: now) { return }

        if now.timeIntervalSince(due) > graceWindow {
            lastAttemptDay = now
            scheduleNote = "Missed today's run — the Mac was asleep or busy past the window."
            Log.audit("benchmark.skipped", ["reason": "outside grace window"], result: .skipped)
            return
        }

        // A benchmark measures whatever the machine has left, so running it on
        // a hot or loaded Mac records the *load*, not the Mac. Waiting out a
        // build or a video call is what keeps the timeline comparable.
        if let blocker = Self.busyReason() {
            scheduleNote = "Waiting — \(blocker). Will retry shortly."
            return
        }

        lastAttemptDay = now
        scheduleNote = nil
        await run(label: Self.scheduledLabel(now), trigger: .scheduled)
    }

    private static func scheduledLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// Non-nil when now is a bad moment to benchmark, describing why.
    nonisolated static func busyReason() -> String? {
        if ProcessInfo.processInfo.thermalState != .nominal { return "the Mac is warm" }
        let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) > 0, load[0] > cores * 0.6 {
            return String(format: "the system is busy (load %.1f)", load[0])
        }
        return nil
    }
}

// MARK: - Workloads (pure, run off the main actor)

enum Bench {

    /// The one place the weights live. Both the in-session `BenchmarkResult`
    /// and the persisted `BenchmarkRecord` score through here — if these ever
    /// drifted apart, today's run and last month's would be on different
    /// scales and the timeline would show a phantom cliff.
    ///
    /// Weighted, scaled into a friendly ~0–4000 range.
    static func score(singleCore: Double, multiCore: Double,
                      memory: Double, disk: Double) -> Double {
        singleCore * 4 + multiCore * 1.5 + memory * 0.02 + disk * 0.05
    }

    private static func seconds(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }

    static func singleCore() -> Double {
        let iterations = 30_000_000
        var acc = 0.0
        let secs = seconds {
            var x = 1.0
            for i in 1...iterations {
                x = (x + Double(i)).squareRoot()
                acc += x.truncatingRemainder(dividingBy: 7.0)
            }
        }
        BenchSink.value += acc
        return secs > 0 ? Double(iterations) / secs / 1_000_000 : 0
    }

    static func multiCore() -> Double {
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let perCore = 15_000_000
        let total = perCore * cores
        let partials = UnsafeMutableBufferPointer<Double>.allocate(capacity: cores)
        partials.initialize(repeating: 0)
        defer { partials.deallocate() }

        let secs = seconds {
            DispatchQueue.concurrentPerform(iterations: cores) { c in
                var x = Double(c + 1)
                var acc = 0.0
                for i in 1...perCore {
                    x = (x + Double(i)).squareRoot()
                    acc += x.truncatingRemainder(dividingBy: 7.0)
                }
                partials[c] = acc
            }
        }
        BenchSink.value += partials.reduce(0, +)
        return secs > 0 ? Double(total) / secs / 1_000_000 : 0
    }

    static func memoryBandwidth() -> Double {
        let bytes = 256 * 1024 * 1024
        let count = bytes / MemoryLayout<Int>.stride
        let src = UnsafeMutableBufferPointer<Int>.allocate(capacity: count)
        let dst = UnsafeMutableBufferPointer<Int>.allocate(capacity: count)
        src.initialize(repeating: 0x5A5A5A5A)
        dst.initialize(repeating: 0)
        defer { src.deallocate(); dst.deallocate() }

        let passes = 6
        let secs = seconds {
            for _ in 0..<passes {
                memcpy(dst.baseAddress!, src.baseAddress!, bytes)
            }
        }
        BenchSink.value += Double(dst[0])
        let movedMB = Double(bytes * passes) / (1024 * 1024)
        return secs > 0 ? movedMB / secs : 0
    }

    static func disk() -> Double {
        let sizeMB = 128
        let bytes = sizeMB * 1024 * 1024
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tweakd-bench-\(getpid()).bin")
        let data = Data(count: bytes)
        defer { try? FileManager.default.removeItem(at: url) }

        var writeSecs = 0.0, readSecs = 0.0
        do {
            writeSecs = seconds {
                try? data.write(to: url, options: .atomic)
            }
            readSecs = seconds {
                if let fh = try? FileHandle(forReadingFrom: url) {
                    let read = try? fh.readToEnd()
                    BenchSink.value += Double(read?.count ?? 0)
                    try? fh.close()
                }
            }
        }
        let totalSecs = writeSecs + readSecs
        guard totalSecs > 0 else { return 0 }
        return Double(sizeMB * 2) / totalSecs   // MB/s over write+read
    }
}
