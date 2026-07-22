//
//  Gauges.swift
//  MacTweak
//
//  Reusable radial gauge + stat tile for the dashboard.
//

import SwiftUI

struct RingGauge: View {
    let value: Double        // 0...100
    let label: String
    let detail: String
    var tint: Color = .blue

    private var clamped: Double { min(max(value, 0), 100) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: clamped / 100)
                    .stroke(
                        AngularGradient(colors: [tint.opacity(0.7), tint], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: clamped)
                VStack(spacing: 0) {
                    Text("\(Int(clamped.rounded()))")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("%").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 108, height: 108)

            Text(label).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(.title3, design: .rounded).weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .card(padding: 14)
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .memory
    return f.string(fromByteCount: Int64(bytes))
}
