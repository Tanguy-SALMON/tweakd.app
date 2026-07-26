//
//  ServicesManager.swift
//  MacTweak
//
//  Background services (launchd jobs) you can actually see and switch off:
//  Homebrew dev servers, vendor updaters, helper daemons. Answers "what is
//  running behind my back, what does it cost, and can I stop it?".
//
//  Talks to `launchctl` directly rather than `brew services` on purpose. Brew's
//  wrapper is only a launchd front-end, and it breaks hard on new macOS releases
//  (on macOS 26 it dies with "unknown or unsupported macOS version" before doing
//  anything). launchd is the actual source of truth and is always present.
//
//  Two deliberate boundaries:
//   • **Apple's own daemons are never listed.** They're SIP-protected, deeply
//     interdependent, and switching them off is how people break their Mac. The
//     handful worth touching already ship as reversible tweaks in the catalog.
//   • **Security/EDR agents are listed read-only.** On a managed Mac these are
//     required by policy, and quietly disabling one is both a compliance problem
//     and a real reduction in protection. Shown for transparency, not switched.
//

import Foundation
import SwiftUI

/// Which launchd domain a job lives in — decides both the `launchctl` target
/// syntax and whether changing it needs admin.
enum ServiceDomain: String, Sendable {
    case user     // gui/<uid> — ~/Library/LaunchAgents and /Library/LaunchAgents
    case system   // system    — /Library/LaunchDaemons, runs as root

    var badge: String { self == .user ? "User" : "System" }
    /// System-domain changes need root; user-domain ones never prompt.
    var needsAdmin: Bool { self == .system }
}

/// Coarse grouping that drives both the UI sections and how freely a row may be
/// switched off.
enum ServiceKind: String, Sendable, CaseIterable {
    case developer   // Homebrew servers, local model runners — yours, safe to stop
    case updater     // vendor auto-updaters — safe, you just update manually
    case vendor      // app helper daemons — moderate, the app may expect them
    case security    // EDR / management agents — shown but never switched
    case mactweak    // MacTweak's own agents
    case other

    var title: String {
        switch self {
        case .developer: return "Developer services"
        case .updater:   return "Auto-updaters"
        case .vendor:    return "App helpers"
        case .security:  return "Security & management"
        case .mactweak:  return "MacTweak"
        case .other:     return "Other"
        }
    }

    var blurb: String {
        switch self {
        case .developer: return "Databases, web servers and model runners you installed. Safe to stop when you're not developing — nothing else depends on them."
        case .updater:   return "Vendor update checkers. Disabling one means you update that app manually; it breaks nothing else."
        case .vendor:    return "Helper daemons installed by apps. Stopping one usually just means the app starts it again, or loses a background feature."
        case .security:  return "Endpoint protection and device management. Shown for transparency — MacTweak won't switch these off."
        case .mactweak:  return "Agents MacTweak installed itself."
        case .other:     return "Everything else that isn't Apple's."
        }
    }

    var icon: String {
        switch self {
        case .developer: return "hammer.fill"
        case .updater:   return "arrow.triangle.2.circlepath"
        case .vendor:    return "shippingbox.fill"
        case .security:  return "lock.shield.fill"
        case .mactweak:  return "slider.horizontal.3"
        case .other:     return "gearshape.fill"
        }
    }

    /// Display order — the things you're most likely to want off come first.
    var order: Int {
        switch self {
        case .developer: return 0
        case .updater:   return 1
        case .vendor:    return 2
        case .other:     return 3
        case .mactweak:  return 4
        case .security:  return 5
        }
    }

    /// Whether MacTweak will let the user change this group at all.
    var controllable: Bool { self != .security }
}

/// One launchd job, merged from its plist on disk and its live state.
struct LaunchService: Identifiable, Sendable, Hashable {
    /// Domain-qualified: the *same* label can exist as both a user agent and a
    /// system daemon (Homebrew installs some services twice), and they are two
    /// genuinely different jobs.
    var id: String { "\(domain.rawValue)/\(label)" }

