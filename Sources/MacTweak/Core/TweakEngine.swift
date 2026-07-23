//
//  TweakEngine.swift
//  MacTweak
//
//  Owns live tweak state, applies/reverts, runs actions, and persists the
//  user's custom ordering and favorites. All shell work happens off the main
//  actor; published state is only mutated back on the main actor.
//

import SwiftUI
import Combine

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

    /// Persisted custom order (tweak keys). Missing keys fall back to catalog order.
    @Published var order: [String] {
        didSet { UserDefaults.standard.set(order, forKey: "tweak.order") }
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
    }

    // MARK: - Queries

    func state(of tweak: Tweak) -> TweakState { state[tweak.key] ?? .unknown }

    func tweaks(in category: TweakCategory) -> [Tweak] {
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return tweaks
            .filter { $0.category == category }
            .sorted { (index[$0.key] ?? 0) < (index[$1.key] ?? 0) }
    }

    var favoriteTweaks: [Tweak] {
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return tweaks
            .filter { favorites.contains($0.key) }
            .sorted { (index[$0.key] ?? 0) < (index[$1.key] ?? 0) }
    }

    var appliedCount: Int { state.values.filter { $0 == .applied }.count }

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

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshot = tweaks
        let probed: [String: TweakState] = await Task.detached {
            var result: [String: TweakState] = [:]
            for t in snapshot { result[t.key] = Self.probe(t) }
            return result
        }.value
        state = probed
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
        let result = await Task.detached { CommandRunner.enablePasswordlessAdmin() }.value
        if result.userCancelled { lastMessage = "Cancelled."; return }
        await refreshAdminStatus()
        lastMessage = adminUnlocked
            ? "Admin unlocked — tweaks now apply without a password."
            : "Couldn't unlock admin. \(result.error.isEmpty ? result.output : result.error)"
    }

    func lockAdmin() async {
        let result = await Task.detached { CommandRunner.disablePasswordlessAdmin() }.value
        if result.userCancelled { lastMessage = "Cancelled."; return }
        await refreshAdminStatus()
        lastMessage = adminUnlocked ? "Couldn't lock admin." : "Admin locked — your password will be required again."
    }

    // MARK: - Apply / revert

    func toggle(_ tweak: Tweak) async {
        let target: TweakState = state(of: tweak) == .applied ? .notApplied : .applied
        await set(tweak, to: target)
    }

    func set(_ tweak: Tweak, to target: TweakState) async {
        guard target == .applied || target == .notApplied else { return }
        guard state(of: tweak) != .unavailable else {
            lastMessage = "\(tweak.title) isn't available on this Mac (SIP is enabled)."
            return
        }
        if state(of: tweak) == target { return }

        busy.insert(tweak.key)
        defer { busy.remove(tweak.key) }

        let command = target == .applied ? tweak.applyCommand : tweak.revertCommand
        let runner = tweak.privilegeRunner
        let result = await Task.detached { runner(command) }.value

        if result.userCancelled {
            lastMessage = "Cancelled."
            return
        }
        // Trust the probe, not the exit code — re-read the real state.
        await refresh(tweak)
        if state(of: tweak) != target {
            let detail = result.error.isEmpty ? "System reported no change." : result.error
            lastMessage = "Couldn't \(target == .applied ? "apply" : "revert") \(tweak.title). \(detail)"
        } else {
            lastMessage = "\(tweak.title) \(target == .applied ? "applied" : "reverted")."
        }
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

        batchRunning = true
        var applied = 0, failed = 0
        for t in pending {
            await set(t, to: .applied)
            if state(of: t) == .applied { applied += 1 } else { failed += 1 }
        }
        batchRunning = false

        var msg = "Applied \(applied) tweak\(applied == 1 ? "" : "s")."
        if failed > 0 { msg += " \(failed) couldn't be applied." }
        if !blocked.isEmpty { msg += " \(blocked.count) need SIP off." }
        lastMessage = msg
    }

    func revertAll() async {
        let applied = tweaks.filter { state(of: $0) == .applied }
        guard !applied.isEmpty else { lastMessage = "Nothing to revert — everything is stock."; return }

        batchRunning = true
        var reverted = 0, failed = 0
        for t in applied {
            await set(t, to: .notApplied)
            if state(of: t) == .notApplied { reverted += 1 } else { failed += 1 }
        }
        batchRunning = false

        var msg = "Reverted \(reverted) tweak\(reverted == 1 ? "" : "s") to stock."
        if failed > 0 { msg += " \(failed) couldn't be reverted." }
        lastMessage = msg
    }

    func apply(preset: Preset) async {
        let keys = preset.keys()
        let pending = tweaks.filter { keys.contains($0.key) && state(of: $0) == .notApplied }
        guard !pending.isEmpty else {
            lastMessage = "\(preset.name): already active (\(keys.count) tweaks)."
            return
        }
        batchRunning = true
        var applied = 0, failed = 0
        for t in pending {
            await set(t, to: .applied)
            if state(of: t) == .applied { applied += 1 } else { failed += 1 }
        }
        batchRunning = false
        var msg = "\(preset.name) preset — applied \(applied) tweak\(applied == 1 ? "" : "s")."
        if failed > 0 { msg += " \(failed) couldn't be applied." }
        lastMessage = msg
    }

    // Write a standalone shell script that reverts every tweak — a safety net if
    // a tweak ever makes the system misbehave and the app won't open.
    func writeEmergencyRevertScript() async {
        let path = "\(NSHomeDirectory())/Documents/MacTweak_Revert.sh"
        let script = Self.buildRevertScript()
        let ok = await Task.detached { () -> Bool in
            guard (try? script.write(toFile: path, atomically: true, encoding: .utf8)) != nil else { return false }
            _ = CommandRunner.user("chmod +x '\(path)'")
            return true
        }.value
        lastMessage = ok ? "Emergency revert script saved to ~/Documents/MacTweak_Revert.sh"
                         : "Couldn't write the revert script."
    }

    nonisolated static func buildRevertScript() -> String {
        var lines = [
            "#!/bin/bash",
            "# MacTweak — Emergency Revert. Reverts every tweak to macOS defaults.",
            "# Run in Terminal:  bash ~/Documents/MacTweak_Revert.sh",
            "set +e",
            "echo 'Reverting all MacTweak tweaks…'",
            "",
            "# User-level tweaks (no sudo):",
        ]
        for t in TweakCatalog.all where t.privilege == .user {
            lines.append(t.revertCommand)
        }
        lines.append("")
        lines.append("# Admin tweaks (prompt for your password):")
        for t in TweakCatalog.all where t.privilege == .admin {
            lines.append("sudo /bin/zsh -c \"\(t.revertCommand)\"")
        }
        lines.append("")
        lines.append("killall Dock Finder 2>/dev/null")
        lines.append("echo '✅ Done. Some changes may need a reboot.'")
        return lines.joined(separator: "\n") + "\n"
    }

    // Apply a specific set (used by the onboarding wizard).
    func apply(keys: Set<String>) async {
        for t in tweaks where keys.contains(t.key) && state(of: t) == .notApplied {
            await set(t, to: .applied)
        }
        lastMessage = "Your tailored setup is ready."
    }

    // MARK: - Actions

    func run(_ action: SystemAction) async {
        busy.insert(action.key)
        defer { busy.remove(action.key) }
        let runner = action.runner
        let cmd = action.command
        let result = await Task.detached { runner(cmd) }.value
        if result.userCancelled { lastMessage = "Cancelled."; return }
        lastMessage = result.ok ? "\(action.title) — done." : "\(action.title) failed: \(result.error)"
    }
}
