//
//  Gauges.swift
//  tweakd
//
//  Monochrome dashboard primitives: a single-accent radial gauge and a stat tile.
//

import SwiftUI
import Charts

/// The section hero used at the top of list/benchmark/actions panes.
struct HeroHeader: View {
    let icon: String
    let title: String
    let blurb: String
    var body: some View {
        HStack(spacing: Space.s) {
            GlyphTile(systemName: icon, size: 42, prominent: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 26, weight: .bold))
                Text(blurb).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The accent area+line marks for the CPU history — shared by the dashboard
/// chart and the menu sparkline (each wraps it with its own axes/chrome).
@ChartContentBuilder
func cpuHistoryMarks(_ history: [MetricPoint]) -> some ChartContent {
    ForEach(history) { p in
        AreaMark(x: .value("t", p.time), y: .value("CPU", p.cpu))
            .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.02)],
                                            startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("t", p.time), y: .value("CPU", p.cpu))
            .foregroundStyle(Theme.accent)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
    }
}

/// GPU series for the same chart. A line only — no area fill, so it stays
/// legible where it crosses the CPU area rather than muddying it.
@ChartContentBuilder
func gpuHistoryMarks(_ history: [MetricPoint]) -> some ChartContent {
    ForEach(history) { p in
        LineMark(x: .value("t", p.time), y: .value("GPU", p.gpu))
            .foregroundStyle(Theme.gpuAccent)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
    }
}

/// One live metric as a labelled meter: value, a ratio bar, and a detail line.
///
/// Replaces the ring gauges. A ring is a two-slice donut around a single number —
/// the arc encodes nothing the number doesn't already say, while costing a square
/// tile each. Three of them crowded the 90s chart into a column too narrow to
/// render its own axis. A meter states the same ratio in a strip, so the metrics
/// stack in a fraction of the width and adding a fourth costs one row, not a column.
struct MetricMeter: View {
    let value: Double        // 0...100
    let label: String
    let detail: String
    /// Identity colour, shared with this metric's line on the chart. Carried by the
    /// meter fill and the legend dot so the two views agree at a glance.
    let tint: Color
    var action: RingGauge.Action? = nil

    // Guard NaN before it reaches a width multiplier, as RingGauge does for `.trim`.
    private var clamped: Double { value.isFinite ? min(max(value, 0), 100) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(label).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: Space.xs)
                // Proportional figures: this is a standalone value, not a column.
                Text("\(Int(clamped.rounded()))")
                    .font(.system(size: 22, weight: .semibold))
                    .contentTransition(.numericText())
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))          // track: lighter step of the same hue
                    Capsule().fill(tint)
                        .frame(width: max(0, geo.size.width * clamped / 100))
                }
            }
            .frame(height: 6)

            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1).minimumScaleFactor(0.85)

            if let action { RingGauge.actionButton(action) }
        }
        // One spoken element: "CPU, 8 cores: 27 percent".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(detail)")
        .accessibilityValue("\(Int(clamped.rounded())) percent")
    }
}

struct RingGauge: View {
    let value: Double        // 0...100
    let label: String
    let detail: String
    var action: Action? = nil

    /// Optional button rendered under the gauge (e.g. "Clear" on the RAM ring).
    struct Action {
        let title: String
        let systemImage: String
        var busy: Bool = false
        let run: () -> Void
    }

    // Guard NaN before it reaches `.trim` — Core Animation logs and blanks the
    // arc on a non-finite value (min/max propagate NaN rather than reject it).
    private var clamped: Double { value.isFinite ? min(max(value, 0), 100) : 0 }

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: clamped / 100)
                    .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // Value already EMA-smoothed and updates once/sec; animating a
                    // gradient arc every tick was continuous compositing for nothing.
                VStack(spacing: 0) {
                    Text("\(Int(clamped.rounded()))")
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 89, height: 89)   // Fibonacci
            // One spoken element: "CPU, 8 cores: 27 percent".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label), \(detail)")
            .accessibilityValue("\(Int(clamped.rounded())) percent")

            VStack(spacing: 2) {
                Text(label).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .textSelection(.enabled)
            .accessibilityHidden(true)   // already conveyed by the gauge element above

            if let action { Self.actionButton(action) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // equal height across the row
        .card()
    }

    @ViewBuilder static func actionButton(_ a: Action) -> some View {
        Button(action: a.run) {
            Group {
                if a.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Label(a.title, systemImage: a.systemImage).font(.system(size: 12, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.gradient)
        .controlSize(.small)
        .disabled(a.busy)
        .padding(.top, Space.xxs)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var accent: Bool = false

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(accent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 17, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .textSelection(.enabled)
            Spacer()
        }
        .card(padding: Space.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .memory
    return f.string(fromByteCount: Int64(bytes))
}
