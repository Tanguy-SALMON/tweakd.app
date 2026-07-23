//
//  MainWindowView.swift
//  MacTweak
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var model: AppModel

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
        }
        .tint(Theme.accent)
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
                .environmentObject(model)
                .frame(width: 620, height: 560)
        }
        .overlay(alignment: .bottom) { toast }
        .animation(.spring(duration: 0.35), value: model.engine.lastMessage)
    }

    @ViewBuilder private var detail: some View {
        switch model.panel {
        case .dashboard: DashboardView()
        case .favorites: TweakListView(section: .favorites)
        case .benchmark: BenchmarkView()
        case .actions:   ActionsView()
        case .category(let c): TweakListView(section: .category(c))
        }
    }

    @ViewBuilder private var toast: some View {
        if let msg = model.engine.lastMessage {
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.bottom, Space.m)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: msg) {
                    try? await Task.sleep(for: .seconds(2.6))
                    model.engine.lastMessage = nil
                }
        }
    }
}
