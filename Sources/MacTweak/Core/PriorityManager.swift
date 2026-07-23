//
//  PriorityManager.swift
//  MacTweak
//
//  Live process-priority (renice) management: discover known network/UI
//  processes, raise or lower their scheduling priority, and optionally persist
//  the change with a per-target LaunchAgent that re-applies it at login.
//
//  Nothing here stores a password — every privileged renice/launchctl call goes
//  through the shared `CommandRunner.admin` lane (one unlock, then passwordless).
//  All state resets to stock on reboot unless "Apply at login" is enabled, and
//  `resetAll()` / the emergency script always restore every process to nice 0.
//
//  NOTE: skeleton API — the concrete implementation is filled in by the
//  Process-Priority worktree agent. Keep the public surface stable; the app,
//  sidebar badge, and emergency-revert script all depend on it.
//

import Foundation
import SwiftUI

/// A well-known process MacTweak offers a one-tap priority preset for.
struct PriorityTarget: Identifiable, Sendable, Hashable {
    let id: String          // stable key, e.g. "mdns"
    let label: String       // display name
    let blurb: String       // what raising/lowering it does
    let icon: String        // SF Symbol
    let pattern: String     // pgrep -f pattern
    let suggestedNice: Int  // -5 for "boost", 10 for "yield"
    let boost: Bool         // true = raise priority (negative nice), false = yield
}

/// One live process row: a PID, its current nice value, and the target it maps to.
struct PriorityProcess: Identifiable, Sendable, Hashable {
    let id: Int32           // pid
    let name: String        // short command name
    let command: String     // full argv[0] path
    var nice: Int           // current NI (0 = default)
    let targetID: String?   // PriorityTarget.id if it matches a known target
}

@MainActor
final class PriorityManager: ObservableObject {

    /// Known targets, in display order. Both the UI and the emergency-revert
    /// script iterate this list — single source of truth.
    static let targets: [PriorityTarget] = [
        PriorityTarget(id: "mdns", label: "mDNSResponder",
                       blurb: "Faster DNS resolution and Bonjour discovery.",
                       icon: "dot.radiowaves.left.and.right",
                       pattern: "mDNSResponder", suggestedNice: -5, boost: true),
        PriorityTarget(id: "firefox", label: "Firefox",
                       blurb: "Snappier page loads under CPU load.",
                       icon: "flame", pattern: "Firefox.app", suggestedNice: -5, boost: true),
        PriorityTarget(id: "chrome", label: "Google Chrome",
                       blurb: "Snappier page loads under CPU load.",
                       icon: "globe", pattern: "Google Chrome", suggestedNice: -5, boost: true),
        PriorityTarget(id: "docker", label: "Docker",
                       blurb: "Lower-latency container networking.",
                       icon: "shippingbox", pattern: "com.docker", suggestedNice: -5, boost: true),
        PriorityTarget(id: "ssh", label: "SSH sessions",
                       blurb: "Low-latency remote terminals.",
                       icon: "terminal", pattern: "sshd", suggestedNice: -5, boost: true),
        PriorityTarget(id: "mediaanalysisd", label: "Media Analysis",
                       blurb: "Yields CPU to foreground apps by lowering its priority.",
                       icon: "film", pattern: "mediaanalysisd", suggestedNice: 10, boost: false),
    ]

    /// The nice range exposed to the user. Kept above -20 for safety (a deeply
    /// negative daemon can starve the UI); the UI warns below -5.
    static let niceRange: ClosedRange<Int> = -10...20

    @Published private(set) var processes: [PriorityProcess] = []
    @Published private(set) var busy: Set<Int32> = []
    @Published private(set) var refreshing = false
    @Published var lastMessage: String?

    /// Number of targets with an "Apply at login" LaunchAgent installed — drives
    /// the sidebar badge. Backed by the on-disk LaunchAgents so it survives relaunch.
    @Published private(set) var managedCount = 0

    private let launchAgentDir = "\(NSHomeDirectory())/Library/LaunchAgents"
    private func plistPath(_ id: String) -> String {
        "\(launchAgentDir)/com.mactweak.priority.\(id).plist"
    }

    init() { recountManaged() }

    // MARK: - Discovery

    /// Re-scan for live processes matching the known targets. Read-only (`pgrep`
    /// + `ps -o nice`), so it never prompts. Implemented by the worktree agent.
    func refresh() async {}

    // MARK: - Priority changes

    /// Apply `renice` to a single process. Privileged (negative nice needs root).
    func setNice(_ process: PriorityProcess, to value: Int) async {}

    /// Apply the target's suggested nice to every matching PID right now.
    func applyTarget(_ target: PriorityTarget) async {}

    /// Reset every managed/known process back to nice 0 and remove all
    /// "Apply at login" LaunchAgents. The emergency stop.
    func resetAll() async {}

    // MARK: - Persistence (LaunchAgents)

    func isApplyingAtLogin(_ target: PriorityTarget) -> Bool {
        FileManager.default.fileExists(atPath: plistPath(target.id))
    }

    /// Create/remove the per-target LaunchAgent that re-runs `renice` after login.
    func setApplyAtLogin(_ target: PriorityTarget, nice: Int, enabled: Bool) async {}

    // MARK: - Emergency revert contribution

    /// Shell lines that reset every known target to nice 0 and unload MacTweak's
    /// priority LaunchAgents — folded into the emergency revert script.
    nonisolated static func revertScriptLines() -> [String] {
        var lines = ["# Process priorities → reset to default (nice 0):"]
        for t in targets {
            lines.append("sudo /usr/bin/renice -n 0 -p $(pgrep -f \(shellQuote(t.pattern)) 2>/dev/null) 2>/dev/null; true")
        }
        lines.append("# Remove MacTweak priority LaunchAgents:")
        lines.append("for f in \"$HOME/Library/LaunchAgents/\"com.mactweak.priority.*.plist; do [ -f \"$f\" ] && { launchctl unload \"$f\" 2>/dev/null; rm -f \"$f\"; }; done; true")
        return lines
    }

    /// POSIX single-quote a string for safe interpolation into a shell command.
    nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Internals

    func recountManaged() {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: launchAgentDir)) ?? []
        managedCount = items.filter { $0.hasPrefix("com.mactweak.priority.") && $0.hasSuffix(".plist") }.count
    }
}
