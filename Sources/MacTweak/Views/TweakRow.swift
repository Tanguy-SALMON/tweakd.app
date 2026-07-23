//
//  TweakRow.swift
//  MacTweak
//

import SwiftUI

struct TweakRow: View {
    @EnvironmentObject var model: AppModel
    let tweak: Tweak
    @State private var showRiskAlert = false

    private var state: TweakState { model.engine.state(of: tweak) }
    private var busy: Bool { model.engine.busy.contains(tweak.key) }
    private var isFavorite: Bool { model.engine.favorites.contains(tweak.key) }
    private var isOn: Bool { state == .applied }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            GlyphTile(systemName: tweak.icon, size: 38, active: isOn)

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    Text(tweak.title).font(.system(size: 15, weight: .semibold))
                    if tweak.privilege == .admin {
                        Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Text(tweak.summary)
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.xxs) {
                    stateBadge
                    Pill(text: tweak.risk.label)
                    if tweak.sipRequired {
                        Pill(text: "Needs SIP off", systemImage: "exclamationmark.shield")
                    }
                    ForEach(tweak.gains, id: \.self) { GainChip(gain: $0) }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: Space.xs)

            VStack(alignment: .trailing, spacing: Space.s) {
                Button {
                    model.engine.toggleFavorite(tweak)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(isFavorite ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)

                toggle
            }
        }
        .card()
        .opacity(state == .unavailable ? 0.55 : 1)
        .alert("Enable “\(tweak.title)”?", isPresented: $showRiskAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Enable Anyway", role: .destructive) {
                Task { await model.engine.set(tweak, to: .applied) }
            }
        } message: {
            Text("This is an advanced tweak. It can affect stability, battery, or need a reboot to fully revert. Continue only if you understand the risk.")
        }
    }

    @ViewBuilder private var stateBadge: some View {
        switch state {
        case .applied:      Pill(text: "Applied", prominent: true, systemImage: "checkmark")
        case .notApplied:   Pill(text: "Stock")
        case .unavailable:  Pill(text: "Unavailable")
        case .unknown:      Pill(text: "—")
        }
    }

    @ViewBuilder private var toggle: some View {
        if busy {
            ProgressView().controlSize(.small).frame(width: 38, height: 22)
        } else if state == .unavailable {
            Button {
                model.engine.lastMessage = "\(tweak.title) needs SIP disabled. Reboot into Recovery, open Terminal, run “csrutil disable”, then reboot."
            } label: {
                Image(systemName: "nosign").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Requires System Integrity Protection to be disabled — click for how.")
        } else {
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { want in
                    if want && tweak.risk == .advanced {
                        showRiskAlert = true            // confirm before enabling advanced tweaks
                    } else {
                        Task { await model.engine.set(tweak, to: want ? .applied : .notApplied) }
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }
}

/// A small chip showing what a tweak improves — the app-native twin of the
/// website's gain indicator: a benefit glyph, its label, and an up-arrow that
/// reads as "this gets better". Kept static (no looping animation) so a list of
/// 30 rows stays at the near-zero idle cost the metrics work bought back.
struct GainChip: View {
    let gain: Gain
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: gain.symbol).foregroundStyle(Theme.accent)
            Text(gain.label).foregroundStyle(.secondary)
            Image(systemName: "arrow.up")
                .font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.accent)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, Space.xs).padding(.vertical, 3)
        .background(Theme.accent.opacity(0.10), in: Capsule())
    }
}
