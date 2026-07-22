//
//  MainWindowView.swift
//  MacTweak
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            ZStack {
                Theme.heroBackground(scheme)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                .shadow(radius: 12, y: 4)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: msg) {
                    try? await Task.sleep(for: .seconds(2.6))
                    model.engine.lastMessage = nil
                }
        }
    }
}
