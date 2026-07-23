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
                if !bench.results.isEmpty {
                    overallChart
                    breakdown
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
