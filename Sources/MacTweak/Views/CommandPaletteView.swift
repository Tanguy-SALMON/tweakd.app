//
//  CommandPaletteView.swift
//  MacTweak
//
//  A Spotlight-style command palette (⌘K): fuzzy search across every tweak,
//  quick action, preset, and panel in the app, with full keyboard navigation.
//  Presented as a floating overlay (not a system sheet) so it reads like
//  Spotlight/Raycast rather than an attached document sheet.
//

import SwiftUI

private enum SearchHit: Identifiable {
    case panel(Panel, title: String, icon: String, subtitle: String)
    case tweak(Tweak)
    case action(SystemAction)
    case preset(Preset)

    var id: String {
        switch self {
        case .panel(let p, _, _, _): return "panel-\(String(describing: p))"
        case .tweak(let t):          return "tweak-\(t.key)"
        case .action(let a):         return "action-\(a.key)"
        case .preset(let p):         return "preset-\(p.id)"
        }
    }

    var title: String {
        switch self {
        case .panel(_, let t, _, _): return t
        case .tweak(let t):          return t.title
        case .action(let a):         return a.title
        case .preset(let p):         return p.name
        }
    }

    var subtitle: String {
        switch self {
        case .panel(_, _, _, let s): return s
        case .tweak(let t):          return "\(t.category.rawValue) · \(t.summary)"
        case .action(let a):         return a.summary
        case .preset(let p):         return p.blurb
        }
    }

    var icon: String {
        switch self {
        case .panel(_, _, let i, _): return i
        case .tweak(let t):          return t.icon
        case .action(let a):         return a.icon
        case .preset(let p):         return p.icon
        }
    }
}

struct CommandPaletteView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    // MARK: - Search index

    private static let allHits: [SearchHit] = {
        let panels: [SearchHit] = [
            .panel(.dashboard, title: "Dashboard", icon: "gauge.with.dots.needle.67percent",
                   subtitle: "Overview & system health"),
            .panel(.favorites, title: "Favorites", icon: "star",
                   subtitle: "Your starred tweaks"),
            .panel(.benchmark, title: "Benchmark", icon: "chart.bar",
                   subtitle: "CPU & disk speed tests"),
            .panel(.actions, title: "Quick Actions", icon: "bolt",
                   subtitle: "One-tap system actions"),
            .panel(.processPriority, title: "Process Priority", icon: "cpu",
                   subtitle: "Renice network & UI processes"),
            .panel(.diskCleanup, title: "Disk Cleanup", icon: "internaldrive",
                   subtitle: "Reclaim space from caches, Xcode, Docker"),
        ]
        return panels
            + TweakCatalog.all.map { SearchHit.tweak($0) }
            + TweakCatalog.actions.map { SearchHit.action($0) }
            + Presets.all.map { SearchHit.preset($0) }
    }()

    private static let defaultHits: [SearchHit] = Array(allHits.prefix(6))

    private var results: [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Self.defaultHits }
        return Self.allHits
            .compactMap { hit -> (SearchHit, Int)? in
                guard let s = Self.score(hit, query: q) else { return nil }
                return (hit, s)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(24)
            .map(\.0)
    }

    /// Subsequence fuzzy match (Spotlight-style): every query character must
    /// appear in order in the target. Consecutive runs and prefix matches
    /// score higher so "cpu" ranks "CPU Priority" above "Sync Photos Update".
    private static func fuzzyScore(query: String, target: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let q = Array(query.lowercased())
        let t = Array(target.lowercased())
        var qi = 0
        var score = 0
        var lastMatch = -1
        for (ti, ch) in t.enumerated() {
            guard qi < q.count else { break }
            if ch == q[qi] {
                score += (lastMatch == ti - 1) ? 3 : 1
                lastMatch = ti
                qi += 1
            }
        }
        guard qi == q.count else { return nil }
        if t.starts(with: q) { score += 20 }
        return score
    }

    private static func score(_ hit: SearchHit, query: String) -> Int? {
        let extra: String
        switch hit {
        case .tweak(let t):  extra = "\(t.summary) \(t.category.rawValue) \(t.key)"
        case .action(let a): extra = a.summary
        case .preset(let p): extra = p.blurb
        case .panel:         extra = hit.subtitle
        }
        var best: Int?
        if let s = fuzzyScore(query: query, target: hit.title) { best = max(best ?? 0, s * 3) }
        if let s = fuzzyScore(query: query, target: extra) { best = max(best ?? 0, s) }
        return best
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                searchField
                Divider().overlay(Theme.hairline)
                if results.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .frame(width: 560)
            .frame(maxHeight: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 40, y: 20)
            .padding(.top, 90)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        .onAppear {
            selection = 0
            focused = true
        }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private var searchField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search tweaks, actions, presets…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focused)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.return) { activateSelection(); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            Text("esc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Space.xs).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(Space.m)
        .animation(.easeOut(duration: 0.12), value: query.isEmpty)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { idx, hit in
                        resultRow(hit, selected: idx == selection)
                            .id(idx)
                            .onTapGesture {
                                selection = idx
                                activateSelection()
                            }
                    }
                }
                .padding(Space.xs)
            }
            .frame(maxHeight: 360)
            .onChange(of: selection) { _, newValue in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func resultRow(_ hit: SearchHit, selected: Bool) -> some View {
        HStack(spacing: Space.s) {
            GlyphTile(systemName: hit.icon, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(hit.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            trailing(for: hit, selected: selected)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
        }
        .contentShape(Rectangle())
        .clickCursor()
        .animation(.easeOut(duration: 0.1), value: selected)
    }

    @ViewBuilder
    private func trailing(for hit: SearchHit, selected: Bool) -> some View {
        switch hit {
        case .panel:
            Image(systemName: "arrow.turn.down.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        case .tweak(let t):
            let applied = model.engine.state(of: t) == .applied
            chip(applied ? "Applied" : "Off", tinted: applied, selected: selected)
        case .action:
            chip("Run", tinted: false, selected: selected)
        case .preset:
            chip("Apply", tinted: false, selected: selected)
        }
    }

    private func chip(_ text: String, tinted: Bool, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : (tinted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary)))
            .padding(.horizontal, Space.xs).padding(.vertical, 2)
            .background(
                selected ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                in: Capsule()
            )
    }

    private var emptyState: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No matches for \u{201C}\(query)\u{201D}")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func activateSelection() {
        guard results.indices.contains(selection) else { return }
        switch results[selection] {
        case .panel(let p, _, _, _):
            model.panel = p
        case .tweak(let t):
            model.panel = .category(t.category)
        case .action(let a):
            Task { await model.engine.run(a) }
        case .preset(let p):
            Task { await model.engine.apply(preset: p) }
        }
        close()
    }

    private func close() {
        query = ""
        withAnimation(.easeOut(duration: 0.15)) { model.showSearch = false }
    }
}
