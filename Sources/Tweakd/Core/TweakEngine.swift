//
//  TweakEngine.swift
//  tweakd
//
//  Owns live tweak state, applies/reverts, runs actions, and persists the
//  user's custom ordering and favorites. All shell work happens off the main
//  actor; published state is only mutated back on the main actor.
//

import SwiftUI
import Combine

/// Live progress of a reporting rescan (drives the scan modal's bar).
struct ScanProgress: Equatable {
    var done: Int
    var total: Int
    var current: String            // title of the last-checked tweak
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// One tweak whose real state changed between the previous scan and this one.
struct ScanChange: Identifiable, Equatable {
    let id: String                 // tweak key
    let title: String
    let from: TweakState
    let to: TweakState
}

/// Result shown when a reporting rescan finishes — the confirmation the scan ran.
struct ScanSummary: Equatable {
    var checked: Int
    var applied: Int
    var unavailable: Int
    var changes: [ScanChange]
}

@MainActor
final class TweakEngine: ObservableObject {

    let tweaks: [Tweak] = TweakCatalog.all
    let actions: [SystemAction] = TweakCatalog.actions

    @Published private(set) var state: [String: TweakState] = [:]
    @Published private(set) var busy: Set<String> = []
    @Published var lastMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var adminUnlocked = false
    @Published private(set) var batchRunning = false

    /// Fired after a single tweak's state is (re)established via `set()`. Lets
    /// the app keep Swift-side companion state in sync (e.g. the ad-block
    /// auto-updater LaunchAgent) without the data-driven catalog knowing about it.
    var onStateChange: ((Tweak) -> Void)?

    /// Non-nil while a reporting rescan is running; drives the scan modal's bar.
    @Published private(set) var scanProgress: ScanProgress?
    /// Set when a reporting rescan finishes; cleared when the user dismisses the modal.
    @Published var scanSummary: ScanSummary?

    /// Persisted custom order (tweak keys). Missing keys fall back to catalog order.
    @Published var order: [String] {
        didSet {
            UserDefaults.standard.set(order, forKey: "tweak.order")
            orderIndex = Self.indexMap(order)
        }
    }
    /// key → position, rebuilt only when `order` changes (not on every query).
    private var orderIndex: [String: Int] = [:]
    private static func indexMap(_ order: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    }
    @Published var favorites: Set<String> {
        didSet { UserDefaults.standard.set(Array(favorites), forKey: "tweak.favorites") }
    }

    init() {
        order = UserDefaults.standard.stringArray(forKey: "tweak.order") ?? TweakCatalog.all.map(\.key)
        favorites = Set(UserDefaults.standard.stringArray(forKey: "tweak.favorites") ?? [])
        // Fold in any tweaks added since the order was last saved.
        let known = Set(order)
        order += TweakCatalog.all.map(\.key).filter { !known.contains($0) }
        orderIndex = Self.indexMap(order)   // didSet doesn't fire during init
    }

    // MARK: - Queries

    func state(of tweak: Tweak) -> TweakState { state[tweak.key] ?? .unknown }

    func tweaks(in category: TweakCategory) -> [Tweak] {
        tweaks
            .filter { $0.category == category }
            .sorted { (orderIndex[$0.key] ?? 0) < (orderIndex[$1.key] ?? 0) }
    }

    var favoriteTweaks: [Tweak] {
        tweaks
            .filter { favorites.contains($0.key) }
            .sorted { (orderIndex[$0.key] ?? 0) < (orderIndex[$1.key] ?? 0) }
    }

    var appliedCount: Int { state.values.filter { $0 == .applied }.count }

    /// Applied count for a category — one pass, no sort (used by the sidebar badges).
    func appliedCount(in category: TweakCategory) -> Int {
        tweaks.reduce(0) { $0 + ($1.category == category && state(of: $1) == .applied ? 1 : 0) }
    }

    // MARK: - Ordering & favorites

    func move(in category: TweakCategory, from source: IndexSet, to destination: Int) {
        var group = tweaks(in: category).map(\.key)
        group.move(fromOffsets: source, toOffset: destination)
        // Rebuild global order: keep everything, but re-sequence this category's keys.
        var newOrder: [String] = []
        var groupIter = group.makeIterator()
        let groupSet = Set(group)
        for key in order {
            if groupSet.contains(key) {
                if let next = groupIter.next() { newOrder.append(next) }
            } else {
                newOrder.append(key)
            }
        }
        order = newOrder
    }

