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
                row(.dashboard, "Dashboard", "gauge.with.dots.needle.67percent")
                row(.favorites, "Favorites", "star",
                    badge: model.engine.favorites.isEmpty ? nil : "\(model.engine.favorites.count)")
                row(.benchmark, "Benchmark", "chart.bar")
                row(.actions, "Quick Actions", "bolt")
            }

            Section("Tweaks") {
                ForEach(TweakCategory.allCases) { c in
                    row(.category(c), c.rawValue, c.icon, badge: appliedBadge(c))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private func appliedBadge(_ c: TweakCategory) -> String? {
        let n = model.engine.appliedCount(in: c)
        return n == 0 ? nil : "\(n)"
    }

    private func row(_ panel: Panel, _ title: String, _ icon: String, badge: String? = nil) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Space.xs).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(.secondary)
        }
        .tag(panel)
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 0) {
                Text("MacTweak").font(.system(size: 14, weight: .semibold))
                Text("v\(appVersion)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.s)
        .background(.bar)
    }

    private var footer: some View {
        VStack(spacing: Space.xs) {
            Button {
                model.wizard = WizardAnswers()
                model.showOnboarding = true
            } label: {
                Label("Guided Setup", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.gradient)

            Button {
                Task { await model.engine.refreshAll(reporting: true) }
            } label: {
                Label(model.engine.isRefreshing ? "Refreshing…" : "Re-scan", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.gradientOutline)
            .disabled(model.engine.isRefreshing)
        }
        .controlSize(.large)
        .padding(Space.s)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
