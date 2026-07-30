//
//  SidebarView.swift
//  tweakd
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
                row(.services, "Services", "square.stack.3d.up",
                    badge: model.services.runningCount == 0 ? nil : "\(model.services.runningCount)")
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
                   selected: model.panel == panel && !model.isSearching) { model.showPanel(panel) }
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
                    Text(Brand.name).font(.system(size: 14, weight: .semibold))
                    Text("v\(appVersion)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            SearchField()
        }
        .padding(.horizontal, Space.s).padding(.top, Space.s).padding(.bottom, Space.xs)
        .background {
            // Solid fill instead of the translucent bar when the user asks to
            // reduce transparency.
            if reduceTransparency { Theme.canvas } else { Rectangle().fill(.bar) }
        }
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
/// swaps to results) — no modal. ⌘L (or ⌘K) focuses it; ↑/↓ browse the results
/// and ⏎ activates the highlighted one; Escape clears. Focusing the field
/// re-activates a query that a tab click had paused.
private struct SearchField: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(focused ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            TextField("Search features", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onKeyPress(.downArrow) { model.moveSearchSelection(1); return .handled }
                .onKeyPress(.upArrow)   { model.moveSearchSelection(-1); return .handled }
                .onKeyPress(.return)    { model.activateSelectedSearchResult(); return .handled }
                .onKeyPress(.escape)    { model.clearSearch(); focused = false; return .handled }
                .accessibilityLabel("Search features")
                .accessibilityHint("Up and down arrows browse results, return opens the highlighted one, escape clears")
            if !model.searchQuery.isEmpty {
                Button { model.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).clickCursor()
                .transition(.opacity)
            } else {
                Text("⌘L")
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
        .animation(.easeOut(duration: 0.12), value: model.searchQuery.isEmpty)
        .onChange(of: model.focusSearchToken) { _, _ in focused = true }
        // Focusing the field resumes search (even a query a tab click paused).
        .onChange(of: focused) { _, now in if now { model.searchActive = true } }
        // A tab click cancels search → blur the field, so clicking back into it
        // is a real focus transition that resumes the query.
        .onChange(of: model.searchActive) { _, now in if !now { focused = false } }
        // Typing resets the ↑/↓ highlight and re-activates search.
        .onChange(of: model.searchQuery) { _, _ in
            model.searchSelection = 0
            if focused { model.searchActive = true }
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Opens the \(title) page")
    }
}
