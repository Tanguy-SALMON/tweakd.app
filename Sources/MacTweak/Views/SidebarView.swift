//
//  SidebarView.swift
//  MacTweak
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: Binding(
            get: { model.panel },
            set: { if let p = $0 { model.panel = p } }
        )) {
            Section {
                row(.dashboard, "Dashboard", "gauge.with.dots.needle.67percent", .blue)
                row(.favorites, "Favorites", "star.fill", .yellow,
                    badge: model.engine.favorites.isEmpty ? nil : "\(model.engine.favorites.count)")
                row(.benchmark, "Benchmark", "chart.bar.xaxis", .orange)
                row(.actions, "Quick Actions", "bolt.badge.automatic", .green)
            }

            Section("Tweaks") {
                ForEach(TweakCategory.allCases) { c in
                    row(.category(c), c.rawValue, c.icon, c.tint,
                        badge: appliedBadge(c))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private func appliedBadge(_ c: TweakCategory) -> String? {
        let n = model.engine.tweaks(in: c).filter { model.engine.state(of: $0) == .applied }.count
        return n == 0 ? nil : "\(n)"
    }

    private func row(_ panel: Panel, _ title: String, _ icon: String, _ tint: Color, badge: String? = nil) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .tag(panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.brand)
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 0) {
                Text("MacTweak").font(.headline)
                Text("v\(appVersion)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.bar)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                model.wizard = WizardAnswers()
                model.showOnboarding = true
            } label: {
                Label("Guided Setup", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)

            Button {
                Task { await model.engine.refreshAll() }
            } label: {
                Label(model.engine.isRefreshing ? "Refreshing…" : "Re-scan", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.engine.isRefreshing)
        }
        .padding(12)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
