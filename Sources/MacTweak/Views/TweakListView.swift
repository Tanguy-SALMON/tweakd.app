//
//  TweakListView.swift
//  MacTweak
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if items.isEmpty {
                    emptyState
                } else {
                    // A plain list would fight the ScrollView; render rows directly
                    // and support drag reordering only within a category.
                    if let category {
                        ReorderableTweakList(category: category)
                    } else {
                        ForEach(items) { TweakRow(tweak: $0) }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var header: some View {
        switch section {
        case .favorites:
            titleBlock(icon: "star.fill", tint: .yellow, title: "Favorites",
                       blurb: "Your pinned tweaks, all in one place.")
        case .category(let c):
            titleBlock(icon: c.icon, tint: c.tint, title: c.rawValue, blurb: c.blurb)
        }
    }

    private func titleBlock(icon: String, tint: Color, title: String, blurb: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: icon).font(.title3.weight(.bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.title, design: .rounded).weight(.bold))
                Text(blurb).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star").font(.largeTitle).foregroundStyle(.secondary)
            Text("No favorites yet").font(.headline)
            Text("Tap the star on any tweak to pin it here.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/// Category rows in a real List so `.onMove` drag-reordering works.
private struct ReorderableTweakList: View {
    @EnvironmentObject var model: AppModel
    let category: TweakCategory

    var body: some View {
        let items = model.engine.tweaks(in: category)
        List {
            ForEach(items) { tweak in
                TweakRow(tweak: tweak)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { model.engine.move(in: category, from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(items.count) * 104 + 8)
    }
}
