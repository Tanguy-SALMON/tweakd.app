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

                LiveMetrics(metrics: model.metrics)

                HStack(spacing: Space.m) {
                    StatTile(title: "Tweaks Applied", value: "\(model.engine.appliedCount)",
                             systemImage: "checkmark.seal", accent: model.engine.appliedCount > 0)
                    StatTile(title: "macOS", value: SystemInfo.osShortVersion, systemImage: "apple.logo")
                    StatTile(title: "SIP", value: SystemInfo.sipEnabled ? "Enabled" : "Disabled",
                             systemImage: SystemInfo.sipEnabled ? "lock" : "lock.open")
                }

                adminCard
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
                    .buttonStyle(.bordered).controlSize(.large)
            } else {
                Button("Unlock") { Task { await model.engine.unlockAdmin() } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
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
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task { await model.engine.revertAll() }
                } label: {
                    Text("Revert All").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, Space.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Space.m)
    }
}

/// Observes `SystemMetrics` directly so the gauges + chart refresh every second
/// (a nested ObservableObject read through AppModel would never trigger this).
private struct LiveMetrics: View {
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
        HStack(spacing: Space.m) {
            RingGauge(value: metrics.cpuPercent, label: "CPU",
                      detail: "\(SystemInfo.coreCount) cores")
            RingGauge(value: metrics.memUsedPercent, label: "Memory",
                      detail: "\(formatBytes(metrics.memUsedBytes)) of \(formatBytes(metrics.memTotalBytes))")
            chart
        }
        .frame(height: 178)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("CPU · last 90s").font(.system(size: 11)).foregroundStyle(.secondary)
            Chart(metrics.history) { p in
                AreaMark(x: .value("t", p.id), y: .value("CPU", p.cpu))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.01)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.id), y: .value("CPU", p.cpu))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .animation(.easeOut(duration: 0.5), value: metrics.history.count)
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}
