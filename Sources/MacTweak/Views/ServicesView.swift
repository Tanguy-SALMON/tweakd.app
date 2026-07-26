//
//  ServicesView.swift
//  MacTweak
//
//  The "Services" pane: every non-Apple launchd job on the Mac, grouped by what
//  it is, with what it's costing right now and a switch to stop or disable it.
//  Built for the "I don't use MySQL or PHP on this machine any more" case.
//

import SwiftUI

struct ServicesView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirming: LaunchService?
    @State private var confirmingGroup: ServiceKind?

    private var services: ServicesManager { model.services }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                header
                if services.scanned && services.services.isEmpty {
                    Text("No third-party background services found.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).card()
                }
                if !services.duplicatedLabels.isEmpty { duplicateWarning }
                ForEach(services.grouped(), id: \.kind) { group in
                    section(group.kind, group.items)
                }
                if let msg = services.lastMessage { messageCard(msg) }
                footnote
            }
            .padding(Space.l)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { if !services.scanned { await services.scan() } }
        .confirmationDialog(confirmTitle, isPresented: confirmBinding) {
            if let s = confirming {
                Button("Disable", role: .destructive) { Task { await services.setEnabled(s, false) } }
                Button("Cancel", role: .cancel) {}
            } else if let kind = confirmingGroup {
                Button("Disable all", role: .destructive) { Task { await services.disableAll(kind: kind) } }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: - Confirmation plumbing

    private var confirmBinding: Binding<Bool> {
        Binding(get: { confirming != nil || confirmingGroup != nil },
                set: { if !$0 { confirming = nil; confirmingGroup = nil } })
    }

    private var confirmTitle: String {
        if let s = confirming { return "Disable \(s.displayName)?" }
        if let k = confirmingGroup { return "Disable all \(k.title.lowercased())?" }
        return ""
    }

    private var confirmMessage: String {
        if let s = confirming {
            let scope = s.domain.needsAdmin ? " This is a system daemon, so it needs your admin password." : ""
            return "It will stop now and won't start at login. You can re-enable it here at any time.\(scope)"
        }
        if let k = confirmingGroup {
            let n = services.services.filter { $0.kind == k && !$0.disabled }.count
            return "\(n) service\(n == 1 ? "" : "s") will stop now and won't start at login. Each stays listed here so you can turn it back on."
        }
        return ""
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.s) {
                HeroHeader(icon: "square.stack.3d.up.fill", title: "Services",
                           blurb: "Background jobs launchd starts for you — what's running, what it costs, and how to stop it.")
                Spacer(minLength: Space.xs)
                Button {
                    Task { await services.scan() }
                } label: {
                    Label(services.scanning ? "Scanning…" : "Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.gradientOutline)
                .disabled(services.scanning)
                .clickCursor()
            }
            HStack(spacing: Space.xs) {
                Pill(text: "\(services.runningCount) running", prominent: true, systemImage: "play.fill")
                Pill(text: "\(services.services.count) total", systemImage: "square.stack.3d.up")
            }
        }
    }

    private var duplicateWarning: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.accent).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text("Installed twice").font(.system(size: 13, weight: .semibold))
                Text("\(services.duplicatedLabels.sorted().joined(separator: ", ")) exist as both a user agent and a system daemon. Disabling only one leaves the other running — turn off both to actually stop the service.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    // MARK: - Sections

    private func section(_ kind: ServiceKind, _ items: [LaunchService]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .top, spacing: Space.xs) {
                Image(systemName: kind.icon)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title).font(.system(size: 14, weight: .semibold))
                    Text(kind.blurb).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.xs)
                if kind.controllable && items.contains(where: { !$0.disabled }) {
                    Button("Disable all") { confirmingGroup = kind }
                        .buttonStyle(.link).font(.system(size: 11))
                        .clickCursor()
                        .accessibilityHint("Disables every service in \(kind.title)")
                }
            }
            .padding(.top, Space.xs)

            ForEach(items) { row($0) }
        }
    }

    private func row(_ s: LaunchService) -> some View {
        HStack(spacing: Space.s) {
            GlyphTile(systemName: s.kind.icon, size: 34, prominent: s.running)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xxs) {
                    Text(s.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if s.domain == .system {
                        Pill(text: "System", systemImage: "lock.fill")
                    }
                    if s.disabled { Pill(text: "Disabled") }
                }
                Text(s.statusText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                if s.running && (s.cpu > 0 || s.memoryMB > 0) {
                    Text(String(format: "%.1f%% CPU · %.0f MB", s.cpu, s.memoryMB))
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
            }

            Spacer(minLength: Space.xs)

            if services.busy.contains(s.id) {
                ProgressView().controlSize(.small)
            } else if !s.kind.controllable {
                Pill(text: "Protected", systemImage: "lock.shield")
            } else {
                controls(s)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(s.displayName), \(s.statusText)")
    }

    @ViewBuilder
    private func controls(_ s: LaunchService) -> some View {
        HStack(spacing: Space.xs) {
            if s.disabled {
                Button("Enable") { Task { await services.setEnabled(s, true) } }
                    .buttonStyle(.gradientOutline).clickCursor()
            } else {
                if s.running {
                    Button("Stop") { Task { await services.stop(s) } }
                        .buttonStyle(.gradientOutline).clickCursor()
                        .help("Stops it now. It starts again at the next login.")
                }
                Button("Disable") { confirming = s }
                    .buttonStyle(.gradient).clickCursor()
                    .help("Stops it now and prevents it starting at login.")
            }
        }
        .controlSize(.small)
    }

    // MARK: - Chrome

    private func messageCard(_ msg: String) -> some View {
        Text(msg).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Apple's own daemons aren't listed — they're SIP-protected and load-bearing. The few worth changing are in the Tweaks categories as reversible toggles.")
            Text("Everything here is reversible: **Stop** lasts until the next login, **Disable** persists until you re-enable it. Both are logged to the audit trail.")
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Space.xs)
    }
}
