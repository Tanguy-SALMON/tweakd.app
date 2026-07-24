//
//  DiskCleanupView.swift
//  MacTweak
//
//  The "Disk Cleanup" pane: every dev-machine space hog (Xcode caches,
//  simulator junk, package-manager caches, Docker's Docker.raw) with a
//  measured size and a one-tap clear — the terminal dance from a support
//  chat, turned into cards.
//

import SwiftUI

struct DiskCleanupView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmingItemID: String?
    @State private var confirmingOrphaned = false

    private var cleanup: DiskCleanupManager { model.diskCleanup }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                header
                if cleanup.totalReclaimableBytes > 0 {
                    reclaimableBanner
                }
                orphanedCard
                ForEach(DiskCleanupManager.items) { item in
                    itemCard(item)
                }
            }
            .padding(Space.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task {
            await cleanup.scan()
            await cleanup.scanOrphaned()
        }
        .confirmationDialog(
            confirmingItem.map { "\($0.actionLabel) \($0.title)?" }
                ?? (confirmingOrphaned ? "Remove \(cleanup.orphanedPaths.count) orphaned leftover\(cleanup.orphanedPaths.count == 1 ? "" : "s")?" : ""),
            isPresented: Binding(
                get: { confirmingItemID != nil || confirmingOrphaned },
                set: { if !$0 { confirmingItemID = nil; confirmingOrphaned = false } }
            )
        ) {
            if let item = confirmingItem {
                Button(item.actionLabel, role: .destructive) {
                    Task { await cleanup.clean(item) }
                }
                Button("Cancel", role: .cancel) {}
            } else if confirmingOrphaned {
                Button("Remove", role: .destructive) {
                    Task { await cleanup.cleanOrphaned() }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(confirmingItem?.blurb ?? "These belong to apps no longer installed on this Mac. This can't be undone.")
        }
    }

    private var confirmingItem: CleanupItem? {
        DiskCleanupManager.items.first { $0.id == confirmingItemID }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s) {
            HeroHeader(icon: "internaldrive.fill", title: "Disk Cleanup",
                       blurb: "Find and reclaim space taken by caches, build artifacts, and container images.")
            Spacer(minLength: Space.xs)
            Button {
                Task { await cleanup.scan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.gradientOutline)
            .controlSize(.small)
            .disabled(cleanup.scanning)
            .padding(.top, Space.xs)
        }
    }

    private var reclaimableBanner: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(Theme.accentGradient)
            Text("~\(formattedGB(cleanup.totalReclaimableBytes)) reclaimable right now.")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .card(padding: Space.s)
    }

    private func formattedGB(_ bytes: Double) -> String {
        let gb = bytes / 1_000_000_000
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", bytes / 1_000_000)
    }

    // MARK: - Orphaned leftovers

    private var orphanedCard: some View {
        let busy = cleanup.busy.contains("orphaned-leftovers") || cleanup.scanningOrphaned
        let count = cleanup.orphanedPaths.count

        return HStack(spacing: Space.s) {
            GlyphTile(systemName: "questionmark.folder", size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.xs) {
                    Text("Orphaned App Leftovers").font(.system(size: 15, weight: .semibold))
                    if !cleanup.scanningOrphaned {
                        Pill(text: count == 0 ? "None found" : "\(count) found · \(formatBytes(UInt64(max(0, cleanup.orphanedBytes))))")
                    }
                }
                Text("Caches, saved state, and support files for apps you've already deleted — cross-checked against everything still in /Applications.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.xs)
            if busy {
                ProgressView().controlSize(.small)
            } else if count > 0 {
                Button("Remove") { confirmingOrphaned = true }
                    .buttonStyle(.gradient).controlSize(.small)
            }
        }
        .card()
        .animation(.easeOut(duration: 0.15), value: busy)
        .animation(.easeOut(duration: 0.15), value: count)
    }

    // MARK: - Item card

    private func itemCard(_ item: CleanupItem) -> some View {
        let isAvailable = cleanup.available[item.id] ?? true
        let busy = cleanup.busy.contains(item.id)
        let size = cleanup.sizes[item.id]

        return HStack(spacing: Space.s) {
            GlyphTile(systemName: item.icon, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.xs) {
                    Text(item.title).font(.system(size: 15, weight: .semibold))
                    if isAvailable, let size {
                        Pill(text: size)
                    }
                    if item.risk != .safe {
                        Pill(text: item.risk.label)
                    }
                }
                Text(item.blurb).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.xs)
            trailing(item, isAvailable: isAvailable, busy: busy)
        }
        .card()
        .opacity(isAvailable ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: busy)
        .animation(.easeOut(duration: 0.15), value: isAvailable)
    }

    @ViewBuilder
    private func trailing(_ item: CleanupItem, isAvailable: Bool, busy: Bool) -> some View {
        if cleanup.sizes[item.id] == nil && cleanup.scanning {
            ProgressView().controlSize(.small)
        } else if !isAvailable {
            Text("Not installed").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if busy {
            ProgressView().controlSize(.small)
        } else {
            Button(item.actionLabel) {
                if item.destructive {
                    confirmingItemID = item.id
                } else {
                    Task { await cleanup.clean(item) }
                }
            }
            .buttonStyle(.gradient)
            .controlSize(.small)
        }
    }
}
