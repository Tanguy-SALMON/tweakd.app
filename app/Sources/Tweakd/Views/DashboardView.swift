//
//  DashboardView.swift
//  tweakd
//

import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                hero

                LiveMetrics(metrics: model.metrics,
                            clearing: model.engine.busy.contains("purge-memory"),
                            onClearRAM: { Task { await model.engine.clearRAM() } })

                HStack(spacing: Space.m) {
                    StatTile(title: "Tweaks Applied", value: "\(model.engine.appliedCount)",
                             systemImage: "checkmark.seal", accent: model.engine.appliedCount > 0)
                    StatTile(title: "macOS", value: SystemInfo.osShortVersion, systemImage: "apple.logo")
                    StatTile(title: "SIP", value: SystemInfo.sipEnabled ? "Enabled" : "Disabled",
                             systemImage: SystemInfo.sipEnabled ? "lock" : "lock.open")
                }

                ThermalCard(monitor: model.thermal,
                            pressureTrend: model.metrics.history.map(\.thermal))
                adminCard
                AudioWatchdogCard(watchdog: model.audioWatchdog,
                                  adminUnlocked: model.engine.adminUnlocked)
                presetsCard
                quickTune
            }
            .padding(Space.l)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Overview")
                .font(.system(size: 34, weight: .bold))
            Text("\(SystemInfo.chip) · \(formatBytes(SystemInfo.physicalMemory)) RAM")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var adminCard: some View {
        let unlocked = model.engine.adminUnlocked
        return HStack(spacing: Space.s) {
            Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(unlocked ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Admin Access").font(.system(size: 15, weight: .semibold))
                Text(unlocked
                     ? "Unlocked — admin tweaks apply without asking for your password."
                     : "Locked — you'll be asked for your password once to enable passwordless tweaks.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textSelection(.enabled)
            Spacer(minLength: Space.s)
            if unlocked {
                Button("Lock") { Task { await model.engine.lockAdmin() } }
                    .buttonStyle(.gradientOutline).controlSize(.large)
            } else {
                Button("Unlock") { Task { await model.engine.unlockAdmin() } }
                    .buttonStyle(.gradient).controlSize(.large)
            }
        }
        .card()
    }

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Presets").sectionTitle()
                Text("Apply a curated bundle in one tap.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            HStack(spacing: Space.xs) {
                ForEach(Presets.all) { p in
                    Button {
                        Task { await model.engine.apply(preset: p) }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: p.icon).font(.system(size: 16, weight: .medium))
                            Text(p.name).font(.system(size: 11, weight: .medium))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s)
                        .background(Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Theme.hairline))
                    }
                    .buttonStyle(.plain)
                    .help(p.blurb)
                    .disabled(model.engine.batchRunning)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var quickTune: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("One-Click Tune").sectionTitle()
                Text("Apply the recommended safe set, or revert everything to stock.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            HStack(spacing: Space.s) {
                Button {
                    Task { await model.engine.applyRecommended() }
                } label: {
                    Text("Apply Recommended").frame(maxWidth: .infinity)
                }
                .buttonStyle(.gradient)
                .controlSize(.large)

                Button {
                    Task { await model.engine.revertAll() }
                } label: {
                    Text("Revert All").frame(maxWidth: .infinity)
                }
                .buttonStyle(.gradientOutline)
                .controlSize(.large)
            }
            .padding(.top, Space.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Space.m)
    }
}

/// Opt-in card for the Core Audio watchdog. Observes the watchdog directly so
/// its ~15s status updates don't churn the whole dashboard.
private struct AudioWatchdogCard: View {
    @ObservedObject var watchdog: CoreAudioWatchdog
    let adminUnlocked: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            GlyphTile(systemName: "waveform.badge.exclamationmark", size: 38,
                      prominent: watchdog.enabled)
            VStack(alignment: .leading, spacing: 2) {
                Text("Core Audio Watchdog").font(.system(size: 15, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textSelection(.enabled)
            Spacer(minLength: Space.s)
            Toggle("", isOn: $watchdog.enabled).labelsHidden()
        }
        .card()
    }

    private var statusLine: String {
        if !watchdog.enabled {
            return "Auto-restarts coreaudiod if a stuck audio stream pegs it above \(Int(watchdog.thresholdPercent))% — so you don't have to kill it by hand."
        }
        if let last = watchdog.lastAction { return last }
        if !adminUnlocked {
            return "Watching… unlock Admin Access above so it can restart silently, without a password prompt."
        }
        return "Watching coreaudiod (now \(Int(watchdog.lastCPU))%). Restarts it automatically if it stays hot."
    }
}

/// Observes `SystemMetrics` directly so the gauges + chart refresh every second
/// (a nested ObservableObject read through AppModel would never trigger this).
private struct LiveMetrics: View {
    @ObservedObject var metrics: SystemMetrics
    var clearing: Bool = false
    var onClearRAM: () -> Void = {}

