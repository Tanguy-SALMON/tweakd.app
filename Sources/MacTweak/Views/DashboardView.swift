//
//  DashboardView.swift
//  MacTweak
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
            Text("Presets").sectionTitle()
            Text("Apply a curated bundle in one tap.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
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
            Text("One-Click Tune").sectionTitle()
            Text("Apply the recommended safe set, or revert everything to stock.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
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
        HStack(spacing: Space.m) {
            RingGauge(value: metrics.cpuPercent, label: "CPU",
                      detail: "\(SystemInfo.coreCount) cores")
            RingGauge(value: metrics.memUsedPercent, label: "Memory",
                      detail: "\(formatBytes(metrics.memUsedBytes)) of \(formatBytes(metrics.memTotalBytes))",
                      action: .init(title: "Clear", systemImage: "wind",
                                    busy: clearing, run: onClearRAM))
            chart
        }
        .frame(height: 200)
        .onAppear { metrics.retain() }
        .onDisappear { metrics.release() }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("CPU · last 90s").font(.system(size: 11)).foregroundStyle(.secondary)
            Chart { cpuHistoryMarks(metrics.history) }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            // No implicit animation here: history.count changes every second,
            // so an animated relayout of the 90-point chart would run 30fps
            // continuously. The chart still redraws each tick — just not animated.
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}
