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
        for t in tweaks where t.recommended && state(of: t) == .notApplied {
            await set(t, to: .applied)
        }
        lastMessage = "Recommended tune applied."
    }

    func revertAll() async {
        for t in tweaks where state(of: t) == .applied {
            await set(t, to: .notApplied)
        }
        lastMessage = "All tweaks reverted to stock."
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