    let label: String
    let plistPath: String
    let domain: ServiceDomain
    let kind: ServiceKind
    /// Executable the job runs, for display.
    let program: String
    /// PID when loaded *and* running; nil when merely loaded, or not loaded.
    let pid: Int32?
    /// Exit status of the last run — non-zero on a job that keeps failing.
    let lastExit: Int?
    /// `launchctl disable`d — won't start at login even though the plist exists.
    let disabled: Bool
    /// Present in launchd's inventory at all.
    let loaded: Bool
    let cpu: Double
    let memoryMB: Double

    var running: Bool { pid != nil }

    /// Short, human name: `homebrew.mxcl.mysql@8.0` → `mysql@8.0`.
    var displayName: String {
        var n = label
        for prefix in ["homebrew.mxcl.", "com.", "org.", "io.", "ai.", "co."] where n.hasPrefix(prefix) {
            n = String(n.dropFirst(prefix.count)); break
        }
        return n
    }

    /// One-line state for the row subtitle.
    var statusText: String {
        if disabled { return "Disabled — won't start at login" }
        if let pid { return "Running · pid \(pid)" }
        if let e = lastExit, e != 0 { return "Not running — last exit \(e)" }
        return loaded ? "Loaded, idle" : "Not loaded"
    }
}

@MainActor
final class ServicesManager: ObservableObject {

    @Published private(set) var services: [LaunchService] = []
    @Published private(set) var scanning = false
    @Published private(set) var busy: Set<String> = []
    @Published var lastMessage: String?
    /// True once a scan has run, so the UI can tell "empty" from "not scanned".
    @Published private(set) var scanned = false

    // MARK: - Grouping

    func grouped() -> [(kind: ServiceKind, items: [LaunchService])] {
        Dictionary(grouping: services, by: \.kind)
            .map { (kind: $0.key, items: $0.value.sorted { a, b in
                if a.running != b.running { return a.running }        // running first
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }) }
            .sorted { $0.kind.order < $1.kind.order }
    }

    var runningCount: Int { services.filter(\.running).count }
    var controllableCount: Int { services.filter { $0.kind.controllable }.count }

    /// Labels present in *both* domains. Stopping only one of the pair leaves the
    /// process running, which looks like the button did nothing — the UI warns.
    var duplicatedLabels: Set<String> {
        let user = Set(services.filter { $0.domain == .user }.map(\.label))
        let system = Set(services.filter { $0.domain == .system }.map(\.label))
        return user.intersection(system)
    }

    // MARK: - Discovery

    func scan() async {
        scanning = true
        defer { scanning = false; scanned = true }
        services = await Task.detached { Self.discover() }.value
    }

    /// Off-main: read every non-Apple job from the three launchd directories and
    /// merge in live state from `launchctl` and `ps`.
    nonisolated static func discover() -> [LaunchService] {
        let home = NSHomeDirectory()
        let sources: [(String, ServiceDomain)] = [
            ("\(home)/Library/LaunchAgents", .user),
            ("/Library/LaunchAgents", .user),
            ("/Library/LaunchDaemons", .system),
        ]

        // Per-domain, because the same label can exist in both and they are
        // different jobs with different state. Plain `launchctl list` only ever
        // reports the caller's own domain, which made a system daemon inherit the
        // user agent's status — exactly backwards for Homebrew services installed
        // twice, where the *system* one is the copy actually running.
        let userState = domainState("gui/\(getuid())")
        let systemState = domainState("system")

        var out: [LaunchService] = []
        var seen = Set<String>()

        for (dir, domain) in sources {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for name in names.sorted() where name.hasSuffix(".plist") {
                let path = "\(dir)/\(name)"
                let (label, program) = readPlist(path: path, fallbackLabel: String(name.dropLast(6)))

                // Apple's own jobs are out of scope entirely — SIP-protected and
                // load-bearing. The few worth touching ship as reversible tweaks.
                if label.hasPrefix("com.apple.") { continue }

                let key = "\(domain.rawValue)/\(label)"
                if seen.contains(key) { continue }   // /Library wins over ~/Library
                seen.insert(key)

                let state = domain == .user ? userState : systemState
                out.append(LaunchService(
                    label: label,
                    plistPath: path,
                    domain: domain,
                    kind: classify(label: label, program: program),
                    program: program,
                    pid: state.running[label],
                    lastExit: state.lastStatus[label],
                    disabled: state.disabled.contains(label),
                    loaded: state.known.contains(label),
                    cpu: 0, memoryMB: 0
                ))
            }
        }
        return attachUsage(to: out)
    }

