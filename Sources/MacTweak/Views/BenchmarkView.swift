//
//  BenchmarkView.swift
//  MacTweak
//

import SwiftUI
import Charts

struct BenchmarkView: View {
    @EnvironmentObject var model: AppModel
    private var bench: BenchmarkEngine { model.benchmark }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                header
                runner
                schedule
                if !bench.results.isEmpty {
                    overallChart
                    breakdown
                }
                if !bench.history.isEmpty {
                    timeline
                }
            }
            .padding(Space.l)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HeroHeader(icon: "chart.bar", title: "Benchmark",
                   blurb: "Measure CPU, memory and disk before and after your tweaks.")
            .padding(.bottom, Space.xxs)
    }

    private var runner: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Button {
                    let label = bench.nextLabel()
                    Task { await bench.run(label: label) }
                } label: {
                    Label(bench.isRunning ? "Running…" : "Run \(bench.nextLabel())",
                          systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gradient)
                .controlSize(.large)
                .disabled(bench.isRunning)

                Button {
                    bench.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.gradientOutline)
                .controlSize(.large)
                .disabled(bench.isRunning || bench.results.isEmpty)
            }

            if bench.isRunning {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ProgressView(value: bench.progress)
                    Text(bench.currentTask).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if bench.results.count < 2 {
                Text("Run a Baseline, apply some tweaks, then run After tweaks to see the delta.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .card(padding: Space.m)
    }

    // MARK: - Daily schedule

    private var schedule: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Benchmark").font(.system(size: 14, weight: .semibold))
                    Text("Runs once a day on its own and saves the score to the timeline below.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { bench.dailyEnabled },
                                         set: { bench.dailyEnabled = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if bench.dailyEnabled {
                Divider().overlay(Theme.hairline)
                HStack(spacing: Space.s) {
                    Text("Run at").font(.system(size: 13, weight: .medium))
                    Picker("", selection: Binding(get: { bench.dailyHour },
                                                  set: { bench.dailyHour = $0 })) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)
                    Spacer()
                    if let next = bench.nextDueDate {
                        Text("Next: \(next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                            .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if let note = bench.scheduleNote {
                    Label(note, systemImage: "clock.badge.exclamationmark")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text("A run pegs every core for a few seconds. It's postponed while the Mac is warm or busy, so a build or a call never lands in the numbers.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .card(padding: Space.m)
    }

    // MARK: - Timeline

    /// Newest last, capped — a chart with 400 points is a smear, not a trend.
    private var timelinePoints: [BenchmarkRecord] { Array(bench.history.suffix(60)) }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Timeline").sectionTitle()
                Spacer()
                Button("Clear history") { bench.clearHistory() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }

            Chart(timelinePoints) { r in
                LineMark(x: .value("Date", r.date), y: .value("Score", r.overall))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", r.date), y: .value("Score", r.overall))
                    .foregroundStyle(Theme.accent)
                    .symbol(r.trigger == .scheduled ? .circle : .diamond)
                    .symbolSize(r.trigger == .scheduled ? 26 : 44)
            }
            .chartYAxis {
                AxisMarks { AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel().font(.system(size: 9)) }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.system(size: 9))
                }
            }
            .frame(height: 160)

            Text("◆ manual · ● scheduled — run-to-run variance is normally a few percent, so read the trend rather than a single point.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            Divider().overlay(Theme.hairline)
            ForEach(recentRows, id: \.record.id) { row in
                historyRow(row)
                if row.record.id != recentRows.last?.record.id {
                    Divider().overlay(Theme.hairline)
                }
            }
        }
        .card()
    }

    /// Newest first, each paired with its change against the run before it.
    private var recentRows: [(record: BenchmarkRecord, deltaPct: Double?)] {
        let all = bench.history
        return all.indices.reversed().prefix(8).map { i in
            let prev = i > 0 ? all[i - 1].overall : nil
            let pct = (prev ?? 0) > 0 ? (all[i].overall - prev!) / prev! * 100 : nil
            return (all[i], pct)
        }
    }

    private func historyRow(_ row: (record: BenchmarkRecord, deltaPct: Double?)) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: row.record.trigger.icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.record.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.system(size: 13, weight: .medium))
                Text(row.record.trigger.label)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(row.record.overall))")
                .font(.system(size: 15, weight: .semibold)).monospacedDigit()
            if let pct = row.deltaPct {
                Pill(text: String(format: "%+.0f%%", pct), prominent: pct >= 0,
                     systemImage: pct >= 0 ? "arrow.up" : "arrow.down")
                    .frame(width: 74)
            } else {
                Color.clear.frame(width: 74, height: 1)
            }
        }
        .padding(.vertical, 2)
    }

    private var overallChart: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Overall Score").sectionTitle()
            Chart(bench.results) { r in
                BarMark(
                    x: .value("Run", r.label),
                    y: .value("Score", r.overall),
                    width: .fixed(55)
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(6)
                .annotation(position: .top) {
                    Text("\(Int(r.overall))").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks { AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel().font(.system(size: 9)) }
            }
            .frame(height: 178)
            if let gain = overallGain {
                Label(gain.text, systemImage: gain.up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(gain.up ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            }
        }
        .card()
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Breakdown").sectionTitle()
            grid("Single-core", \.singleCore)
            Divider().overlay(Theme.hairline)
            grid("Multi-core", \.multiCore)
            Divider().overlay(Theme.hairline)
            grid("Memory", \.memoryBandwidth)
            Divider().overlay(Theme.hairline)
            grid("Disk", \.disk)
        }
        .card()
    }

    private func grid(_ name: String, _ key: KeyPath<BenchmarkResult, Double>) -> some View {
        HStack {
            Text(name).font(.system(size: 13, weight: .medium)).frame(width: 110, alignment: .leading)
            Spacer()
            ForEach(bench.results) { r in
                VStack(spacing: 1) {
                    Text(String(format: "%.0f", r[keyPath: key]))
                        .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    Text(r.label).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(minWidth: 74)
            }
            if let d = metricDelta(key) {
                Pill(text: d.text, prominent: d.up, systemImage: d.up ? "arrow.up" : "arrow.down")
                    .frame(width: 74)
            }
        }
    }

    private var overallGain: (text: String, up: Bool)? {
        guard let a = bench.baseline, let b = bench.latest, a.id != b.id, a.overall > 0 else { return nil }
        let pct = (b.overall - a.overall) / a.overall * 100
        return (String(format: "%+.1f%% overall vs baseline", pct), pct >= 0)
    }

    private func metricDelta(_ key: KeyPath<BenchmarkResult, Double>) -> (text: String, up: Bool)? {
        guard let a = bench.baseline, let b = bench.latest, a.id != b.id else { return nil }
        let av = a[keyPath: key], bv = b[keyPath: key]
        guard av > 0 else { return nil }
        let pct = (bv - av) / av * 100
        return (String(format: "%+.0f%%", pct), pct >= 0)
    }
}
