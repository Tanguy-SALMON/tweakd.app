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
    /// Thermal-pressure history, 0...3. Sampled on the metrics tick, which is a
    /// free ProcessInfo read — unlike the per-cluster MHz below it, which needs
    /// `powermetrics` as root and so stays on-demand.
    var pressureTrend: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            verdictRow
            pressureScale

            if pressureTrend.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    Sparkline(values: pressureTrend, tint: Theme.accent,
                              fixedPeak: 3, stepped: true,
                              gridLevels: [(1.0, "critical"), (2.0 / 3.0, "serious")])
                        // 34, not 21: two 8pt labels 1/3 of the box apart need
                        // the room, and at 21 they overlapped into a smudge.
                        .frame(height: 34)   // Fibonacci
                    Text("Thermal pressure · last 90s — the floor is nominal, the dashed rules are the two throttling levels. Flat along the bottom means nothing was ever limited.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    temperatureNote
                }
            }

            if !monitor.clusters.isEmpty {
                Divider().overlay(Theme.hairline)
                ForEach(monitor.clusters) { clusterRow($0) }
                liveRow
                footnote
            } else if let err = monitor.sampleError {
                Text(err).font(.system(size: 12)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let blocked = monitor.liveBlocked {
                Text(blocked).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if ThermalMonitor.isPassivelyCooled {
                fanlessNote
            }
        }
        .card()
        .animation(.easeOut(duration: 0.2), value: monitor.clusters.count)
        .animation(.easeOut(duration: 0.2), value: monitor.thermalLabel)
        .task { monitor.refreshThermalState() }
        // powermetrics runs as root for as long as live mode is on — leaving the
        // pane must stop it, not just hide it.
        .onDisappear { monitor.stopLive() }
    }

    // MARK: - Pressure scale

    /// The four levels laid out as a scale with the current one lit.
    ///
    /// "Nominal" by itself is a verdict with nothing to measure it against — you
    /// can't tell whether it's the good end or the bad end, or what the two
    /// dashed rules on the strip below are called. Showing the whole ladder makes
    /// the current rung mean something.
    private var pressureScale: some View {
        let current = monitor.levelIndex
        return VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: 3) {
                ForEach(Array(ThermalMonitor.levels.enumerated()), id: \.offset) { i, level in
                    let active = i == current
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(active ? AnyShapeStyle(rungTint(i))
                                         : AnyShapeStyle(Color.secondary.opacity(0.15)))
                            .frame(height: 6)
                        Text(level.name)
                            .font(.system(size: 10, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? .primary : .secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .help(level.meaning)
                }
            }
            Text(ThermalMonitor.levels[min(current, 3)].meaning)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thermal pressure")
        .accessibilityValue("\(ThermalMonitor.levels[min(current, 3)].name). \(ThermalMonitor.levels[min(current, 3)].meaning)")
    }

    /// Green only at nominal — the point of the scale is that one end is good.
    private func rungTint(_ index: Int) -> Color {
        switch index {
        case 0:  return .green
        case 1:  return .yellow
        case 2:  return .orange
        default: return .red
        }
    }

    /// Asked often enough to answer in the UI: there is no temperature to show.
    private var temperatureNote: some View {
        Text("No degrees here: Apple Silicon doesn't publish a die temperature to apps, so macOS's own pressure level is the honest signal — and it's the one the system actually acts on when it decides to slow down.")
            .font(.system(size: 10)).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    // MARK: - Live sampling

    private var liveRow: some View {
        HStack(spacing: Space.xs) {
            if monitor.live {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Live · refreshing every second")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let at = monitor.sampledAt {
                Text("Sampled \(at.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.xs)
            Button {
                monitor.toggleLive()
            } label: {
                Label(monitor.live ? "Stop live" : "Go live",
                      systemImage: monitor.live ? "stop.circle" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.gradientOutline)
            .controlSize(.small)
            .disabled(monitor.sampling)
            .help(monitor.live
                  ? "Stop the continuous powermetrics sampler"
                  : "Keep powermetrics running so the cluster speeds refresh every second (needs Admin Access unlocked)")
        }
        .textSelection(.enabled)
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
            .textSelection(.enabled)

            Spacer(minLength: Space.xs)

            if monitor.sampling {
                ProgressView().controlSize(.small)
            } else if monitor.live {
                // The live stream already re-reads every second; a one-shot
                // sample alongside it would just fight it for the same numbers.
                EmptyView()
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
            .textSelection(.enabled)
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
        // Live mode redraws these every second; without a transition the bar and
        // the digits snap, which reads as flicker rather than as movement.
        .animation(.easeOut(duration: 0.3), value: c.currentMHz)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.friendlyName)
        .accessibilityValue("\(c.currentMHz) of \(c.maxMHz) megahertz")
    }

    /// The single most important caveat: idle ≠ throttled.
    private var footnote: some View {
        Text(monitor.live
             ? "Cores sit well below maximum whenever the Mac is idle — that's normal, not throttling. Only the pressure level above tells you whether the ceiling has actually been lowered."
             : "This is a one-off sample. Cores sit well below maximum whenever the Mac is idle — that's normal, not throttling. Only the pressure level above tells you whether the ceiling has actually been lowered.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var fanlessNote: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            Image(systemName: "wind")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("This Mac is fanless, so it sheds heat by slowing down. Expect throttling under long sustained loads (big builds, exports) — brief bursts stay at full speed.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
