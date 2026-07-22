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
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.green.gradient)
                        .frame(width: 46, height: 46)
                        .overlay(Image(systemName: "bolt.badge.automatic")
                            .font(.title3.weight(.bold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick Actions").font(.system(.title, design: .rounded).weight(.bold))
                        Text("One-shot maintenance. Nothing here is permanent.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                ForEach(model.engine.actions) { action in
                    row(action)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
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

    private func row(_ action: SystemAction) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: action.icon).foregroundStyle(.green))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(action.title).font(.headline)
                    if action.privilege == .admin {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    if action.destructive {
                        Pill(text: "Rebuilds data", color: .red)
                    }
                }
                Text(action.summary).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if model.engine.busy.contains(action.key) {
                ProgressView().controlSize(.small)
            } else {
                Button("Run") {
                    if action.destructive { confirming = action }
                    else { Task { await model.engine.run(action) } }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .card()
    }
}
