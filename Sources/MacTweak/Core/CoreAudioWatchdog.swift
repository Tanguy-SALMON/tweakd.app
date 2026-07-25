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
//  A restart is *not* assumed to work. launchd immediately relaunches coreaudiod
//  and the offending HAL plugin loads straight back into the fresh process, so a
//  naive watchdog re-trips every ~45s forever — audio blipping each time, root
//  cause untouched (observed live: 8 restarts in 7 minutes). Hence the cooldown
//  and the attempt cap below: after `maxAttempts` failures it gives up, stays
//  watching, and says which plugin to remove instead of flapping.
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

    /// Trip threshold, as % of one core. Deliberately high: a wedged stream spins
    /// a whole core or more (156% observed in the wild), whereas coreaudiod doing
    /// *legitimate* work — a call with echo cancellation, spatial audio — can
    /// comfortably sustain 10–30%. A low bar here means killing audio mid-call,
    /// which is far worse than leaving a busy-but-healthy daemon alone.
    let thresholdPercent: Double = 70
    private let interval: TimeInterval = 15
    private let sustainedTicksToTrip = 2          // ~30s above threshold
    /// Minimum spacing between restarts, so a plugin that re-wedges instantly
    /// can't turn this into an audio-blipping loop.
    private let cooldown: TimeInterval = 300
    /// Consecutive failed restarts before giving up and telling the user instead.
    private let maxAttempts = 3
    /// Calm ticks that clear the failure streak (~2 min genuinely healthy).
    private let calmTicksToForgive = 8

    private static let key = "watchdog.coreaudio"
    private weak var engine: TweakEngine?
    private var timer: Timer?
    private var prevCPUSeconds: Double?
    private var prevStamp: Date?
    private var hotTicks = 0
    private var calmTicks = 0
    private var attempts = 0
    private var lastRestart: Date?
    /// Set once restarting has demonstrably failed; keeps watching, stops acting.
    private var gaveUp = false

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
        rebaseline()
        // An explicit re-enable is the user saying "try again" — clear the streak.
        attempts = 0; lastRestart = nil; gaveUp = false; lastAction = nil
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

    /// Forget the previous sample, so the next tick only establishes a baseline
    /// rather than deriving a bogus delta across a pid change or a gap.
    private func rebaseline() {
        prevCPUSeconds = nil; prevStamp = nil; hotTicks = 0
    }

    private func tick() async {
        let now = Date()
        guard let secs = await Task.detached { Self.readCoreAudioCPUSeconds() }.value else {
            rebaseline(); return               // coreaudiod not running (mid-restart)
        }
        guard let prev = prevCPUSeconds, let stamp = prevStamp else {
            prevCPUSeconds = secs; prevStamp = now; return
        }
        let elapsed = now.timeIntervalSince(stamp)
        // Accumulated CPU time going *backwards* means a new pid — the delta is
        // meaningless, so adopt this sample as the baseline instead of dropping it.
        guard elapsed > 0, secs >= prev else {
            prevCPUSeconds = secs; prevStamp = now; hotTicks = 0; return
        }
        prevCPUSeconds = secs; prevStamp = now

        let pct = (secs - prev) / elapsed * 100
        lastCPU = pct

        if pct >= thresholdPercent {
            hotTicks += 1; calmTicks = 0
        } else {
            hotTicks = 0; calmTicks += 1
            // A sustained healthy stretch means whatever we did (or the user did)
            // worked — forgive the streak so a future wedge is acted on again.
            if calmTicks >= calmTicksToForgive, attempts > 0 || gaveUp {
                attempts = 0; gaveUp = false; lastRestart = nil
                lastAction = nil
                Log.audit("watchdog.recovered", ["daemon": "coreaudiod"], result: .ok)
            }
        }

        if hotTicks >= sustainedTicksToTrip {
            hotTicks = 0
            await trip(observed: pct)
        }
    }

    private func trip(observed pct: Double) async {
        guard let engine else { return }
        let observed = Int(pct)

        // Restarting has already failed repeatedly — the plugin reloads into the
        // fresh process, so trying again just blips audio. Say what to fix.
        if gaveUp {
            lastAction = "Core Audio still pegged at \(observed)% after \(maxAttempts) restarts — a virtual-audio plugin in /Library/Audio/Plug-Ins/HAL/ is stuck. Quit the app that installed it (often Teams), or remove the plugin."
            return
        }
        guard engine.adminUnlocked else {
            lastAction = "Core Audio pegged at \(observed)% — unlock admin to auto-restart."
            return
        }
        if let last = lastRestart, Date().timeIntervalSince(last) < cooldown {
            let wait = Int((cooldown - Date().timeIntervalSince(last)) / 60) + 1
            lastAction = "Core Audio hot again (\(observed)%) — waiting ~\(wait) min before restarting again."
            return
        }
        guard let action = engine.actions.first(where: { $0.key == "restart-coreaudio" }) else { return }

        attempts += 1
        lastRestart = Date()
        Log.audit("watchdog.restart", ["daemon": "coreaudiod", "cpu": "\(observed)",
                                       "attempt": "\(attempts)/\(maxAttempts)"])
        await engine.run(action)
        rebaseline()   // the new pid's counter starts from zero

        if attempts >= maxAttempts {
            gaveUp = true
            lastAction = "Restarted Core Audio \(attempts)× and it keeps pegging — something in /Library/Audio/Plug-Ins/HAL/ is stuck. Quit the app that installed it (often Teams), or remove the plugin. Re-toggle this to try again."
            Log.audit("watchdog.gaveUp", ["daemon": "coreaudiod", "attempts": "\(attempts)"],
                      result: .failed)
        } else {
            lastAction = "Restarted Core Audio (was \(observed)%, attempt \(attempts) of \(maxAttempts))."
        }
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
