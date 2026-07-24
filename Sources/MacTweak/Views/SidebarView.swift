//
//  SidebarView.swift
//  MacTweak
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // Custom rows (not List's built-in `selection:`) so the selected row wears
        // the app's orange→red gradient instead of the macOS system-blue highlight.
        List {
            Section {
                row(.dashboard, "Dashboard", "gauge.with.dots.needle.67percent")
                row(.favorites, "Favorites", "star",
                    badge: model.engine.favorites.isEmpty ? nil : "\(model.engine.favorites.count)")
                row(.benchmark, "Benchmark", "chart.bar")
                row(.actions, "Quick Actions", "bolt")
                row(.processPriority, "Process Priority", "cpu",
                    badge: model.priority.managedCount == 0 ? nil : "\(model.priority.managedCount)")
                row(.diskCleanup, "Disk Cleanup", "internaldrive")
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
        SidebarRow(title: title, icon: icon, badge: badge,
                   selected: model.panel == panel) { model.panel = panel }
            .listRowInsets(EdgeInsets(top: 1, leading: Space.xs, bottom: 1, trailing: Space.xs))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var header: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Theme.accentGradient)
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text("MacTweak").font(.system(size: 14, weight: .semibold))
                    Text("v\(appVersion)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            SearchField(text: $model.searchQuery, focusToken: model.focusSearchToken)
        }
        .padding(.horizontal, Space.s).padding(.top, Space.s).padding(.bottom, Space.xs)
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

/// A live search field. Typing filters the whole app inline (the main window
/// swaps to results) — no modal. ⌘K focuses it via `focusToken`; Escape clears.
private struct SearchField: View {
    @Binding var text: String
    let focusToken: Int
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(focused ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            TextField("Search features", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onKeyPress(.escape) { text = ""; focused = false; return .handled }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).clickCursor()
                .transition(.opacity)
            } else {
                Text("⌘K")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(.horizontal, Space.xs)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(focused ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.hairline),
                              lineWidth: focused ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.12), value: focused)
        .animation(.easeOut(duration: 0.12), value: text.isEmpty)
        .onChange(of: focusToken) { _, _ in focused = true }
    }
}

/// One navigation row. Selected → the brand orange→red gradient with white
/// content; hovered → a whisper-grey wash. Both transitions are muted so the
/// sidebar feels alive without flicker.
private struct SidebarRow: View {
    let title: String
    let icon: String
    let badge: String?
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.icon))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer(minLength: Space.xxs)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, Space.xs).padding(.vertical, 1)
                        .background(
                            selected ? AnyShapeStyle(.white.opacity(0.22))
                                     : AnyShapeStyle(Color.secondary.opacity(0.12)),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(Theme.accentGradient)
                          : AnyShapeStyle(hovering ? Color.secondary.opacity(0.12) : Color.clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .clickCursor()
        .animation(.easeOut(duration: 0.16), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
