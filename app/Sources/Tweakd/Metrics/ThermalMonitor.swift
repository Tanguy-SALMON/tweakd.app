//
//  ThermalMonitor.swift
//  tweakd
//
//  Answers one question honestly: "is this Mac running at full speed, or is it
//  being thermally throttled?"
//
//  Two independent signals, because neither alone is sufficient:
//
//  1. Thermal pressure — `ProcessInfo.thermalState`. Free, needs no root, and
//     pushes a notification on change. This is the *authoritative* throttle
//     signal: macOS tells you directly when it's derating for heat. (It's the
//     same value `powermetrics --samplers thermal` prints as "Current pressure
//     level", so there's no reason to pay for root to read it.)
//
//  2. Cluster frequencies — `powermetrics --samplers cpu_power`, which needs
//     root and ~300 ms, so it's sampled on demand rather than continuously.
//
//  The crucial caveat this type is built around: **a frequency below maximum is
//  normally just idle, not throttling.** Cores clock down when nothing is asking
//  for work. Only pressure ≠ nominal means the ceiling has actually been lowered.
//  `verdict` combines both so the UI can never imply "you're throttled" when the
//  machine is merely resting.
//

import Foundation
import SwiftUI

/// One CPU cluster's speed. Apple Silicon groups cores into an Efficiency
/// cluster and one or more Performance clusters (an M3 Pro/Max has P0 and P1).
struct ClusterSpeed: Identifiable, Sendable {
    let name: String        // e.g. "P-Cluster", "E-Cluster", "P0-Cluster"
    let currentMHz: Int
    /// Highest step the hardware advertises, read from the residency histogram.
    let maxMHz: Int

    var id: String { name }

    /// How close to the ceiling, 0…1 (nil when the max is unknown).
    var fractionOfMax: Double? {
        guard maxMHz > 0 else { return nil }
        return min(Double(currentMHz) / Double(maxMHz), 1)
    }

    /// "Performance" / "Efficiency" — friendlier than powermetrics' raw label.
    var friendlyName: String {
        if name.hasPrefix("E") { return "Efficiency cores" }
        if name.hasPrefix("P") {
            // P0-Cluster / P1-Cluster on multi-cluster chips (M-series Pro/Max).
            let digits = name.drop(while: { $0 != "P" }).dropFirst().prefix(while: \.isNumber)
            return digits.isEmpty ? "Performance cores" : "Performance cores \(digits)"
        }
        return name
    }
}

@MainActor
final class ThermalMonitor: ObservableObject {

    /// macOS's own thermal-pressure level — the authoritative throttle signal.
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    /// Per-cluster speeds from the last `sampleFrequencies()` call.
    @Published private(set) var clusters: [ClusterSpeed] = []
    @Published private(set) var sampling = false
    /// Set when a frequency sample couldn't be taken (needs admin, or timed out).
    @Published private(set) var sampleError: String?
    /// When the frequency data was last read — it's a point-in-time sample.
    @Published private(set) var sampledAt: Date?

    private var observer: NSObjectProtocol?

