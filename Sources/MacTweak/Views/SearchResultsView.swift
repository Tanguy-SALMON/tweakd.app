//
//  SearchResultsView.swift
//  MacTweak
//
//  Inline, live search results — rendered right in the main window (no modal)
//  whenever the sidebar search field has text. Matching tweaks appear as their
//  real rows, with working toggles/stars, exactly like a category tab but
//  filtered across every category at once. Pages and Quick Actions that match
//  show as quick jumps.
//

import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject var model: AppModel

    // Semantic ranking (stemming, prefix, typo & trigram tolerance) via the
    // shared engine — each corpus is scored and ordered by relevance. Ids are
    // namespaced so the engine's per-item cache never collides across corpora.

    private var tweakHits: [Tweak] {
        let byID = Dictionary(uniqueKeysWithValues: model.engine.tweaks.map { ("tweak:\($0.key)", $0) })
        let items = model.engine.tweaks.map { t in
            SearchableItem(
                id: "tweak:\(t.key)",
                title: t.title,
                body: "\(t.summary) \(t.category.rawValue) "
                    + t.tags.map(\.rawValue).joined(separator: " ") + " "
                    + t.gains.map(\.label).joined(separator: " ") + " \(t.key)")
        }
        return model.search.rank(model.searchQuery, items: items).compactMap { byID[$0] }
    }

    private var actionHits: [SystemAction] {
        let byID = Dictionary(uniqueKeysWithValues: model.engine.actions.map { ("action:\($0.key)", $0) })
        let items = model.engine.actions.map {
            SearchableItem(id: "action:\($0.key)", title: $0.title, body: "\($0.summary) \($0.key)")
        }
        return model.search.rank(model.searchQuery, items: items).compactMap { byID[$0] }
    }

    private var pageHits: [PageTarget] {
        let byID = Dictionary(uniqueKeysWithValues: Self.pages.map { ("page:\($0.id)", $0) })
        let items = Self.pages.map {
            SearchableItem(id: "page:\($0.id)", title: $0.title, body: $0.subtitle)
        }
        return model.search.rank(model.searchQuery, items: items).compactMap { byID[$0] }
    }

    var body: some View {
        // Compute each corpus once per render (query is tokenised once).
        let pages = pageHits
        let tweaks = tweakHits
        let actions = actionHits
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                header(total: pages.count + tweaks.count + actions.count)

                if pages.isEmpty && tweaks.isEmpty && actions.isEmpty {
                    emptyState
                } else {
                    if !pages.isEmpty { pagesSection(pages) }
                    if !tweaks.isEmpty { tweaksSection(tweaks) }
                    if !actions.isEmpty { actionsSection(actions) }
                }
            }
            .padding(Space.l)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private func header(total: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                Text("Search").font(.system(size: 34, weight: .bold))
                Spacer()
                Button { model.searchQuery = "" } label: {
                    Label("Clear", systemImage: "xmark")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.gradientOutline).controlSize(.small)
            }
            Text(total == 0 ? "No matches for “\(model.searchQuery)”"
                            : "\(total) result\(total == 1 ? "" : "s") for “\(model.searchQuery)”")
                .font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    private func pagesSection(_ pageHits: [PageTarget]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Pages").sectionTitle()
            ForEach(pageHits) { page in
                Button {
                    model.panel = page.panel
                    model.searchQuery = ""
                } label: {
                    HStack(spacing: Space.s) {
                        GlyphTile(systemName: page.icon, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(page.title).font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .card(padding: Space.s)
                }
                .buttonStyle(.plain).clickCursor()
            }
        }
    }

    private func tweaksSection(_ tweakHits: [Tweak]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Tweaks").sectionTitle()
            ForEach(tweakHits) { TweakRow(tweak: $0) }
        }
    }

    private func actionsSection(_ actionHits: [SystemAction]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Quick Actions").sectionTitle()
            ForEach(actionHits) { action in
                HStack(spacing: Space.s) {
                    GlyphTile(systemName: action.icon, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.title).font(.system(size: 14, weight: .semibold))
                        Text(action.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Space.xs)
                    Button(action.destructive ? "Run…" : "Run") {
                        Task { await model.engine.run(action) }
                    }
                    .buttonStyle(.gradient).controlSize(.small)
                }
                .card(padding: Space.s)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Nothing matches").font(.system(size: 15, weight: .semibold))
            Text("Try a feature name, a benefit like “battery”, or a keyword from its description.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    }

    // MARK: - Page index

    struct PageTarget: Identifiable {
        let panel: Panel
        let title: String
        let subtitle: String
        let icon: String
        var id: String { title }
    }

    static let pages: [PageTarget] = [
        .init(panel: .dashboard, title: "Dashboard", subtitle: "Overview, live CPU / memory / network", icon: "gauge.with.dots.needle.67percent"),
        .init(panel: .favorites, title: "Favorites", subtitle: "Your pinned tweaks", icon: "star"),
        .init(panel: .benchmark, title: "Benchmark", subtitle: "CPU & disk speed tests", icon: "chart.bar"),
        .init(panel: .actions, title: "Quick Actions", subtitle: "One-tap system actions", icon: "bolt"),
        .init(panel: .processPriority, title: "Process Priority", subtitle: "Renice network & UI processes", icon: "cpu"),
        .init(panel: .diskCleanup, title: "Disk Cleanup", subtitle: "Reclaim space from caches, Xcode, Docker", icon: "internaldrive"),
    ]
}
