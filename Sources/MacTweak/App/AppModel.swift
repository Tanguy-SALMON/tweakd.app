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

/// A navigable page surfaced in search results (the non-tweak destinations).
struct SearchPage: Identifiable, Hashable {
    let panel: Panel
    let title: String
    let subtitle: String
    let icon: String
    var id: String { title }
}

/// One row in the flat, ranked search result list — used both to render the
/// results and to drive keyboard (↑/↓/⏎) navigation over them.
enum SearchResultRow: Identifiable {
    case page(SearchPage)
    case tweak(Tweak)
    case action(SystemAction)

    var id: String {
        switch self {
        case .page(let p):   return "page:\(p.id)"
        case .tweak(let t):  return "tweak:\(t.key)"
        case .action(let a): return "action:\(a.key)"
        }
    }
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
    let thermal = ThermalMonitor()
    /// Offline semantic search over the feature catalog (stemming, typo & fuzzy
    /// tolerance). Held here so its per-item token index is built once and reused.
    let search = FeatureSearchEngine()

    @Published var panel: Panel = .dashboard
    @Published var showOnboarding = false
    /// Live search text. Kept even when a tab is clicked, so re-focusing the
    /// search field resumes the same query.
    @Published var searchQuery = ""
    /// Whether the search view is currently taking over the detail area. Set true
    /// when the field gains focus / the user types; set false when a tab is
    /// clicked (which cancels back to the panel without losing the query text).
    @Published var searchActive = false
    /// Highlighted result index for ↑/↓ keyboard navigation.
    @Published var searchSelection = 0
    /// Bumped to ask the sidebar search field to grab focus (⌘L).
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

    // MARK: - Search

    /// The non-tweak destinations search can jump to.
    static let searchPages: [SearchPage] = [
        .init(panel: .dashboard, title: "Dashboard", subtitle: "Overview, live CPU / memory / network", icon: "gauge.with.dots.needle.67percent"),
        .init(panel: .favorites, title: "Favorites", subtitle: "Your pinned tweaks", icon: "star"),
        .init(panel: .benchmark, title: "Benchmark", subtitle: "CPU & disk speed tests", icon: "chart.bar"),
        .init(panel: .actions, title: "Quick Actions", subtitle: "One-tap system actions", icon: "bolt"),
        .init(panel: .processPriority, title: "Process Priority", subtitle: "Renice network & UI processes", icon: "cpu"),
        .init(panel: .diskCleanup, title: "Disk Cleanup", subtitle: "Reclaim space from caches, Xcode, Docker", icon: "internaldrive"),
    ]

    /// True while search results are taking over the detail area (active + a
    /// non-blank query). Drives both the detail switch and sidebar de-selection.
    var isSearching: Bool {
        searchActive && !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The flat, relevance-ranked result list (pages, then tweaks, then actions),
    /// each group ordered by the semantic engine. Empty unless actively searching.
    var searchResults: [SearchResultRow] {
        guard isSearching else { return [] }
        let q = searchQuery

        let pageByID = Dictionary(uniqueKeysWithValues: Self.searchPages.map { ("page:\($0.id)", $0) })
        let pageItems = Self.searchPages.map { SearchableItem(id: "page:\($0.id)", title: $0.title, body: $0.subtitle) }
        let pages = search.rank(q, items: pageItems).compactMap { pageByID[$0] }.map(SearchResultRow.page)

        let tweakByID = Dictionary(uniqueKeysWithValues: engine.tweaks.map { ("tweak:\($0.key)", $0) })
        let tweakItems = engine.tweaks.map { t in
            SearchableItem(id: "tweak:\(t.key)", title: t.title,
                body: "\(t.summary) \(t.category.rawValue) "
                    + t.tags.map(\.rawValue).joined(separator: " ") + " "
                    + t.gains.map(\.label).joined(separator: " ") + " \(t.key)")
        }
        let tweaks = search.rank(q, items: tweakItems).compactMap { tweakByID[$0] }.map(SearchResultRow.tweak)

        let actionByID = Dictionary(uniqueKeysWithValues: engine.actions.map { ("action:\($0.key)", $0) })
        let actionItems = engine.actions.map { SearchableItem(id: "action:\($0.key)", title: $0.title, body: "\($0.summary) \($0.key)") }
        let actions = search.rank(q, items: actionItems).compactMap { actionByID[$0] }.map(SearchResultRow.action)

        return pages + tweaks + actions
    }

    /// Navigate to a panel (sidebar click) — cancels the search overlay but keeps
    /// the query text so re-focusing the field resumes it.
    func showPanel(_ p: Panel) {
        panel = p
        searchActive = false
    }

    func clearSearch() {
        searchQuery = ""
        searchSelection = 0
        searchActive = false
    }

    /// Move the ↑/↓ selection, clamped to the current result count.
    func moveSearchSelection(_ delta: Int) {
        let count = searchResults.count
        guard count > 0 else { searchSelection = 0; return }
        searchSelection = min(max(searchSelection + delta, 0), count - 1)
    }

    /// Activate the highlighted result: navigate for pages/tweaks, run for actions.
    func activateSelectedSearchResult() {
        let results = searchResults
        guard results.indices.contains(searchSelection) else { return }
        switch results[searchSelection] {
        case .page(let p):   showPanel(p.panel)
        case .tweak(let t):  showPanel(.category(t.category))
        case .action(let a): Task { await engine.run(a) }
        }
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
            // On a fanless Mac, tweaks that let *more* work run concurrently
            // spend thermal budget the foreground app needs — the ceiling there
            // is heat, not scheduling. Documented in docs/TWEAKS.md.
            if t.tags.contains(.needsActiveCooling) && SystemInfo.isFanless { continue }

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
