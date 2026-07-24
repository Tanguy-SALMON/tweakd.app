//
//  AppModel.swift
//  MacTweak
//
//  Shared app state: the engine, live metrics, benchmarks, navigation, and the
//  onboarding wizard's answers.
//

import SwiftUI
import Combine

enum Panel: Hashable {
    case dashboard
    case favorites
    case benchmark
    case actions
    case processPriority
    case diskCleanup
    case category(TweakCategory)
}

@MainActor
final class AppModel: ObservableObject {
    let engine = TweakEngine()
    let metrics = SystemMetrics()
    let benchmark = BenchmarkEngine()
    let audioWatchdog = CoreAudioWatchdog()
    let priority = PriorityManager()
    let diskCleanup = DiskCleanupManager()
    let adBlock = AdBlockManager()
    /// Offline semantic search over the feature catalog (stemming, typo & fuzzy
    /// tolerance). Held here so its per-item token index is built once and reused.
    let search = FeatureSearchEngine()

    @Published var panel: Panel = .dashboard
    @Published var showOnboarding = false
    /// Live search text. When non-empty, the main window shows filtered results
    /// inline (instead of the current panel) — no modal.
    @Published var searchQuery = ""
    /// Bumped to ask the sidebar search field to grab focus (⌘K).
    @Published var focusSearchToken = 0
    @Published var wizard = WizardAnswers()

    @AppStorage("didOnboard") private var didOnboard = false
    private var booted = false
    private var bag = Set<AnyCancellable>()

    init() {
        boot()
        // Nested ObservableObjects don't propagate through the parent on their
        // own — forward the ones whose changes should refresh AppModel-bound UI.
        // (metrics tick every second and are observed directly by the metric
        // views, so they're intentionally not forwarded here.)
        engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        benchmark.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        priority.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        diskCleanup.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)

        // Keep the ad-block weekly auto-updater LaunchAgent in step with the
        // "Block Ads & Trackers" tweak whenever it's toggled.
        engine.onStateChange = { [weak self] tweak in
            guard let self, tweak.key == "hosts-adblock" else { return }
            self.adBlock.reconcile(adBlockApplied: self.engine.state(of: tweak) == .applied)
        }
    }

    func boot() {
        guard !booted else { return }
        booted = true
        // Metrics sampling is ref-counted by the views that show it (retain/
        // release) so it never runs while no gauge is on screen.
        // Warm the lazy `csrutil status` / sysctl probes off-main so the first
        // Dashboard render doesn't block on them.
        Task.detached { _ = SystemInfo.sipEnabled; _ = SystemInfo.chip }
        Task {
            await engine.refreshAdminStatus()
            await engine.refreshAll()
            // Reconcile the weekly ad-block updater with the tweak's real state
            // once probes have run (installs the agent if the block is active
            // but the agent went missing; removes a stale agent otherwise).
            if let t = engine.tweaks.first(where: { $0.key == "hosts-adblock" }) {
                adBlock.reconcile(adBlockApplied: engine.state(of: t) == .applied)
            }
        }
        audioWatchdog.configure(engine: engine)
        if !didOnboard { showOnboarding = true }
    }

    func finishOnboarding(apply: Bool) async {
        if apply {
            await engine.apply(keys: wizard.recommendedKeys())
        }
        didOnboard = true
        showOnboarding = false
    }
}

// MARK: - Onboarding answers & recommendation logic

enum Priority: String, CaseIterable, Identifiable {
    case battery = "Battery life"
    case balanced = "Balanced"
    case performance = "Performance"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .battery: return "leaf.fill"
        case .balanced: return "circle.lefthalf.filled"
        case .performance: return "flame.fill"
        }
    }
}

struct WizardAnswers {
    var usesAI = true
    var usesSpotlight = true
    var usesPhotos = true
    var usesAirDrop = true
    var privacyFocused = false
    var wantsSnappyUI = true
    var priority: Priority = .balanced
    var runsNetworkServices = false   // web servers, SSH, containers → server/low-latency tuning
    var hardenSecurity = false        // prefers security over convenience → firewall/stealth
    var needsLowLatency = false       // gaming / remote desktop → network + priority boosts

    /// Turn the answers into a tailored set of tweak keys.
    func recommendedKeys() -> Set<String> {
        var keys = Set<String>()
        for t in TweakCatalog.all {
            // Never auto-pick advanced or SIP-blocked tweaks.
            if t.risk == .advanced { continue }
            if t.sipRequired && SystemInfo.sipEnabled { continue }

            // Respect features the user wants to keep.
            if t.tags.contains(.usesAI) && usesAI { continue }
            if t.tags.contains(.usesSpotlight) && usesSpotlight { continue }
            if t.tags.contains(.usesPhotos) && usesPhotos { continue }
            if t.tags.contains(.usesAirDropAirPlay) && usesAirDrop { continue }

            var include = t.recommended
            if wantsSnappyUI && t.tags.contains(.snappyUI) { include = true }
            if privacyFocused && t.tags.contains(.privacyFocused) { include = true }
            if priority == .performance && t.tags.contains(.prioritizePerformance) { include = true }
            if priority == .battery && t.tags.contains(.prioritizeBattery) { include = true }
            if hardenSecurity && t.tags.contains(.security) { include = true }
            if runsNetworkServices && t.tags.contains(.serverWorkload) { include = true }
            if needsLowLatency && t.tags.contains(.lowLatency) { include = true }

            if include { keys.insert(t.key) }
        }
        return keys
    }
}
