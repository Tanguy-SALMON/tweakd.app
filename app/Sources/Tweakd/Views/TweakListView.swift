//
//  TweakListView.swift
//  tweakd
//

import SwiftUI

enum TweakSection: Equatable {
    case favorites
    case category(TweakCategory)
}

struct TweakListView: View {
    @EnvironmentObject var model: AppModel
    let section: TweakSection

    private var category: TweakCategory? {
        if case .category(let c) = section { return c }
        return nil
    }

    private var items: [Tweak] {
        switch section {
        case .favorites: return model.engine.favoriteTweaks
        case .category(let c): return model.engine.tweaks(in: c)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.m)

            if items.isEmpty {
                emptyState
                Spacer(minLength: 0)
            } else {
                // A real List scrolls natively and sizes rows itself — no height
                // estimate, so nothing gets clipped.
                List {
                    ForEach(items) { tweak in
                        TweakRow(tweak: tweak)
                            .listRowInsets(EdgeInsets(top: Space.xxs, leading: Space.l,
                                                      bottom: Space.xxs, trailing: Space.l))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { source, dest in
                        if let category { model.engine.move(in: category, from: source, to: dest) }
                    }
                    Spacer(minLength: Space.m)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var header: some View {
        switch section {
        case .favorites:
            titleBlock(icon: "star", title: "Favorites",
                       blurb: "Your pinned tweaks, all in one place.")
        case .category(let c):
            titleBlock(icon: c.icon, title: c.rawValue, blurb: c.blurb)
        }
    }

    private func titleBlock(icon: String, title: String, blurb: String) -> some View {
        HeroHeader(icon: icon, title: title, blurb: blurb)
    }

    private var emptyState: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "star").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("No favorites yet").font(.system(size: 15, weight: .semibold))
            Text("Click the star on any tweak to pin it here.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    }
}