    /// Everything known about one launchd domain.
    struct DomainState: Sendable {
        var running: [String: Int32] = [:]    // label → pid, only when actually running
        var lastStatus: [String: Int] = [:]   // label → last exit status, when reported
        var disabled: Set<String> = []        // explicitly `launchctl disable`d
        var known: Set<String> = []           // present in the domain at all
    }

    /// Parse one `launchctl print <domain>` — authoritative for that domain and,
    /// usefully, readable **without root** for `system` too. Yields both the
    /// service table and the disabled list from a single call.
    ///
    /// The output nests two blocks we care about:
    /// ```
    ///     services = {
    ///            297      - 	homebrew.mxcl.nginx      <- pid, status, label
    ///              0      0 	com.docker.socket        <- pid 0 = not running
    ///          25900   (pe) 	com.apple.foo            <- status can be non-numeric
    ///     }
    ///     disabled services = {
    ///         "homebrew.mxcl.php@8.1" => enabled
    ///     }
    /// ```
    nonisolated static func domainState(_ domain: String) -> DomainState {
        let r = CommandRunner.user("/bin/launchctl print \(domain) 2>/dev/null")
        var state = DomainState()
        guard r.ok else { return state }

        enum Block { case none, services, disabled }
        var block = Block.none

        for raw in r.output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // "disabled services" first — it also contains the word "services".
            if line.hasPrefix("disabled services = {") { block = .disabled; continue }
            if line.hasPrefix("services = {") { block = .services; continue }
            if line == "}" { block = .none; continue }

            switch block {
            case .none:
                continue
            case .disabled:
                guard let open = line.firstIndex(of: "\""),
                      let close = line[line.index(after: open)...].firstIndex(of: "\"") else { continue }
                let label = String(line[line.index(after: open)..<close])
                if line.hasSuffix("=> disabled") { state.disabled.insert(label) }
                state.known.insert(label)
            case .services:
                let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard f.count >= 3 else { continue }
                let label = String(f[f.count - 1])
                state.known.insert(label)
                // pid 0 means "known but not running"; a real pid means running.
                if let pid = Int32(f[0]), pid > 0 { state.running[label] = pid }
                if let status = Int(f[1]) { state.lastStatus[label] = status }
            }
        }
        return state
    }

    /// One `ps` pass for every running pid, folded back into the rows.
    nonisolated static func attachUsage(to services: [LaunchService]) -> [LaunchService] {
        let pids = services.compactMap(\.pid)
        guard !pids.isEmpty else { return services }
        let r = CommandRunner.user("/bin/ps -o pid=,%cpu=,rss= -p \(pids.map(String.init).joined(separator: " "))")
        guard r.ok else { return services }

        var usage: [Int32: (Double, Double)] = [:]
        for line in r.output.split(separator: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 3, let pid = Int32(f[0]),
                  let cpu = Double(f[1]), let rss = Double(f[2]) else { continue }
            usage[pid] = (cpu, rss / 1024.0)     // rss is KB
        }
        return services.map { s in
            guard let pid = s.pid, let u = usage[pid] else { return s }
            return LaunchService(label: s.label, plistPath: s.plistPath, domain: s.domain,
                                 kind: s.kind, program: s.program, pid: s.pid,
                                 lastExit: s.lastExit, disabled: s.disabled, loaded: s.loaded,
                                 cpu: u.0, memoryMB: u.1)
        }
    }

    /// Label (and program) from the plist — binary or XML, both handled.
    /// Falls back to the filename, which is the convention launchd itself expects.
    nonisolated static func readPlist(path: String, fallbackLabel: String) -> (label: String, program: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return (fallbackLabel, "") }

        let label = (dict["Label"] as? String) ?? fallbackLabel
        var program = (dict["Program"] as? String) ?? ""
        if program.isEmpty, let args = dict["ProgramArguments"] as? [String] {
            // Skip the shell wrapper Homebrew and friends use, so the row names
            // the actual server rather than "/bin/sh".
            program = args.first(where: { $0.hasPrefix("/") && !$0.hasSuffix("/sh") && !$0.hasSuffix("/bash") })
                ?? args.first ?? ""
        }
        return (label, program)
    }

    /// Bucket a job by label and executable path. Ordered most-specific first —
    /// security wins over everything so an EDR agent can never fall through into
    /// a controllable group.
    nonisolated static func classify(label: String, program: String) -> ServiceKind {
        let l = label.lowercased()
        let p = program.lowercased()

        let security = ["paloaltonetworks", "cortex", "crowdstrike", "falcon", "sentinelone",
                        "carbonblack", "jamf", "microsoft.defender", "wdav", "sophos",
                        "mcafee", "trendmicro", "eset", "kandji", "mosyle", "intune"]
        if security.contains(where: { l.contains($0) || p.contains($0) }) { return .security }

        if l.hasPrefix("com.mactweak") { return .mactweak }

        let updater = ["update", "updater", "keystone", "autoupdate", "sparkle", "wake"]
        if updater.contains(where: { l.contains($0) }) { return .updater }

        if l.hasPrefix("homebrew.mxcl.") { return .developer }
        let dev = ["mysql", "mariadb", "postgres", "redis", "nginx", "php", "httpd", "mongod",
                   "elastic", "rabbitmq", "memcached", "ollama", "mlx", "jupyter", "gateway",
                   "honcho", "minio", "consul", "supabase"]
        if dev.contains(where: { l.contains($0) }) || p.contains("/opt/homebrew/") { return .developer }

        let vendor = ["docker", "teamviewer", "vmware", "parallels", "adobe", "dropbox",
                      "google", "microsoft", "logitech", "citrix", "zoom", "slack"]
        if vendor.contains(where: { l.contains($0) }) { return .vendor }

        return .other
    }

    // MARK: - Control

    /// `launchctl` target for this job, e.g. `gui/501/homebrew.mxcl.redis`.
    nonisolated static func target(_ s: LaunchService) -> String {
        s.domain == .system ? "system/\(s.label)" : "gui/\(getuid())/\(s.label)"
    }

    nonisolated static func domainTarget(_ s: LaunchService) -> String {
        s.domain == .system ? "system" : "gui/\(getuid())"
    }

    /// Stop the job now. It comes back at the next login/boot — that's the point
    /// of keeping this separate from `setEnabled(false)`.
    func stop(_ s: LaunchService) async {
        guard guardControllable(s) else { return }
        busy.insert(s.id); defer { busy.remove(s.id) }

        let cmd = "/bin/launchctl bootout \(Self.target(s))"
        let result = await run(cmd, admin: s.domain.needsAdmin)
        guard !result.userCancelled else {
            lastMessage = "Cancelled."
            Log.audit("service.stop", ["label": s.label, "domain": s.domain.rawValue], result: .cancelled)
            return
        }
        await scan()
        let nowStopped = services.first { $0.id == s.id }?.running != true
        lastMessage = nowStopped
            ? "\(s.displayName) stopped. It will start again at login — use Disable to prevent that."
            : "Couldn't stop \(s.displayName). \(Self.detail(result))"
        Log.audit("service.stop",
                  ["label": s.label, "domain": s.domain.rawValue, "exit": "\(result.exitCode)"],
                  result: nowStopped ? .ok : .failed)
    }

    /// Persistently enable or disable the job. Disabling also stops it now;
    /// enabling also starts it — otherwise the button appears to do nothing until
    /// the next reboot.
    func setEnabled(_ s: LaunchService, _ enabled: Bool) async {
        guard guardControllable(s) else { return }
        busy.insert(s.id); defer { busy.remove(s.id) }

        let t = Self.target(s)
        let dom = Self.domainTarget(s)
        let quoted = Self.shellQuote(s.plistPath)
        // `disable` only sets the flag and `enable` only clears it, so each is
        // paired with the matching runtime action. `|| true` on bootout: it fails
        // when the job isn't loaded, which is a no-op, not an error.
        let cmd = enabled
            ? "/bin/launchctl enable \(t); /bin/launchctl bootstrap \(dom) \(quoted) 2>&1 || true"
            : "/bin/launchctl disable \(t); /bin/launchctl bootout \(t) 2>&1 || true"

        let result = await run(cmd, admin: s.domain.needsAdmin)
        guard !result.userCancelled else {
            lastMessage = "Cancelled."
            Log.audit("service.setEnabled", ["label": s.label, "enabled": enabled ? "yes" : "no"],
                      result: .cancelled)
            return
        }

        await scan()
        let after = services.first { $0.id == s.id }
        let ok = after.map { $0.disabled == !enabled } ?? false
        lastMessage = ok
            ? (enabled ? "\(s.displayName) enabled and started."
                       : "\(s.displayName) disabled — it won't start at login.")
            : "Couldn't \(enabled ? "enable" : "disable") \(s.displayName). \(Self.detail(result))"
        Log.audit("service.setEnabled",
                  ["label": s.label, "domain": s.domain.rawValue,
                   "enabled": enabled ? "yes" : "no", "exit": "\(result.exitCode)"],
                  result: ok ? .ok : .failed)
    }

    /// Disable every controllable job in a group in one pass — the "I don't do
    /// PHP on this machine any more" button.
    func disableAll(kind: ServiceKind) async {
        guard kind.controllable else { return }
        let victims = services.filter { $0.kind == kind && !$0.disabled }
        guard !victims.isEmpty else { lastMessage = "Nothing to disable in \(kind.title)."; return }

        Log.audit("service.disableAll.begin", ["kind": kind.rawValue, "count": "\(victims.count)"])
        for s in victims {
            await setEnabled(s, false)
            if lastMessage == "Cancelled." { break }   // user dismissed the auth prompt
        }
        await scan()
        let left = services.filter { $0.kind == kind && !$0.disabled }.count
        lastMessage = "\(kind.title): \(victims.count - left) disabled\(left > 0 ? ", \(left) left" : "")."
        Log.audit("service.disableAll", ["kind": kind.rawValue, "remaining": "\(left)"],
                  result: left == 0 ? .ok : .failed)
    }

    // MARK: - Internals

    /// Refuse to touch the protected group, loudly rather than silently.
    private func guardControllable(_ s: LaunchService) -> Bool {
        guard s.kind.controllable else {
            lastMessage = "\(s.displayName) is a security/management agent — MacTweak won't change it."
            Log.audit("service.blocked", ["label": s.label, "kind": s.kind.rawValue], result: .skipped)
            return false
        }
        return true
    }

    private func run(_ command: String, admin: Bool) async -> CommandResult {
        await Task.detached { admin ? CommandRunner.admin(command) : CommandRunner.user(command) }.value
    }

    nonisolated static func detail(_ r: CommandResult) -> String {
        let d = r.error.isEmpty ? r.output : r.error
        return d.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
