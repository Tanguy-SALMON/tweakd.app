//
//  ThermalCard.swift
//  tweakd
//
//  "Am I getting full performance, or am I being throttled?" — the verdict up
//  top from macOS's own thermal-pressure level (free, live), with optional
//  per-cluster frequency vs. maximum underneath (needs admin, sampled on demand).
//

import SwiftUI

struct ThermalCard: View {
    @ObservedObject var monitor: ThermalMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            verdictRow

            if !monitor.clusters.isEmpty {
                Divider().overlay(Theme.hairline)
                ForEach(monitor.clusters) { clusterRow($0) }
                footnote
            } else if let err = monitor.sampleError {
                Text(err).font(.system(size: 12)).foregroundStyle(.secondary)
            }

            if ThermalMonitor.isPassivelyCooled {
                fanlessNote
            }
        }
        .card()
        .animation(.easeOut(duration: 0.2), value: monitor.clusters.count)
        .animation(.easeOut(duration: 0.2), value: monitor.thermalLabel)
        .task { monitor.refreshThermalState() }
    }

    // MARK: - Verdict

    private var verdictRow: some View {
        let v = monitor.verdict
        return HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: v.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(v.isAlarming ? AnyShapeStyle(.orange) : AnyShapeStyle(Theme.accentGradient))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(v.title).font(.system(size: 15, weight: .semibold))
                    Pill(text: monitor.thermalLabel.capitalized,
                         prominent: v.isAlarming)
                }
                Text(v.detail)
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.xs)

            if monitor.sampling {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await monitor.sampleFrequencies() }
                } label: {
                    Label(monitor.clusters.isEmpty ? "Check speed" : "Re-check",
                          systemImage: "speedometer")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.gradientOutline)
                .controlSize(.small)
                .help("Sample real CPU frequencies with powermetrics (needs admin)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Per-cluster speed

    private func clusterRow(_ c: ClusterSpeed) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Space.xs) {
                Text(c.friendlyName).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(c.currentMHz) / \(c.maxMHz) MHz")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let f = c.fractionOfMax {
                    Text("\(Int((f * 100).rounded()))%")
                        .font(.system(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            if let f = c.fractionOfMax {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(Theme.accentGradient)
                            .frame(width: max(2, geo.size.width * f))
                    }
                }
                .frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.friendlyName)
        .accessibilityValue("\(c.currentMHz) of \(c.maxMHz) megahertz")
    }

    /// The single most important caveat: idle ≠ throttled.
    private var footnote: some View {
        Text("This is a one-off sample. Cores sit well below maximum whenever the Mac is idle — that's normal, not throttling. Only the pressure level above tells you whether the ceiling has actually been lowered.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var fanlessNote: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            Image(systemName: "wind")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("This Mac is fanless, so it sheds heat by slowing down. Expect throttling under long sustained loads (big builds, exports) — brief bursts stay at full speed.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