    var body: some View {
        VStack(spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                // Meters in one card, chart in another. The three metrics read as a
                // set rather than three competing tiles, and the chart gets the width
                // it needs for its own axis instead of a quarter of the row.
                VStack(spacing: Space.m) {
                    MetricMeter(value: metrics.cpuPercent, label: "CPU",
                                detail: "\(SystemInfo.coreCount) cores", tint: Theme.accent,
                                trend: metrics.history.map(\.cpu))
                    MetricMeter(value: metrics.gpuPercent, label: "GPU",
                                detail: "\(formatBytes(metrics.gpuInUseBytes)) in use", tint: Theme.gpuAccent,
                                trend: metrics.history.map(\.gpu))
                    MetricMeter(value: metrics.memUsedPercent, label: "Memory",
                                detail: "\(formatBytes(metrics.memUsedBytes)) of \(formatBytes(metrics.memTotalBytes))",
                                tint: Theme.memAccent,
                                trend: metrics.history.map(\.mem),
                                action: .init(title: "Clear", systemImage: "wind",
                                              busy: clearing, run: onClearRAM))
                }
                .frame(width: 233)   // Fibonacci
                .card()

                chart
            }
            // No fixed row height: the meter card sizes to its own content, and
            // pinning it to 200 clipped the Clear button out over the tiles below.
            // The chart takes its height from the meters beside it instead.
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.m) {
                StatTile(title: "Download", value: formatRate(metrics.netDownKBps),
                         systemImage: "arrow.down.circle",
                         trend: metrics.history.map(\.netDown), trendTint: Theme.accent)
                StatTile(title: "Upload", value: formatRate(metrics.netUpKBps),
                         systemImage: "arrow.up.circle",
                         trend: metrics.history.map(\.netUp), trendTint: Theme.gpuAccent)
            }
            .animation(.easeOut(duration: 0.2), value: metrics.netDownKBps)
            .animation(.easeOut(duration: 0.2), value: metrics.netUpKBps)
        }
        .onAppear { metrics.retain() }
        .onDisappear { metrics.release() }
    }

    private func formatRate(_ kbps: Double) -> String {
        kbps >= 1024 ? String(format: "%.1f MB/s", kbps / 1024) : String(format: "%.0f KB/s", kbps)
    }

    /// A trailing 90-second window anchored on the newest sample, so the chart
    /// scrolls with real time instead of squashing every tick into the x-domain.
    private var xWindow: ClosedRange<Date> {
        let end = metrics.history.last?.time ?? Date()
        return end.addingTimeInterval(-90)...end
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text("last 90s").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
                    .textSelection(.enabled)
                Spacer()
                seriesKey("CPU", Theme.accent)
                seriesKey("GPU", Theme.gpuAccent)
                seriesKey("Memory", Theme.memAccent)
            }
            Chart {
                cpuHistoryMarks(metrics.history, filled: false)
                gpuHistoryMarks(metrics.history)
                memHistoryMarks(metrics.history)
            }
            .chartXScale(domain: xWindow)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            // Labels on the leading edge: on the trailing edge they sat outside
            // the plot and got clipped by the card, which is what cut "100" and
            // "0" in half against the right border.
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 144)   // Fibonacci — a floor, so the plot never collapses
            // Swift Charts doesn't clip marks to the plot area on its own — a
            // point that's briefly just outside the rolling 90s domain (normal
            // as the window advances every tick) would otherwise draw a line
            // straight across whatever sits beside this card.
            .chartPlotStyle { $0.clipped() }
            .clipped()
            // No implicit animation here: history.count changes every second,
            // so an animated relayout of the 90-point chart would run 30fps
            // continuously. The chart still redraws each tick — just not animated.
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    /// Legend dot + label. Two series share one chart, so the colour has to be
    /// named somewhere — the y-axis can't say which line is which.
    private func seriesKey(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
        .fixedSize()   // "CPU" must never wrap to "CP / U" when the row is tight
    }
}
