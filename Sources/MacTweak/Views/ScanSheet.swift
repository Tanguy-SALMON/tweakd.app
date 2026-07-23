//
//  ScanSheet.swift
//  MacTweak
//
//  Modal shown by the sidebar "Re-scan" button. A live progress bar while every
//  tweak is re-probed, then a completion summary confirming the scan ran and
//  listing anything whose real state drifted since the last scan.
//

import SwiftUI

struct ScanSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: Space.m) {
            if let summary = model.engine.scanSummary {
                doneView(summary)
            } else {
                scanningView(model.engine.scanProgress)
            }
        }
        .padding(Space.l)
        .frame(width: 440)
        .tint(Theme.accent)
    }

    // MARK: - Scanning

    private func scanningView(_ progress: ScanProgress?) -> some View {
        let p = progress ?? ScanProgress(done: 0, total: model.engine.tweaks.count, current: "")
        return VStack(spacing: Space.m) {
            GlyphTile(systemName: "arrow.triangle.2.circlepath", size: 52, prominent: true)
                .rotationEffect(.degrees(spin))
                .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = 360 } }

            VStack(spacing: 4) {
                Text("Scanning system…").font(.system(size: 18, weight: .semibold))
                Text("Reading the live state of every tweak")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }

            ProgressView(value: p.fraction)
                .progressViewStyle(.linear)

            HStack {
                Text(p.current.isEmpty ? "Starting…" : "Checking \(p.current)…")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                Text("\(p.done) / \(p.total)")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    @State private var spin: Double = 0

    // MARK: - Done

    private func doneView(_ s: ScanSummary) -> some View {
        VStack(spacing: Space.m) {
            GlyphTile(systemName: "checkmark", size: 52, prominent: true)

            VStack(spacing: 4) {
                Text("Scan complete").font(.system(size: 18, weight: .semibold))
                Text("^[\(s.checked) tweak](inflect: true) checked against the live system")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }

            HStack(spacing: Space.xs) {
                statChip("\(s.applied)", "Applied", prominent: true)
                statChip("\(s.checked - s.applied - s.unavailable)", "Stock")
                statChip("\(s.unavailable)", "Unavailable")
            }

            if s.changes.isEmpty {
                Label("No changes since the last scan", systemImage: "equal.circle")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.xs)
            } else {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("^[\(s.changes.count) change](inflect: true) since last scan").sectionTitle()
                    ScrollView {
                        VStack(spacing: Space.xxs) {
                            ForEach(s.changes) { changeRow($0) }
                        }
                    }
                    .frame(maxHeight: 168)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                model.engine.scanSummary = nil
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func statChip(_ value: String, _ label: String, prominent: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: Space.s)
    }

    private func changeRow(_ c: ScanChange) -> some View {
        HStack(spacing: Space.xs) {
            Text(c.title).font(.system(size: 13, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: Space.xs)
            Text(stateLabel(c.from)).font(.system(size: 12)).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.secondary)
            Text(stateLabel(c.to)).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.to == .applied ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.control))
    }

    private func stateLabel(_ s: TweakState) -> String {
        switch s {
        case .applied: return "Applied"
        case .notApplied: return "Stock"
        case .unavailable: return "Unavailable"
        case .unknown: return "Unknown"
        }
    }
}