    init() {
        // Thermal pressure is push-based and free; no polling needed.
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Hop to the main actor explicitly — the notification's queue is
            // main, but that isn't the same guarantee as actor isolation.
            Task { @MainActor in self?.refreshThermalState() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refreshThermalState() {
        let now = ProcessInfo.processInfo.thermalState
        if now != thermalState {
            Log.audit("thermal.stateChange",
                      ["from": Self.label(thermalState), "to": Self.label(now)])
        }
        thermalState = now
    }

    // MARK: - Verdict

    /// The plain-language answer to "am I getting full performance?"
    enum Verdict {
        case fullSpeed          // pressure nominal — no derating
        case mildlyLimited      // pressure fair
        case throttled          // serious / critical — real performance loss
        case unknown

        var title: String {
            switch self {
            case .fullSpeed:     return "Running at full speed"
            case .mildlyLimited: return "Slightly limited"
            case .throttled:     return "Thermally throttled"
            case .unknown:       return "Unknown"
            }
        }

        var detail: String {
            switch self {
            case .fullSpeed:
                return "macOS reports nominal thermal pressure — the CPU's full speed range is available. Cores idling below their maximum is normal; they clock down when there's nothing to do."
            case .mildlyLimited:
                return "Thermal pressure is elevated. macOS has begun trimming peak performance slightly — usually after a sustained burst. It should recover on its own once things cool."
            case .throttled:
                return "macOS is actively reducing performance to shed heat, so sustained work will run slower. Close or deprioritise whatever is pegging the CPU, and check for blocked vents."
            case .unknown:
                return "Couldn't read the thermal pressure level."
            }
        }

        var icon: String {
            switch self {
            case .fullSpeed:     return "checkmark.seal.fill"
            case .mildlyLimited: return "thermometer.medium"
            case .throttled:     return "thermometer.high"
            case .unknown:       return "questionmark.circle"
            }
        }

        /// Only a real throttle earns the alarming treatment.
        var isAlarming: Bool { self == .throttled }
    }

    var verdict: Verdict {
        switch thermalState {
        case .nominal:  return .fullSpeed
        case .fair:     return .mildlyLimited
        case .serious, .critical: return .throttled
        @unknown default: return .unknown
        }
    }

    nonisolated static func label(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    var thermalLabel: String { Self.label(thermalState) }

    /// The four levels macOS can report, in order, each with what it actually
    /// means for you. Shown as a scale in the UI: "Nominal" on its own is a
    /// result with nothing to compare it against.
    static let levels: [(state: ProcessInfo.ThermalState, name: String, meaning: String)] = [
        (.nominal,  "Nominal",  "No heat limiting at all. Full speed is available."),
        (.fair,     "Fair",     "Warming up. macOS trims peak speed a little; you're unlikely to feel it."),
        (.serious,  "Serious",  "Real slowdown. Speed is cut to shed heat, and background work is deferred."),
        (.critical, "Critical", "Emergency limiting. Everything is throttled hard until the Mac cools."),
    ]

    /// 0…3 — which rung of `levels` is lit right now.
    var levelIndex: Int {
        Int(SystemMetrics.thermalStep(thermalState))
    }

    /// True when this Mac has no fan, so sustained load is far likelier to
    /// throttle — worth saying out loud on an Air.
    static let isPassivelyCooled: Bool = SystemInfo.isFanless

    // MARK: - Frequency sampling (admin)

    /// Sample per-cluster frequencies via `powermetrics` (needs root; ~0.3 s).
    func sampleFrequencies() async {
        guard !sampling else { return }
        sampling = true
        defer { sampling = false }

        let result = await Task.detached {
            // A single 300 ms sample of just the cpu_power sampler — enough for
            // active frequency plus the residency histogram we derive max from.
            CommandRunner.admin("/usr/bin/powermetrics --samplers cpu_power -n 1 -i 300 2>/dev/null")
        }.value

        if result.userCancelled {
            sampleError = "Cancelled."
            return
        }
        let parsed = Self.parseClusters(result.output)
        if parsed.isEmpty {
            sampleError = result.ok
                ? "Couldn't read CPU frequencies from powermetrics."
                : "Reading CPU frequency needs administrator access."
            clusters = []
        } else {
            sampleError = nil
            clusters = parsed
            sampledAt = Date()
            Log.audit("thermal.sample",
                      ["pressure": thermalLabel,
                       "clusters": parsed.map { "\($0.name):\($0.currentMHz)/\($0.maxMHz)" }
                           .joined(separator: ",")],
                      result: .ok)
        }
    }

    // MARK: - Live frequency stream (admin, 1 Hz)

    /// True while cluster speeds are refreshing every second.
    @Published private(set) var live = false
    /// Why live mode isn't available, if it isn't.
    @Published private(set) var liveBlocked: String?

    private var stream: CommandRunner.StreamHandle?
    private var blockLines: [String] = []
    /// Bound on one stream's lifetime. This is a root process; if the UI ever
    /// fails to stop it, it stops itself rather than sampling forever.
    private static let liveSampleLimit = 900     // 15 min at 1 Hz

    /// Live mode needs a *streaming* root process, which only the passwordless
    /// sudoers rule can give us — the authorization dialog buffers until exit.
    var canGoLive: Bool { CommandRunner.hasPasswordlessAdmin() }

    func toggleLive() {
        live ? stopLive() : startLive()
    }

    func startLive() {
        guard stream == nil else { return }
        guard canGoLive else {
            liveBlocked = "Live speeds need Admin Access unlocked — powermetrics has to keep running as root."
            return
        }
        liveBlocked = nil

        // One sample per second, cpu_power only. `-n` bounds the run; the handler
        // below restarts it if it expires while the card is still showing.
        let cmd = "/usr/bin/powermetrics --samplers cpu_power -i 1000 -n \(Self.liveSampleLimit) 2>/dev/null"
        stream = CommandRunner.streamAdmin(cmd, onLine: { [weak self] line in
            Task { @MainActor in self?.consume(line) }
        }, onEnd: { [weak self] in
            Task { @MainActor in self?.streamEnded() }
        })

        guard stream != nil else {
            liveBlocked = "Couldn't start powermetrics."
            return
        }
        live = true
        sampleError = nil
        Log.audit("thermal.live", ["state": "start"])
    }

    func stopLive() {
        stream?.stop()
        stream = nil
        blockLines = []
        guard live else { return }
        live = false
        Log.audit("thermal.live", ["state": "stop"])
    }

    private func streamEnded() {
        stream = nil
        // Hit the sample cap while still on screen: start a fresh window rather
        // than silently freezing the numbers at whatever they last were.
        if live {
            live = false
            startLive()
        }
    }

    /// Accumulate one sample block, then parse it whole.
    ///
    /// powermetrics emits a cluster's frequency and its residency histogram on
    /// separate lines, and the histogram is where the maximum comes from — so
    /// lines can't be parsed individually. `*** Sampled system activity` opens
    /// each block, which makes it the flush point for the previous one.
    private func consume(_ line: String) {
        if line.contains("*** Sampled system activity") {
            flushBlock()
            return
        }
        blockLines.append(line)
        // A malformed stream must not grow without bound.
        if blockLines.count > 400 { blockLines.removeFirst(blockLines.count - 400) }
    }

    private func flushBlock() {
        defer { blockLines = [] }
        let parsed = Self.parseClusters(blockLines.joined(separator: "\n"))
        guard !parsed.isEmpty else { return }
        // Max MHz comes from the residency histogram, which only lists steps the
        // cluster actually visited this second — an idle cluster can report a low
        // "max". Carry the highest ceiling seen so the percentage stays anchored.
        let previousMax = Dictionary(uniqueKeysWithValues: clusters.map { ($0.name, $0.maxMHz) })
        clusters = parsed.map {
            ClusterSpeed(name: $0.name, currentMHz: $0.currentMHz,
                         maxMHz: max($0.maxMHz, previousMax[$0.name] ?? 0))
        }
        sampledAt = Date()
        sampleError = nil
    }

    /// Parse `powermetrics --samplers cpu_power` output into per-cluster speeds.
    ///
    /// Two lines per cluster matter:
    ///   `P-Cluster HW active frequency: 1264 MHz`
    ///   `P-Cluster HW active residency: 55.96% (660 MHz: 29% … 3504 MHz: 0%)`
    /// The histogram in the residency line enumerates every DVFS step, so its
    /// highest entry is the hardware maximum — there's no sysctl for this on
    /// Apple Silicon (`hw.cpufrequency` is Intel-only and absent).
    nonisolated static func parseClusters(_ output: String) -> [ClusterSpeed] {
        var current: [String: Int] = [:]
        var maxes: [String: Int] = [:]
        var order: [String] = []

        let stepRegex = try? NSRegularExpression(pattern: #"(\d+)\s*MHz:"#)

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)

            if let r = line.range(of: " HW active frequency:") {
                let cluster = String(line[line.startIndex..<r.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let tail = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if let mhz = Int(tail.split(separator: " ").first.map(String.init) ?? "") {
                    current[cluster] = mhz
                    if !order.contains(cluster) { order.append(cluster) }
                }
                continue
            }

            if let r = line.range(of: " HW active residency:"), let stepRegex {
                let cluster = String(line[line.startIndex..<r.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let ns = line as NSString
                let steps = stepRegex.matches(in: line, range: NSRange(location: 0, length: ns.length))
                    .compactMap { m -> Int? in
                        guard m.numberOfRanges > 1 else { return nil }
                        return Int(ns.substring(with: m.range(at: 1)))
                    }
                if let top = steps.max() { maxes[cluster] = top }
            }
        }

        // Performance clusters first — that's what "am I at max?" is really about.
        return order.map { ClusterSpeed(name: $0, currentMHz: current[$0] ?? 0, maxMHz: maxes[$0] ?? 0) }
            .sorted { a, b in
                let aP = a.name.hasPrefix("P"), bP = b.name.hasPrefix("P")
                if aP != bP { return aP }
                return a.name < b.name
            }
    }
}
