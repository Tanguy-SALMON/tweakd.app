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
    nonisolated static let targets: [PriorityTarget] = [
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
    nonisolated static let niceRange: ClosedRange<Int> = -10...20

    @Published private(set) var processes: [PriorityProcess] = []
    @Published private(set) var busy: Set<Int32> = []
    /// Target-level busy set — drives per-card spinners for whole-target ops
    /// (applyTarget / setApplyAtLogin) that don't map to a single pid.
    @Published private(set) var busyTargets: Set<String> = []
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
    /// + `ps -o nice`), so it never prompts.
    func refresh() async {
        refreshing = true
        defer { refreshing = false }
        let found = await Task.detached { Self.discoverProcesses() }.value
        processes = found
    }

    /// Off-main: pgrep every target, then one `ps` call for the union of pids,
    /// parsed into `[PriorityProcess]` sorted by target order then pid.
    nonisolated static func discoverProcesses() -> [PriorityProcess] {
        var claimedPIDs = Set<Int32>()
        var pidToTarget: [Int32: PriorityTarget] = [:]
        var orderedPIDs: [Int32] = []

        for target in targets {
            let result = CommandRunner.user("/usr/bin/pgrep -f \(shellQuote(target.pattern))")
            guard result.ok, !result.output.isEmpty else { continue }
            for line in result.output.split(separator: "\n") {
                guard let pid = Int32(line.trimmingCharacters(in: .whitespaces)) else { continue }
                guard !claimedPIDs.contains(pid) else { continue }   // first target wins
                claimedPIDs.insert(pid)
                pidToTarget[pid] = target
                orderedPIDs.append(pid)
            }
        }
        guard !orderedPIDs.isEmpty else { return [] }

        let psArgs = orderedPIDs.map(String.init).joined(separator: " ")
        let psResult = CommandRunner.user("/bin/ps -o pid=,nice=,comm= -p \(psArgs)")
        guard psResult.ok else { return [] }

        var byPID: [Int32: PriorityProcess] = [:]
        for line in psResult.output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, let pid = Int32(fields[0]), let nice = Int(fields[1]) else { continue }
            let command = fields[2...].joined(separator: " ")
            let name = (command as NSString).lastPathComponent
            byPID[pid] = PriorityProcess(id: pid, name: name, command: command,
                                          nice: nice, targetID: pidToTarget[pid]?.id)
        }

        let targetOrder = Dictionary(uniqueKeysWithValues: targets.enumerated().map { ($1.id, $0) })
        return orderedPIDs.compactMap { byPID[$0] }.sorted { a, b in
            let ai = a.targetID.flatMap { targetOrder[$0] } ?? Int.max
            let bi = b.targetID.flatMap { targetOrder[$0] } ?? Int.max
            if ai != bi { return ai < bi }
            return a.id < b.id
        }
    }

    // MARK: - Priority changes

    /// Apply `renice` to a single process. Privileged (negative nice needs root).
    func setNice(_ process: PriorityProcess, to value: Int) async {
        let clamped = min(max(value, Self.niceRange.lowerBound), Self.niceRange.upperBound)
        busy.insert(process.id)
        defer { busy.remove(process.id) }

        let result = await Task.detached {
            CommandRunner.admin("renice -n \(clamped) -p \(process.id)")
        }.value
        if result.userCancelled {
            lastMessage = "Cancelled."
            Log.audit("priority.setNice", ["pid": "\(process.id)", "nice": "\(clamped)"], result: .cancelled)
            return
        }

        await refresh()
        let fields = ["pid": "\(process.id)", "process": process.name,
                      "from": "\(process.nice)", "to": "\(clamped)"]
        if let updated = processes.first(where: { $0.id == process.id }), updated.nice == clamped {
            lastMessage = "\(process.name) priority set to \(clamped)."
            Log.audit("priority.setNice", fields, result: .ok)
        } else {
            let detail = result.error.isEmpty ? result.output : result.error
            lastMessage = "Couldn't change priority for \(process.name). \(detail.isEmpty ? "" : detail)"
            Log.audit("priority.setNice", fields.merging(["error": detail]) { a, _ in a }, result: .failed)
        }
    }

    /// Apply the target's suggested nice to every matching PID right now.
    func applyTarget(_ target: PriorityTarget) async {
        busyTargets.insert(target.id)
        defer { busyTargets.remove(target.id) }

        let pattern = target.pattern
        let nice = target.suggestedNice
        let pids = await Task.detached { Self.livePIDs(matching: pattern) }.value
        guard !pids.isEmpty else {
            lastMessage = "No running \(target.label) processes."
            return
        }

        let pidArgs = pids.map(String.init).joined(separator: " ")
        let result = await Task.detached {
            CommandRunner.admin("renice -n \(nice) -p \(pidArgs)")
        }.value
        if result.userCancelled {
            lastMessage = "Cancelled."
            Log.audit("priority.applyTarget", ["target": target.id, "nice": "\(nice)"], result: .cancelled)
            return
        }

        await refresh()
        lastMessage = result.ok
            ? "\(target.label): \(pids.count) process\(pids.count == 1 ? "" : "es") set to nice \(nice)."
            : "Couldn't change priority for \(target.label). \(result.error.isEmpty ? result.output : result.error)"
        Log.audit("priority.applyTarget",
                  ["target": target.id, "nice": "\(nice)", "pids": "\(pids.count)",
                   "exit": "\(result.exitCode)"],
                  result: result.ok ? .ok : .failed)
    }

    /// Reset every managed/known process back to nice 0 and remove all
    /// "Apply at login" LaunchAgents. The emergency stop.
    func resetAll() async {
        busyTargets.formUnion(Self.targets.map(\.id))
        defer { busyTargets.subtract(Self.targets.map(\.id)) }

        let patterns = Self.targets.map(\.pattern)
        let dir = launchAgentDir
        let result = await Task.detached {
            Self.resetAllOffMain(patterns: patterns, launchAgentDir: dir)
        }.value

        recountManaged()
        await refresh()
        lastMessage = result.userCancelled ? "Cancelled." : "All process priorities reset to default."
        Log.audit("priority.resetAll", ["agentsRemaining": "\(managedCount)"],
                  result: result.userCancelled ? .cancelled : .ok)
    }

    /// Off-main: renice every live pid across every target to 0, then remove
    /// every priority LaunchAgent (unload + delete).
    nonisolated static func resetAllOffMain(patterns: [String], launchAgentDir: String) -> CommandResult {
        var allPIDs = Set<Int32>()
        for pattern in patterns { allPIDs.formUnion(livePIDs(matching: pattern)) }

        var last = CommandResult(output: "", error: "", exitCode: 0)
        if !allPIDs.isEmpty {
            let pidArgs = allPIDs.map(String.init).joined(separator: " ")
            last = CommandRunner.admin("renice -n 0 -p \(pidArgs)")
        }

        let items = (try? FileManager.default.contentsOfDirectory(atPath: launchAgentDir)) ?? []
        for item in items where item.hasPrefix("com.mactweak.priority.") && item.hasSuffix(".plist") {
            let path = "\(launchAgentDir)/\(item)"
            _ = CommandRunner.user("launchctl bootout gui/$(id -u) \(shellQuote(path)) 2>/dev/null; launchctl unload \(shellQuote(path)) 2>/dev/null")
            try? FileManager.default.removeItem(atPath: path)
        }
        return last
    }

    /// Off-main helper: pgrep a pattern and return the live pids.
    nonisolated static func livePIDs(matching pattern: String) -> [Int32] {
        let result = CommandRunner.user("/usr/bin/pgrep -f \(shellQuote(pattern))")
        guard result.ok, !result.output.isEmpty else { return [] }
        return result.output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: - Persistence (LaunchAgents)

    func isApplyingAtLogin(_ target: PriorityTarget) -> Bool {
        FileManager.default.fileExists(atPath: plistPath(target.id))
    }

    /// Create/remove the per-target LaunchAgent that re-runs `renice` after login.
    func setApplyAtLogin(_ target: PriorityTarget, nice: Int, enabled: Bool) async {
        busyTargets.insert(target.id)
        defer { busyTargets.remove(target.id) }

        let path = plistPath(target.id)
        let id = target.id
        let pattern = target.pattern

        let ok = await Task.detached { () -> Bool in
            if enabled {
                return Self.installLaunchAgent(path: path, id: id, pattern: pattern, nice: nice)
            } else {
                _ = CommandRunner.user("launchctl unload \(Self.shellQuote(path)) 2>/dev/null")
                try? FileManager.default.removeItem(atPath: path)
                return true
            }
        }.value

        recountManaged()
        lastMessage = ok
            ? "\(target.label): apply at login \(enabled ? "enabled" : "disabled")."
            : "Couldn't \(enabled ? "enable" : "disable") apply-at-login for \(target.label)."
        // Persistence change: installs/removes a LaunchAgent that survives reboot.
        Log.audit("priority.applyAtLogin",
                  ["target": target.id, "enabled": enabled ? "yes" : "no", "nice": "\(nice)"],
                  result: ok ? .ok : .failed)
    }

    /// Off-main: write the LaunchAgent plist and (re)load it.
    nonisolated static func installLaunchAgent(path: String, id: String, pattern: String, nice: Int) -> Bool {
        let label = "com.mactweak.priority.\(id)"
        let shellCommand = "sleep 15; /usr/bin/sudo -n /bin/zsh -c 'renice -n \(nice) -p $(pgrep -f \"\(pattern)\")' 2>/dev/null; true"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/sh</string>
                <string>-c</string>
                <string>\(xmlEscape(shellCommand))</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard (try? plist.write(toFile: path, atomically: true, encoding: .utf8)) != nil else { return false }
        _ = CommandRunner.user("launchctl unload \(shellQuote(path)) 2>/dev/null; launchctl load \(shellQuote(path))")
        return true
    }

    /// Escape the handful of XML-significant characters for a plist string value.
    nonisolated static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

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
