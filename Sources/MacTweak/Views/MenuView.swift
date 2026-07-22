//
//  MenuView.swift
//  MacTweak
//
//  The menu-bar dropdown: live stats, favorites quick-toggles, and shortcuts.
//

import SwiftUI

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 10) {
                miniStat("cpu", "CPU", "\(Int(model.metrics.cpuPercent))%", .blue)
                miniStat("memorychip", "MEM", "\(Int(model.metrics.memUsedPercent))%", .purple)
                miniStat("checkmark.seal.fill", "TWEAKS", "\(model.engine.appliedCount)", .green)
            }

            Divider()

            if model.engine.favoriteTweaks.isEmpty {
                Text("Pin tweaks with the ★ to control them here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.engine.favoriteTweaks.prefix(6)) { tweak in
                        favoriteRow(tweak)
                    }
                }
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("Open MacTweak", systemImage: "macwindow").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.engine.applyRecommended() }
            } label: {
                Label("Apply Recommended", systemImage: "wand.and.sparkles").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.brand).frame(width: 24, height: 24)
                .overlay(Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
            Text("MacTweak").font(.headline)
            Spacer()
        }
    }

    private func miniStat(_ icon: String, _ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).font(.system(.body, design: .rounded).weight(.bold))
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func favoriteRow(_ tweak: Tweak) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tweak.category.icon).foregroundStyle(tweak.category.tint).frame(width: 18)
            Text(tweak.title).font(.callout).lineLimit(1)
            Spacer()
            if model.engine.busy.contains(tweak.key) {
                ProgressView().controlSize(.small)
            } else {
                Toggle("", isOn: Binding(
                    get: { model.engine.state(of: tweak) == .applied },
                    set: { _ in Task { await model.engine.toggle(tweak) } }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .disabled(model.engine.state(of: tweak) == .unavailable)
            }
        }
    }
}
