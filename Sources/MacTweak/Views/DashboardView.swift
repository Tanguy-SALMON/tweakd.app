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
            VStack(alignment: .leading, spacing: 20) {
                hero

                HStack(spacing: 14) {
                    RingGauge(value: model.metrics.cpuPercent, label: "CPU",
                              detail: "\(SystemInfo.coreCount) cores", tint: .blue)
                    RingGauge(value: model.metrics.memUsedPercent, label: "Memory",
                              detail: "\(formatBytes(model.metrics.memUsedBytes)) of \(formatBytes(model.metrics.memTotalBytes))",
                              tint: .purple)
                    liveChart
                }
                .frame(height: 210)

                HStack(spacing: 14) {
                    StatTile(title: "Tweaks Applied", value: "\(model.engine.appliedCount)",
                             systemImage: "checkmark.seal.fill", tint: .green)
                    StatTile(title: "macOS", value: SystemInfo.osShortVersion,
                             systemImage: "apple.logo", tint: .primary)
                    StatTile(title: "SIP", value: SystemInfo.sipEnabled ? "Enabled" : "Disabled",
                             systemImage: SystemInfo.sipEnabled ? "lock.fill" : "lock.open.fill",
                             tint: SystemInfo.sipEnabled ? .orange : .green)
                }

                quickTune
            }
            .padding(24)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome back")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("\(SystemInfo.chip) · \(formatBytes(SystemInfo.physicalMemory)) RAM")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var liveChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live · last 90s").font(.caption).foregroundStyle(.secondary)
            Chart(model.metrics.history) { p in
                AreaMark(x: .value("t", p.id), y: .value("CPU", p.cpu))
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.4), .blue.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.id), y: .value("CPU", p.cpu))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { AxisGridLine(); AxisValueLabel() }
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var quickTune: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One-click tune").sectionTitle()
            Text("Apply the recommended safe set, or revert everything to stock.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    Task { await model.engine.applyRecommended() }
                } label: {
                    Label("Apply Recommended", systemImage: "wand.and.sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    Task { await model.engine.revertAll() }
                } label: {
                    Label("Revert All", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }
}
