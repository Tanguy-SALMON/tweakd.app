//
//  Gauges.swift
//  MacTweak
//
//  Monochrome dashboard primitives: a single-accent radial gauge and a stat tile.
//

import SwiftUI

struct RingGauge: View {
    let value: Double        // 0...100
    let label: String
    let detail: String

    private var clamped: Double { min(max(value, 0), 100) }

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: clamped / 100)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: clamped)
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
            }
        }
        .frame(maxWidth: .infinity)
        .card()
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
