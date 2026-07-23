//
//  Gauges.swift
//  MacTweak
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
            Spacer()
        }
    }
}

/// The accent area+line marks for the CPU history — shared by the dashboard
/// chart and the menu sparkline (each wraps it with its own axes/chrome).
@ChartContentBuilder
func cpuHistoryMarks(_ history: [MetricPoint]) -> some ChartContent {
    ForEach(history) { p in
        AreaMark(x: .value("t", p.id), y: .value("CPU", p.cpu))
            .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.02)],
                                            startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("t", p.id), y: .value("CPU", p.cpu))
            .foregroundStyle(Theme.accent)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
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

            VStack(spacing: 2) {
                Text(label).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let action { actionButton(action) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // equal height across the row
        .card()
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
            Spacer()
        }
        .card(padding: Space.s)
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .memory
    return f.string(fromByteCount: Int64(bytes))
}
