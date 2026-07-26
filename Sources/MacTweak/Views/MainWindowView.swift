//
//  MainWindowView.swift
//  MacTweak
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Scan modal lives on the detail anchor so it doesn't collide with
            // the onboarding sheet attached to the outer view.
            .sheet(isPresented: Binding(
                get: { model.engine.scanProgress != nil || model.engine.scanSummary != nil },
                set: { if !$0 { model.engine.scanSummary = nil } }
            )) {
                ScanSheet().environmentObject(model)
                    .interactiveDismissDisabled(model.engine.scanProgress != nil)
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
                .environmentObject(model)
                .frame(width: 620, height: 560)
        }
        .overlay(alignment: .bottom) { toast }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: model.engine.lastMessage)
        .background {
            // Hidden global shortcuts — ⌘L (and ⌘K) focus the sidebar search
            // field from anywhere in the window (no modal; results render inline).
            Group {
                Button("") { model.focusSearchToken += 1 }
                    .keyboardShortcut("l", modifiers: .command)
                Button("") { model.focusSearchToken += 1 }
                    .keyboardShortcut("k", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var detail: some View {
        // An active query takes over the detail area with inline results — like
        // switching to a "search" tab. Clicking a sidebar tab cancels it (keeps
        // the query text), and re-focusing the field resumes it.
        if model.isSearching {
            SearchResultsView()
        } else {
            panelDetail
        }
    }

    @ViewBuilder private var panelDetail: some View {
        switch model.panel {
        case .dashboard: DashboardView()
        case .favorites: TweakListView(section: .favorites)
        case .benchmark: BenchmarkView()
        case .actions:   ActionsView()
        case .processPriority: ProcessPriorityView()
        case .diskCleanup: DiskCleanupView()
        case .services: ServicesView()
        case .category(let c): TweakListView(section: .category(c))
        }
    }

    @ViewBuilder private var toast: some View {
        if let msg = model.engine.lastMessage {
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .background {
                    if reduceTransparency { Capsule().fill(Theme.surface) }
                    else { Capsule().fill(.regularMaterial) }
                }
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.bottom, Space.m)
                // A status announcement so VoiceOver reads it when it appears.
                .accessibilityElement()
                .accessibilityLabel(msg)
                .accessibilityAddTraits(.updatesFrequently)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: msg) {
                    try? await Task.sleep(for: .seconds(2.6))
                    model.engine.lastMessage = nil
                }
        }
    }
}
