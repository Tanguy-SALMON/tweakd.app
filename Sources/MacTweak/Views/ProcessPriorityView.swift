//
//  ProcessPriorityView.swift
//  MacTweak
//
//  The "Process Priority" pane: a live table of known network/UI processes with
//  a nice-value slider per row, an "Apply at login" toggle, and an emergency
//  "Reset all to default" button.
//

import SwiftUI

struct ProcessPriorityView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmingReset = false
    /// Per-target chosen nice value (seeded from the current live value or the
    /// target's suggestion on first appearance).
    @State private var niceChoice: [String: Double] = [:]

    private var priority: PriorityManager { model.priority }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                header
                warningCallout

                ForEach(PriorityManager.targets) { target in
                    targetCard(target)
                }

                resetRow
            }
            .padding(Space.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await priority.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s) {
            HeroHeader(icon: "cpu", title: "Process Priority",
                       blurb: "Give network and UI processes more CPU under load — or make background daemons yield.")
            Spacer(minLength: Space.xs)
            Button {
                Task { await priority.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.gradientOutline)
            .controlSize(.small)
            .disabled(priority.refreshing)
            .padding(.top, Space.xs)
        }
    }

    // MARK: - Warning callout

    private var warningCallout: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.accentGradient)
            VStack(alignment: .leading, spacing: 3) {
                Text("Priority changes reset on reboot")
                    .font(.system(size: 13, weight: .semibold))
                Text("Turn on \"Apply at login\" per process to keep it. Raising priority (negative values) needs admin and can make the system feel sluggish if overused.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: Space.s)
    }

    // MARK: - Per-target card

    private func targetCard(_ target: PriorityTarget) -> some View {
        let liveProcesses = priority.processes.filter { $0.targetID == target.id }
        let currentNice = liveProcesses.first?.nice
        let binding = niceBinding(for: target, current: currentNice)
        let value = Int(binding.wrappedValue.rounded())
        let busy = priority.busyTargets.contains(target.id)
        let applyingAtLogin = priority.isApplyingAtLogin(target)

        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                GlyphTile(systemName: target.icon, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.xs) {
                        Text(target.label).font(.system(size: 15, weight: .semibold))
                        Pill(text: pillText(count: liveProcesses.count, nice: currentNice))
                    }
                    Text(target.blurb).font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.xs)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button(target.boost ? "Boost" : "Yield") {
                        Task { await priority.applyTarget(target) }
                    }
                    .buttonStyle(.gradient)
                    .controlSize(.small)
                }
            }

            HStack(spacing: Space.s) {
                Slider(value: binding, in: Double(PriorityManager.niceRange.lowerBound)...Double(PriorityManager.niceRange.upperBound), step: 1)
                    .disabled(busy)
                    .tint(Theme.accent)
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(width: 32, alignment: .trailing)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: value)
            }

            if value < -5 {
                HStack(spacing: Space.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                    Text("Very high priority can make the system feel sluggish.")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.15), value: value)
            }

            Toggle(isOn: Binding(
                get: { applyingAtLogin },
                set: { newValue in
                    Task { await priority.setApplyAtLogin(target, nice: value, enabled: newValue) }
                }
            )) {
                Text("Apply at login").font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(busy)

            DisclosureGroup("Show command") {
                Text("renice -n \(value) -p $(pgrep -f \"\(target.pattern)\")")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .padding(Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
            .font(.system(size: 12))
        }
        .card()
        .animation(.easeOut(duration: 0.15), value: busy)
    }

    private func pillText(count: Int, nice: Int?) -> String {
        guard count > 0 else { return "Not running" }
        let runningPart = "\(count) running"
        guard let nice else { return runningPart }
        return "\(runningPart) · nice \(nice)"
    }

    private func niceBinding(for target: PriorityTarget, current: Int?) -> Binding<Double> {
        Binding(
            get: {
                if let existing = niceChoice[target.id] { return existing }
                let seed = Double(current ?? target.suggestedNice)
                return seed
            },
            set: { niceChoice[target.id] = $0 }
        )
    }

    // MARK: - Reset

    private var resetRow: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                confirmingReset = true
            } label: {
                Label("Emergency: Reset all to default", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.gradientOutline)
            Spacer()
        }
        .padding(.top, Space.xs)
        .confirmationDialog("Reset every process priority to default?",
                            isPresented: $confirmingReset) {
            Button("Reset All", role: .destructive) {
                Task { await priority.resetAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sets every known process back to nice 0 and removes all \"Apply at login\" LaunchAgents.")
        }
    }
}
