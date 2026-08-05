//
//  Gauges.swift
//  tweakd
//
//  Dashboard primitives: per-metric trend meters, stat tiles and sparklines.
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

/// The accent area+line marks for the CPU history. Only the menu-bar panel uses
/// these now — the dashboard draws its own lines with `Sparkline`. The area wash
/// stays on here because that plot is a lone series in a tiny space, where the
/// fill gives it some body.
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

/// One live metric: label, current value, its own trend line, and a detail line.
///
/// This replaced the ring gauges, then absorbed the combined chart that briefly
/// sat beside it. A ring was a two-slice donut around a single number, and the
/// three-series chart plotted the same values a second time — stacked on one
/// 0...100 axis they overlapped into a tangle no legend could untie. A line per
/// metric, in that metric's colour, says the same thing without either problem,
/// and a fourth metric costs one row.
struct MetricMeter: View {
    let value: Double        // 0...100
    let label: String
    let detail: String
    /// Identity colour, carried by the trend line and the dot beside the label.
    let tint: Color
    /// Recent history for this metric, newest last. Fixed to a 0...100 scale, not
    /// self-scaled: these are percentages with a real ceiling, and self-scaling
    /// would draw a quiet 4% CPU as a full-height mountain.
    var trend: [Double] = []
    var action: Action? = nil

    /// Optional button rendered under the meter (the Clear on the memory row).
    struct Action {
        let title: String
        let systemImage: String
        var busy: Bool = false
        let run: () -> Void
    }

    // Guard NaN before it reaches the sparkline scale: min/max propagate NaN
    // rather than reject it, and Core Animation blanks the layer on a non-finite.
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

            // No meter bar: the sparkline states the same ratio against the same
            // fixed 0...100 ceiling, and says how it got there as well. Two marks
            // for one number was redundant once the trend was there.
            if trend.count > 1 {
                Sparkline(values: trend, tint: tint, fixedPeak: 100)
                    .frame(height: 34)   // Fibonacci
            }

            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1).minimumScaleFactor(0.85)

            if let action { actionButton(action) }
        }
        // One spoken element: "CPU, 8 cores: 27 percent".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(detail)")
        .accessibilityValue("\(Int(clamped.rounded())) percent")
    }

    @ViewBuilder private func actionButton(_ a: Action) -> some View {
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
    /// Optional trend, newest last. Throughput is a rate with no ceiling, so it
    /// gets a sparkline rather than a meter — there is no "100%" to fill against,
    /// and a bar would have to invent one.
    var trend: [Double] = []
    var trendTint: Color = Theme.accent

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
            Spacer(minLength: Space.s)
            if trend.count > 1 { Sparkline(values: trend, tint: trendTint).frame(width: 89, height: 28) }
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

/// A bare trend line — no axes, no labels, sized by its container.
///
/// Scaled to its own maximum rather than a shared one: throughput has no fixed
/// ceiling, and a common scale would flatten a 40 KB/s upload to a dead line
/// whenever a download spikes to 20 MB/s. The tile's value text carries the
/// magnitude; the line only has to carry the shape.
struct Sparkline: View {
    let values: [Double]
    let tint: Color
    /// Width of the time window in samples, matching the history buffer. The x
    /// axis is this window — NOT `values.count` — so the newest sample always
    /// sits at the right edge and older ones march left, exactly like the 90s
    /// chart's fixed date domain. Scaling to `values.count` instead pinned the
    /// series to a fixed left origin and stretched it as history filled, so it
    /// never appeared to flow.
    var capacity: Int = 90
    /// Pin the top of the scale instead of using the series' own maximum. Needed
    /// for anything with a real ceiling: a 0...100 percentage self-scaled would
    /// redraw a quiet 4% CPU as a full-height mountain, and thermal pressure
    /// self-scaled would show "fair" as if it were "critical".
    var fixedPeak: Double? = nil
    /// Draw as a staircase. Right for a state that steps between discrete levels
    /// — interpolating thermal pressure would imply values between them.
    var stepped: Bool = false

    var body: some View {
        GeometryReader { geo in
            // never divide by zero on an idle link
            let peak = fixedPeak ?? max(values.max() ?? 0, 1)
            let slots = max(capacity - 1, 1)
            let stepX = geo.size.width / CGFloat(slots)
            // Inset by half the stroke so a flat idle line at zero stays visible
            // instead of being clipped in half by the bottom edge.
            let inset = 0.75
            let plotHeight = max(geo.size.height - inset * 2, 1)
            let newestIndex = values.count - 1
            let points = values.enumerated().map { i, v in
                CGPoint(x: geo.size.width - CGFloat(newestIndex - i) * stepX,
                        y: inset + plotHeight * (1 - CGFloat(min(max(v / peak, 0), 1))))
            }
            ZStack {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: inset + plotHeight))
                    p.addLine(to: first)
                    Self.trace(&p, points, stepped: stepped)
                    p.addLine(to: CGPoint(x: points[points.count - 1].x, y: inset + plotHeight))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    Self.trace(&p, points, stepped: stepped)
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)   // the tile's value already states the figure
    }

    /// Walk the remaining points, either straight between them or as a staircase
    /// that holds each level until the next sample changes it.
    private static func trace(_ p: inout Path, _ points: [CGPoint], stepped: Bool) {
        for point in points.dropFirst() {
            if stepped { p.addLine(to: CGPoint(x: point.x, y: p.currentPoint?.y ?? point.y)) }
            p.addLine(to: point)
        }
    }
}
