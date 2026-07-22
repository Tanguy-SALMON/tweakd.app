//
//  BenchmarkView.swift
//  MacTweak
//
//  Run a baseline, apply tweaks, run again — see the gain in a chart.
//

import SwiftUI
import Charts

struct BenchmarkView: View {
    @EnvironmentObject var model: AppModel
    private var bench: BenchmarkEngine { model.benchmark }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                runner
                if !bench.results.isEmpty {
                    overallChart
                    breakdown
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.gradient)
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: "chart.bar.xaxis").font(.title3.weight(.bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text("Benchmark").font(.system(.title, design: .rounded).weight(.bold))
                Text("Measure CPU, memory and disk before and after your tweaks.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var runner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    let label = bench.nextLabel()
                    Task { await bench.run(label: label) }
                } label: {
                    Label(bench.isRunning ? "Running…" : "Run \(bench.nextLabel())",
                          systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
                .disabled(bench.isRunning)

                Button {
                    bench.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(bench.isRunning || bench.results.isEmpty)
            }

            if bench.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: bench.progress)
                    Text(bench.currentTask).font(.caption).foregroundStyle(.secondary)
                }
            } else if bench.results.count < 2 {
                Text("Tip: run a **Baseline**, apply some tweaks, then run **After tweaks** to see the delta.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .card(padding: 18)
    }

    private var overallChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Overall score").sectionTitle()
            Chart(bench.results) { r in
                BarMark(
                    x: .value("Run", r.label),
                    y: .value("Score", r.overall)
                )
                .foregroundStyle(Theme.brand)
                .cornerRadius(6)
                .annotation(position: .top) {
                    Text("\(Int(r.overall))").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)
            if let gain = overallGain {
                Label(gain.text, systemImage: gain.up ? "arrow.up.right" : "arrow.down.right")
                    .font(.headline)
                    .foregroundStyle(gain.up ? .green : .red)
            }
        }
        .card()
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown").sectionTitle()
            grid("Single-core", \.singleCore, "Mops/s")
            Divider().opacity(0.4)
            grid("Multi-core", \.multiCore, "Mops/s")
            Divider().opacity(0.4)
            grid("Memory", \.memoryBandwidth, "MB/s")
            Divider().opacity(0.4)
            grid("Disk", \.disk, "MB/s")
        }
        .card()
    }

    private func grid(_ name: String, _ key: KeyPath<BenchmarkResult, Double>, _ unit: String) -> some View {
        HStack {
            Text(name).font(.subheadline.weight(.medium)).frame(width: 110, alignment: .leading)
            Spacer()
            ForEach(bench.results) { r in
                VStack(spacing: 1) {
                    Text(String(format: "%.0f", r[keyPath: key]))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                    Text(r.label).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(minWidth: 74)
            }
            if let d = metricDelta(key) {
                Pill(text: d.text, color: d.up ? .green : .red, filled: true,
                     systemImage: d.up ? "arrow.up" : "arrow.down")
                    .frame(width: 78)
            }
        }
    }

    // MARK: - Deltas

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
