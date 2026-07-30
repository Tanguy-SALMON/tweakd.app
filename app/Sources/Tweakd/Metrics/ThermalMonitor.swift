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
