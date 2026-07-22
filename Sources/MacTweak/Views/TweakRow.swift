//
//  TweakRow.swift
//  MacTweak
//

import SwiftUI

struct TweakRow: View {
    @EnvironmentObject var model: AppModel
    let tweak: Tweak

    private var state: TweakState { model.engine.state(of: tweak) }
    private var busy: Bool { model.engine.busy.contains(tweak.key) }
    private var isFavorite: Bool { model.engine.favorites.contains(tweak.key) }
    private var isOn: Bool { state == .applied }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(tweak.title).font(.headline)
                    if tweak.privilege == .admin {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                    }
                }
                Text(tweak.summary)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Pill(text: tweak.risk.label, color: tweak.risk.tint)
                    stateBadge
                    if tweak.sipRequired {
                        Pill(text: "Needs SIP off", color: .red, systemImage: "exclamationmark.shield")
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    model.engine.toggleFavorite(tweak)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                toggle
            }
        }
        .card()
        .opacity(state == .unavailable ? 0.55 : 1)
    }

    private var icon: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tweak.category.tint.opacity(0.16))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: tweak.category.icon)
                .foregroundStyle(tweak.category.tint))
    }

    @ViewBuilder private var stateBadge: some View {
        switch state {
        case .applied:      Pill(text: "Applied", color: .green, filled: true, systemImage: "checkmark")
        case .notApplied:   Pill(text: "Stock", color: .secondary)
        case .unavailable:  Pill(text: "Unavailable", color: .red)
        case .unknown:      Pill(text: "—", color: .secondary)
        }
    }

    @ViewBuilder private var toggle: some View {
        if busy {
            ProgressView().controlSize(.small).frame(width: 40, height: 22)
        } else if state == .unavailable {
            Image(systemName: "nosign").foregroundStyle(.secondary)
        } else {
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { _ in Task { await model.engine.toggle(tweak) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(tweak.category.tint)
        }
    }
}
