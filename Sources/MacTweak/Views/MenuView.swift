//
//  MenuView.swift
//  MacTweak
//
//  The menu-bar dropdown: live stats, favorites quick-toggles, and shortcuts.
//

import SwiftUI
import Charts

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header

            MenuMetrics(metrics: model.metrics, tweaksApplied: model.engine.appliedCount)

            Divider().overlay(Theme.hairline)

            if model.engine.favoriteTweaks.isEmpty {
                Text("Pin tweaks with the star to control them here.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: Space.xs) {
                    ForEach(model.engine.favoriteTweaks.prefix(6)) { tweak in
                        favoriteRow(tweak)
                    }
                }
            }

            Divider().overlay(Theme.hairline)

            menuButton("Open MacTweak", "macwindow") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }

            Button {
                Task { await model.engine.applyRecommended() }
            } label: {
                HStack {
                    Label("Apply Recommended", systemImage: "wand.and.sparkles")
                    Spacer()
                    if model.engine.batchRunning { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .disabled(model.engine.batchRunning)

            Divider().overlay(Theme.hairline)

            menuButton("Quick Security", "lock.shield") {
                Task { await model.engine.applyPreset(id: "hardened") }
            }
            menuButton("Low-Latency Network", "bolt.horizontal") {
                Task { await model.engine.applyPreset(id: "lowlatency") }
            }
            menuButton("Reset Priorities", "arrow.uturn.backward") {
                Task { await model.priority.resetAll() }
            }

            menuButton("Quit", "power") { NSApp.terminate(nil) }

            if let msg = model.engine.lastMessage {
                Divider().overlay(Theme.hairline)
                HStack(alignment: .top, spacing: Space.xs) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.accent)
                    Text(msg).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
                .task(id: msg) {
                    try? await Task.sleep(for: .seconds(5))
                    model.engine.lastMessage = nil
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.engine.lastMessage)
        .padding(Space.s)
        .frame(width: 288)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.accent).frame(width: 22, height: 22)
                .overlay(Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
            Text("MacTweak").font(.system(size: 14, weight: .semibold))
            Spacer()
        }
    }

    private func favoriteRow(_ tweak: Tweak) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: tweak.icon).foregroundStyle(.secondary).frame(width: 18)
            Text(tweak.title).font(.system(size: 13)).lineLimit(1)
            Spacer()
            if model.engine.busy.contains(tweak.key) {
                ProgressView().controlSize(.small)
            } else if model.engine.state(of: tweak) == .unavailable {
                Image(systemName: "nosign")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .help("Unavailable — needs SIP disabled. Open MacTweak for details.")
            } else {
                Toggle("", isOn: Binding(
                    get: { model.engine.state(of: tweak) == .applied },
                    set: { want in Task { await model.engine.set(tweak, to: want ? .applied : .notApplied) } }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
        }
    }

    private func menuButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
    }
}

/// Live CPU/MEM tiles + sparkline. Observes SystemMetrics directly so it ticks
/// every second even while the menu is open.
private struct MenuMetrics: View {
    @ObservedObject var metrics: SystemMetrics
    let tweaksApplied: Int

    var body: some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                tile("cpu", "CPU", "\(Int(metrics.cpuPercent))%")
                tile("memorychip", "MEM", "\(Int(metrics.memUsedPercent))%")
                tile("checkmark.seal", "TWEAKS", "\(tweaksApplied)", accent: true)
            }
            cpuChart
        }
        // Sample only while the popover is actually open; no per-second implicit
        // animation (it would re-composite the chart continuously).
        .onAppear { metrics.retain() }
        .onDisappear { metrics.release() }
    }

    private var xDomain: ClosedRange<Date> {
        let end = metrics.history.last?.time ?? Date()
        return end.addingTimeInterval(-90)...end
    }

    private var cpuChart: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("CPU LOAD").font(.system(size: 9, weight: .semibold))
                    .tracking(0.5).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(metrics.cpuPercent))% used")
                    .font(.system(size: 11, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
            }
            Chart {
                RuleMark(y: .value("mid", 50))
                    .foregroundStyle(Theme.hairline)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                cpuHistoryMarks(metrics.history)
                if let last = metrics.history.last {
                    PointMark(x: .value("t", last.time), y: .value("cpu", last.cpu))
                        .foregroundStyle(Theme.accent).symbolSize(24)
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
                    AxisValueLabel {
                        if let n = v.as(Int.self) {
                            Text("\(n)").font(.system(size: 7)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 42)
        }
    }

    private func tile(_ icon: String, _ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(accent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xs)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.tile))
    }
}
