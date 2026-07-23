//
//  ActionsView.swift
//  MacTweak
//

import SwiftUI

struct ActionsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirming: SystemAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                HeroHeader(icon: "bolt", title: "Quick Actions",
                           blurb: "One-shot maintenance. Nothing here is permanent.")
                    .padding(.bottom, Space.xxs)

                emergencyScriptRow

                ForEach(model.engine.actions) { action in
                    row(action)
                }
            }
            .padding(Space.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Run \(confirming?.title ?? "")?",
                            isPresented: Binding(get: { confirming != nil },
                                                 set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { action in
            Button("Run \(action.title)", role: .destructive) {
                Task { await model.engine.run(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.summary)
        }
    }

    private var emergencyScriptRow: some View {
        HStack(spacing: Space.s) {
            GlyphTile(systemName: "cross.case", size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("Create Emergency Revert Script").font(.system(size: 15, weight: .semibold))
                Text("Writes ~/Documents/MacTweak_Revert.sh — reverts every tweak from Terminal if the app can't.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.xs)
            Button("Create") {
                Task { await model.engine.writeEmergencyRevertScript() }
            }
            .buttonStyle(.borderedProminent)
        }
        .card()
    }

    private func row(_ action: SystemAction) -> some View {
        HStack(spacing: Space.s) {
            GlyphTile(systemName: action.icon, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.xs) {
                    Text(action.title).font(.system(size: 15, weight: .semibold))
                    if action.privilege == .admin {
                        Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if action.destructive {
                        Pill(text: "Rebuilds data")
                    }
                }
                Text(action.summary).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.xs)
            if model.engine.busy.contains(action.key) {
                ProgressView().controlSize(.small)
            } else {
                Button("Run") {
                    if action.destructive { confirming = action }
                    else { Task { await model.engine.run(action) } }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .card()
    }
}
