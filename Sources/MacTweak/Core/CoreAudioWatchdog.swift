//
//  CoreAudioWatchdog.swift
//  MacTweak
//
//  Watches coreaudiod's CPU and auto-restarts it when a stuck audio stream
//  pegs it (a third-party virtual-audio HAL driver — e.g. Teams — runs *inside*
//  coreaudiod, so a hung stream shows up as coreaudiod CPU). Opt-in; only acts
//  when the load is sustained, and only restarts silently if passwordless admin
//  is unlocked so it never throws a password prompt on its own.
//

import Foundation
import Combine

@MainActor
final class CoreAudioWatchdog: ObservableObject {

    /// Persisted opt-in. Toggling starts/stops the sampler.
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.key)
            enabled ? start() : stop()
        }
    }

    /// Most recent measured coreaudiod CPU (% of one core), for the UI.
    @Published private(set) var lastCPU: Double = 0
    /// Human-readable note about the last thing the watchdog did.
    @Published private(set) var lastAction: String?

    /// Trip threshold and how long it must hold before we act.
    let thresholdPercent: Double = 8
    private let interval: TimeInterval = 15
    private let sustainedTicksToTrip = 2          // ~30s above threshold

    private static let key = "watchdog.coreaudio"
    private weak var engine: TweakEngine?
    private var timer: Timer?
    private var prevCPUSeconds: Double?
    private var prevStamp: Date?
    private var hotTicks = 0

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// Wire to the engine so the watchdog can reuse the Restart Core Audio action
    /// and check whether admin is unlocked. Starts sampling if already enabled.
    func configure(engine: TweakEngine) {
        self.engine = engine
        if enabled { start() }
    }

    private func start() {
        guard timer == nil else { return }
        prevCPUSeconds = nil; prevStamp = nil; hotTicks = 0
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        lastCPU = 0
    }

    // MARK: - Sampling

    private func tick() async {
        let sample = await Task.detached { Self.readCoreAudioCPUSeconds() }.value
        let now = Date()
        defer { prevCPUSeconds = sample; prevStamp = now }

        guard let secs = sample, let prev = prevCPUSeconds, let stamp = prevStamp else { return }
        let elapsed = now.timeIntervalSince(stamp)
        // pid changed (a restart) → accumulated time drops; skip this delta.
        guard elapsed > 0, secs >= prev else { hotTicks = 0; return }

        let pct = (secs - prev) / elapsed * 100
        lastCPU = pct
        hotTicks = pct >= thresholdPercent ? hotTicks + 1 : 0

        if hotTicks >= sustainedTicksToTrip {
            hotTicks = 0
            await trip(observed: pct)
        }
    }

    private func trip(observed pct: Double) async {
        guard let engine else { return }
        guard engine.adminUnlocked else {
            lastAction = "Core Audio pegged at \(Int(pct))% — unlock admin to auto-restart."
            return
        }
        guard let action = engine.actions.first(where: { $0.key == "restart-coreaudio" }) else { return }
        await engine.run(action)
        lastAction = "Restarted Core Audio (was \(Int(pct))%)."
        prevCPUSeconds = nil; prevStamp = nil   // fresh baseline after restart
    }

    // MARK: - Reading another process's CPU (no root needed)

    /// Accumulated CPU-seconds for coreaudiod, via `ps` (works cross-user without
    /// root). Instantaneous % is derived from the delta between two ticks.
    nonisolated private static func readCoreAudioCPUSeconds() -> Double? {
        let pid = CommandRunner.user("pgrep -x coreaudiod | head -1").output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty else { return nil }
        let raw = CommandRunner.user("ps -o cputime= -p \(pid)").output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return parseCPUTime(raw)
    }

    /// Parse ps cputime: `SS`, `MM:SS`, `MM:SS.ss`, `HH:MM:SS`, or `DD-HH:MM:SS`.
    nonisolated static func parseCPUTime(_ s: String) -> Double? {
        guard !s.isEmpty else { return nil }
        var str = s
        var days = 0.0
        if let dash = str.firstIndex(of: "-") {
            days = Double(str[..<dash]) ?? 0
            str = String(str[str.index(after: dash)...])
        }
        let parts = str.split(separator: ":").map { Double($0) ?? 0 }
        guard !parts.isEmpty else { return nil }
        let secs = parts.reduce(0.0) { $0 * 60 + $1 }
        return days * 86_400 + secs
    }
}
