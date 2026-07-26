//
//  ServicesView.swift
//  MacTweak
//
//  The "Services" pane: every non-Apple launchd job on the Mac, grouped by what
//  it is, with what it's costing right now and a switch to stop or disable it.
//  Built for the "I don't use MySQL or PHP on this machine any more" case.
//
//  Laid out as one card per group with compact hairline-separated rows (the
//  Process Priority table pattern) rather than a card per service: at ~50
//  services, per-row cards are mostly chrome and impossible to scan.
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
                if services.scanning && !services.scanned { scanningCard }
                if services.scanned && services.services.isEmpty { emptyCard }
                if !services.duplicatedLabels.isEmpty { duplicateWarning }
                if let msg = services.lastMessage { messageCard(msg) }
                ForEach(services.groups) { group in
                    section(group)
                }
                footnote
            }
            .padding(Space.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { if !services.scanned { await services.scan() } }
        .animation(.easeOut(duration: 0.15), value: services.busy)
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
            let admin = s.domain.needsAdmin ? " This is a system daemon, so it needs your admin password." : ""
            let ports = s.ports.isEmpty ? "" : " Anything using port \(s.ports.map(String.init).joined(separator: ", ")) will stop working."
            return "It will stop now and won't start at login. You can re-enable it here at any time.\(ports)\(admin)"
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
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.gradientOutline)
                .controlSize(.small)
                .disabled(services.scanning)
                .padding(.top, Space.xs)
            }
            HStack(spacing: Space.xs) {
                Pill(text: "\(services.runningCount) running", prominent: true, systemImage: "bolt.fill")
                Pill(text: "\(services.services.count) total")
                if services.totalMemoryMB >= 1 {
                    Pill(text: String(format: "%.0f MB held", services.totalMemoryMB),
                         systemImage: "memorychip")
                }
            }
        }
    }

    // MARK: - Status cards

    private var scanningCard: some View {
        HStack(spacing: Space.s) {
            ProgressView().controlSize(.small)
            Text("Scanning launchd domains…")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.m)
        .card(padding: Space.s)
    }

    private var emptyCard: some View {
        HStack(spacing: Space.s) {
            GlyphTile(systemName: "checkmark", size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing running behind your back")
                    .font(.system(size: 14, weight: .semibold))
                Text("No third-party background services are installed on this Mac.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var duplicateWarning: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.accent).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text("Installed twice").font(.system(size: 13, weight: .semibold))
                Text("\(services.duplicatedLabels.joined(separator: ", ")) exist as both a user agent and a system daemon. Disabling only one leaves the other running — turn off both to actually stop the service.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func messageCard(_ msg: String) -> some View {
        Text(msg).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: Space.s)
    }

    // MARK: - Sections

    private func section(_ group: ServicesManager.ServiceGroup) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(group.kind.title).sectionTitle()
                Pill(text: group.runningCount > 0
                     ? "\(group.runningCount)/\(group.items.count) running"
                     : "\(group.items.count)")
                Spacer(minLength: Space.xs)
                if group.canDisableAny {
                    Button("Disable all") { confirmingGroup = group.kind }
                        .buttonStyle(.gradientOutline)
                        .controlSize(.small)
                        .accessibilityHint("Disables every service in \(group.kind.title)")
                }
            }
            .padding(.top, Space.s)
            .help(group.kind.blurb)

            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, s in
                    if index > 0 { Divider().opacity(0.5) }
                    row(s)
                }
            }
            .card(padding: Space.xs)
        }
    }

    private func row(_ s: LaunchService) -> some View {
        HStack(spacing: Space.s) {
            // Running is carried by a dot, not the glyph tile: GlyphTile's
            // `prominent` flag is deliberately a no-op in this design system.
            Circle()
                .fill(s.running ? AnyShapeStyle(Theme.accentGradient)
                                : AnyShapeStyle(Color.secondary.opacity(0.28)))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Space.xxs) {
                    Text(s.displayName)
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    // On a protected row the lock pill already says "system-ish";
                    // a second pill next to it is just noise.
                    if s.domain == .system && s.kind.controllable {
                        Pill(text: "System")
                    }
                    ForEach(s.ports, id: \.self) { port in
                        Pill(text: ":\(port)")
                    }
                }
                Text(subtitle(s))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: Space.xs)

            // Fixed-width monospaced stat column so the numbers line up down the
            // whole page — that alignment is most of what makes a table readable.
            if s.running {
                Text(String(format: "%.1f%% · %.0f MB", s.cpu, s.memoryMB))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(s.cpu >= 20 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 104, alignment: .trailing)
            }

            trailing(s)
                .frame(minWidth: 116, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, Space.xs)
        .opacity(s.disabled ? 0.55 : 1)
        .contentShape(Rectangle())
        // Children stay individually accessible on purpose — combining them into
        // one element would swallow the Stop/Disable buttons for VoiceOver.
        .accessibilityLabel("\(s.displayName), \(subtitle(s))")
    }

    /// Status line, folding in the worker count and last failure when they matter.
    private func subtitle(_ s: LaunchService) -> String {
        var parts = [s.statusText]
        if s.running && s.processCount > 1 { parts.append("\(s.processCount) processes") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func trailing(_ s: LaunchService) -> some View {
        if services.busy.contains(s.id) {
            ProgressView().controlSize(.small)
        } else if !s.kind.controllable {
            // Full opacity and a calm lock: this row is intentional, not broken.
            Pill(text: "Protected", systemImage: "lock.shield")
                .help("Security and management agents are read-only here — they're required by your organisation or by macOS.")
        } else if s.disabled {
            Button("Enable") { Task { await services.setEnabled(s, true) } }
                .buttonStyle(.gradientOutline).controlSize(.small)
                .help("Re-enables it and starts it now.")
        } else {
            HStack(spacing: Space.xxs) {
                if s.running {
                    Button("Stop") { Task { await services.stop(s) } }
                        .buttonStyle(.gradientOutline).controlSize(.small)
                        .help("Stops it now. It starts again at the next login.")
                }
                Button("Disable") { confirming = s }
                    .buttonStyle(.gradient).controlSize(.small)
                    .help("Stops it now and prevents it starting at login.")
            }
        }
    }

    // MARK: - Chrome

    private var footnote: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Apple's own daemons aren't listed — they're SIP-protected and load-bearing. The few worth changing are in the Tweaks categories as reversible toggles.")
            Text("**Stop** lasts until the next login; **Disable** persists until you re-enable it. CPU and memory are summed over each service's whole process tree. Every change is logged to the audit trail.")
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Space.xs)
    }
}