    func toggleFavorite(_ tweak: Tweak) {
        if favorites.contains(tweak.key) { favorites.remove(tweak.key) }
        else { favorites.insert(tweak.key) }
    }

    // MARK: - Probing

    /// Re-probe every tweak. When `reporting` is true it publishes live progress
    /// and a completion summary (with a diff of what changed) for the scan modal;
    /// the silent form is used for the boot scan and menu quick refreshes.
    func refreshAll(reporting: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshot = tweaks
        let previous = state
        let total = snapshot.count
        let titleByKey = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.key, $0.title) })
        if reporting { scanProgress = ScanProgress(done: 0, total: total, current: "") }

        // Probe concurrently — each is an independent read-only shell spawn. The
        // bar fills as real probes complete, so progress is honest, not faked.
        let probed = await withTaskGroup(of: (String, TweakState).self) { group -> [String: TweakState] in
            for t in snapshot { group.addTask { (t.key, Self.probe(t)) } }
            var result: [String: TweakState] = [:]
            for await (key, st) in group {
                result[key] = st
                if reporting {
                    scanProgress = ScanProgress(done: result.count, total: total,
                                                current: titleByKey[key] ?? "")
                }
            }
            return result
        }
        state = probed

        if reporting {
            let changes: [ScanChange] = snapshot.compactMap { t in
                let old = previous[t.key] ?? .unknown
                let new = probed[t.key] ?? .unknown
                // Ignore first-run transitions out of .unknown — not real drift.
                guard old != new, old != .unknown else { return nil }
                return ScanChange(id: t.key, title: t.title, from: old, to: new)
            }
            scanSummary = ScanSummary(
                checked: total,
                applied: probed.values.filter { $0 == .applied }.count,
                unavailable: probed.values.filter { $0 == .unavailable }.count,
                changes: changes
            )
            scanProgress = nil
        }
    }

    func refresh(_ tweak: Tweak) async {
        let probed = await Task.detached { Self.probe(tweak) }.value
        state[tweak.key] = probed
    }

    nonisolated static func probe(_ t: Tweak) -> TweakState {
        if t.sipRequired && SystemInfo.sipEnabled { return .unavailable }
        let r = CommandRunner.user(t.statusCommand)
        if r.output.isEmpty { return .notApplied }
        return r.output.localizedCaseInsensitiveContains(t.appliedWhenOutputContains)
            ? .applied : .notApplied
    }

    // MARK: - Admin unlock (authenticate once, then passwordless)

    func refreshAdminStatus() async {
        adminUnlocked = await Task.detached { CommandRunner.hasPasswordlessAdmin() }.value
    }

    func unlockAdmin() async {
        Log.info("unlockAdmin start")
        let result = await Task.detached { CommandRunner.enablePasswordlessAdmin() }.value
        Log.info("unlockAdmin done exit=\(result.exitCode) cancelled=\(result.userCancelled)")
        if result.userCancelled {
            lastMessage = "Cancelled."
            Log.audit("admin.unlock", result: .cancelled)
            return
        }
        await refreshAdminStatus()
        lastMessage = adminUnlocked
            ? "Admin unlocked — tweaks now apply without a password."
            : "Couldn't unlock admin. \(result.error.isEmpty ? result.output : result.error)"
        // Security-relevant: this installs a passwordless-sudo rule in /etc/sudoers.d.
        Log.audit("admin.unlock",
                  ["sudoers": CommandRunner.sudoersPath, "exit": "\(result.exitCode)"],
                  result: adminUnlocked ? .ok : .failed)
    }

    func lockAdmin() async {
        Log.info("lockAdmin start")
        let result = await Task.detached { CommandRunner.disablePasswordlessAdmin() }.value
        Log.info("lockAdmin done exit=\(result.exitCode) cancelled=\(result.userCancelled)")
        if result.userCancelled {
            lastMessage = "Cancelled."
            Log.audit("admin.lock", result: .cancelled)
            return
        }
        await refreshAdminStatus()
        lastMessage = adminUnlocked ? "Couldn't lock admin." : "Admin locked — your password will be required again."
        Log.audit("admin.lock",
                  ["sudoers": CommandRunner.sudoersPath, "exit": "\(result.exitCode)"],
                  result: adminUnlocked ? .failed : .ok)
    }

    /// After the macOS auth dialog closes, macOS hands focus back to whatever was
    /// frontmost before — for a menu-bar (accessory) app that means our window
    /// drops behind everything and looks like a crash. Grab focus back and raise it.
    /// Called from `CommandRunner.adminPrompt` (a background thread), so it hops to
    /// the main thread itself — every osascript prompt recovers, no call site can forget.
    nonisolated static func reactivate() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Apply / revert

    func toggle(_ tweak: Tweak) async {
        let target: TweakState = state(of: tweak) == .applied ? .notApplied : .applied
        await set(tweak, to: target)
    }

    func set(_ tweak: Tweak, to target: TweakState) async {
        guard target == .applied || target == .notApplied else { return }
        let before = state(of: tweak)
        // Common audit fields for every outcome below.
        let fields = ["key": tweak.key, "from": before.auditName, "to": target.auditName,
                      "privilege": tweak.privilege == .admin ? "admin" : "user"]

        guard before != .unavailable else {
            lastMessage = "\(tweak.title) isn't available on this Mac (SIP is enabled)."
            Log.audit("tweak.set", fields.merging(["reason": "unavailable"]) { a, _ in a }, result: .skipped)
            return
        }
        if before == target {
            Log.audit("tweak.set", fields.merging(["reason": "already-in-state"]) { a, _ in a }, result: .skipped)
            return
        }

        busy.insert(tweak.key)
        defer { busy.remove(tweak.key) }

        let command = target == .applied ? tweak.applyCommand : tweak.revertCommand
        let runner = tweak.privilegeRunner
        let result = await Task.detached { runner(command) }.value

        if result.userCancelled {
            lastMessage = "Cancelled."
            Log.audit("tweak.set", fields, result: .cancelled)
            return
        }
        // Trust the probe, not the exit code — re-read the real state.
        await refresh(tweak)
        let after = state(of: tweak)
        var audited = fields
        audited["actual"] = after.auditName
        audited["exit"] = "\(result.exitCode)"
        if after != target {
            let detail = result.error.isEmpty ? "System reported no change." : result.error
            lastMessage = "Couldn't \(target == .applied ? "apply" : "revert") \(tweak.title). \(detail)"
            audited["error"] = detail
            Log.audit("tweak.set", audited, result: .failed)
        } else {
            lastMessage = "\(tweak.title) \(target == .applied ? "applied" : "reverted")."
            Log.audit("tweak.set", audited, result: .ok)
        }
        onStateChange?(tweak)
    }

    /// Apply/revert a batch, owning the busy flag and success/failure tally.
    private func runBatch(_ items: [Tweak], to target: TweakState) async -> (done: Int, failed: Int) {
        batchRunning = true
        defer { batchRunning = false }
        var done = 0, failed = 0
        for t in items {
            await set(t, to: target)
            if state(of: t) == target { done += 1 } else { failed += 1 }
        }
        return (done, failed)
    }

    func applyRecommended() async {
        let recommended = tweaks.filter(\.recommended)
        let pending = recommended.filter { state(of: $0) == .notApplied }
        let blocked = recommended.filter { state(of: $0) == .unavailable }

        guard !pending.isEmpty else {
            let active = recommended.filter { state(of: $0) == .applied }.count
            lastMessage = blocked.isEmpty
                ? "You're all set — \(active) recommended tweaks already active."
                : "\(active) active; \(blocked.count) need SIP off."
            return
        }

        let (applied, failed) = await runBatch(pending, to: .applied)
        var msg = "Applied \(applied) tweak\(applied == 1 ? "" : "s")."
        if failed > 0 { msg += " \(failed) couldn't be applied." }
        if !blocked.isEmpty { msg += " \(blocked.count) need SIP off." }
        lastMessage = msg
    }

    func revertAll() async {
        let applied = tweaks.filter { state(of: $0) == .applied }
        guard !applied.isEmpty else { lastMessage = "Nothing to revert — everything is stock."; return }

        Log.audit("revertAll.begin", ["count": "\(applied.count)"])
        let (reverted, failed) = await runBatch(applied, to: .notApplied)
        var msg = "Reverted \(reverted) tweak\(reverted == 1 ? "" : "s") to stock."
        if failed > 0 { msg += " \(failed) couldn't be reverted." }
        lastMessage = msg
        Log.audit("revertAll.end", ["reverted": "\(reverted)", "failed": "\(failed)"],
                  result: failed == 0 ? .ok : .failed)
    }

    /// Apply a preset by its id — the menu-bar quick actions use this.
    func applyPreset(id: String) async {
        guard let p = Presets.all.first(where: { $0.id == id }) else {
            lastMessage = "That preset isn't available."
            return
        }
        await apply(preset: p)
    }

    func apply(preset: Preset) async {
        let keys = preset.keys()
        let pending = tweaks.filter { keys.contains($0.key) && state(of: $0) == .notApplied }
        guard !pending.isEmpty else {
            lastMessage = "\(preset.name): already active (\(keys.count) tweaks)."
            Log.audit("preset.apply", ["preset": preset.id, "reason": "already-active"], result: .skipped)
            return
        }
        Log.audit("preset.begin", ["preset": preset.id, "count": "\(pending.count)"])
        let (applied, failed) = await runBatch(pending, to: .applied)
        var msg = "\(preset.name) preset — applied \(applied) tweak\(applied == 1 ? "" : "s")."
        if failed > 0 { msg += " \(failed) couldn't be applied." }
        lastMessage = msg
        Log.audit("preset.end", ["preset": preset.id, "applied": "\(applied)", "failed": "\(failed)"],
                  result: failed == 0 ? .ok : .failed)
    }

    // Write a standalone shell script that reverts every tweak — a safety net if
    // a tweak ever makes the system misbehave and the app won't open.
    func writeEmergencyRevertScript() async {
        let path = Brand.revertScript
        let script = Self.buildRevertScript()
        let ok = await Task.detached { () -> Bool in
            guard (try? script.write(toFile: path, atomically: true, encoding: .utf8)) != nil else { return false }
            _ = CommandRunner.user("chmod +x '\(path)'")
            return true
        }.value
        lastMessage = ok ? "Emergency revert script saved to ~/Documents/\(Brand.name)_Revert.sh"
                         : "Couldn't write the revert script."
    }

    nonisolated static func buildRevertScript() -> String {
        var lines = [
            "#!/bin/bash",
            "# \(Brand.name) — Emergency Revert. Reverts every tweak to macOS defaults.",
            "# Run in Terminal:  bash ~/Documents/\(Brand.name)_Revert.sh",
            "set +e",
            "echo 'Reverting all \(Brand.name) tweaks…'",
            "",
            "# User-level tweaks (no sudo):",
        ]
        for t in TweakCatalog.all where t.privilege == .user {
            lines.append(t.revertCommand)
        }
        lines.append("")
        lines.append("# Admin tweaks (prompt for your password):")
        for t in TweakCatalog.all where t.privilege == .admin {
            // Single-quote the command so embedded double-quotes and $(...) reach
            // root's zsh intact instead of being mangled — or run as the user —
            // by the outer shell. POSIX single-quote escaping: ' -> '\''.
            let quoted = t.revertCommand.replacingOccurrences(of: "'", with: "'\\''")
            lines.append("sudo /bin/zsh -c '\(quoted)'")
        }
        lines.append("")
        // Reset any renice priorities and remove tweakd's priority LaunchAgents.
        lines.append(contentsOf: PriorityManager.revertScriptLines())
        lines.append("")
        lines.append("killall Dock Finder 2>/dev/null")
        lines.append("echo '✅ Done. Some changes may need a reboot.'")
        return lines.joined(separator: "\n") + "\n"
    }

    // Apply a specific set (used by the onboarding wizard).
    func apply(keys: Set<String>) async {
        let pending = tweaks.filter { keys.contains($0.key) && state(of: $0) == .notApplied }
        _ = await runBatch(pending, to: .applied)
        lastMessage = "Your tailored setup is ready."
    }

    // MARK: - Actions

    /// Free inactive memory now (the "purge-memory" quick action), surfaced as a
    /// button on the Dashboard's Memory ring.
    func clearRAM() async {
        if let a = actions.first(where: { $0.key == "purge-memory" }) { await run(a) }
    }

    func run(_ action: SystemAction) async {
        busy.insert(action.key)
        defer { busy.remove(action.key) }
        Log.info("action run: \(action.key)")
        let runner = action.runner
        let cmd = action.command
        let result = await Task.detached { runner(cmd) }.value
        Log.info("action result: \(action.key) exit=\(result.exitCode)")
        let fields = ["key": action.key,
                      "privilege": action.privilege == .admin ? "admin" : "user",
                      "destructive": action.destructive ? "yes" : "no"]
        if result.userCancelled {
            lastMessage = "Cancelled."
            Log.audit("action.run", fields, result: .cancelled)
            return
        }
        lastMessage = result.ok ? "\(action.title) — done." : "\(action.title) failed: \(result.error)"
        var audited = fields
        audited["exit"] = "\(result.exitCode)"
        if !result.ok { audited["error"] = result.error }
        Log.audit("action.run", audited, result: result.ok ? .ok : .failed)
    }
}
