//
//  SearchResultsView.swift
//  tweakd
//
//  Inline, live search results — rendered right in the main window (no modal)
//  while the sidebar search field is active. Matching tweaks appear as their
//  real rows, with working toggles/stars, exactly like a category tab but
//  filtered across every category at once. Pages and Quick Actions that match
//  show as quick jumps. The ↑/↓-highlighted row (driven from the search field)
//  is ringed and scrolled into view; ⏎ activates it.
//

import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let results = model.searchResults
        let selectedID = results.indices.contains(model.searchSelection)
            ? results[model.searchSelection].id : nil

        let pages: [SearchPage]      = results.compactMap { if case .page(let p) = $0 { return p } else { return nil } }
        let tweaks: [Tweak]          = results.compactMap { if case .tweak(let t) = $0 { return t } else { return nil } }
        let actions: [SystemAction]  = results.compactMap { if case .action(let a) = $0 { return a } else { return nil } }

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    header(total: results.count)

                    if results.isEmpty {
                        emptyState
                    } else {
                        if !pages.isEmpty { pagesSection(pages, selectedID: selectedID) }
                        if !tweaks.isEmpty { tweaksSection(tweaks, selectedID: selectedID) }
                        if !actions.isEmpty { actionsSection(actions, selectedID: selectedID) }
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.searchSelection) { _, newSel in
                let current = model.searchResults
                guard current.indices.contains(newSel) else { return }
                withAnimation(.easeOut(duration: 0.14)) { proxy.scrollTo(current[newSel].id, anchor: .center) }
            }
        }
    }

    // MARK: - Header

    private func header(total: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                Text("Search").font(.system(size: 34, weight: .bold))
                Spacer()
                Button { model.clearSearch() } label: {
                    Label("Clear", systemImage: "xmark")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.gradientOutline).controlSize(.small)
            }
            Text(total == 0 ? "No matches for “\(model.searchQuery)”"
                            : "\(total) result\(total == 1 ? "" : "s") for “\(model.searchQuery)” · ↑↓ to browse, ⏎ to open")
                .font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    private func pagesSection(_ pages: [SearchPage], selectedID: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Pages").sectionTitle()
            ForEach(pages) { page in
                let rowID = "page:\(page.id)"
                Button {
                    model.showPanel(page.panel)
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
                .selectionRing(rowID == selectedID)
                .id(rowID)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(page.title), \(page.subtitle)")
                .accessibilityAddTraits(rowID == selectedID ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint("Opens this page")
            }
        }
    }

    private func tweaksSection(_ tweaks: [Tweak], selectedID: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Tweaks").sectionTitle()
            ForEach(tweaks) { tweak in
                let rowID = "tweak:\(tweak.key)"
                TweakRow(tweak: tweak)
                    .selectionRing(rowID == selectedID)
                    .id(rowID)
            }
        }
    }

    private func actionsSection(_ actions: [SystemAction], selectedID: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Quick Actions").sectionTitle()
            ForEach(actions) { action in
                let rowID = "action:\(action.key)"
                HStack(spacing: Space.s) {
                    GlyphTile(systemName: action.icon, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.title).font(.system(size: 14, weight: .semibold))
                        Text(action.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: Space.xs)
                    Button(action.destructive ? "Run…" : "Run") {
                        Task { await model.engine.run(action) }
                    }
                    .buttonStyle(.gradient).controlSize(.small)
                    .accessibilityLabel("Run \(action.title)")
                }
                .card(padding: Space.s)
                .selectionRing(rowID == selectedID)
                .id(rowID)
                .accessibilityAddTraits(rowID == selectedID ? .isSelected : [])
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
}

// MARK: - Selection ring

private struct SelectionRing: ViewModifier {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Theme.accentGradient, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
    }
}

private extension View {
    /// Ring the row when it's the ↑/↓-highlighted result.
    func selectionRing(_ selected: Bool) -> some View { modifier(SelectionRing(selected: selected)) }
}
