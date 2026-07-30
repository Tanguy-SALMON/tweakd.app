//
//  AdBlockManager.swift
//  tweakd
//
//  Keeps the /etc/hosts ad-block list fresh. StevenBlack updates the source
//  list constantly, so a one-time download goes stale — this installs a weekly
//  LaunchAgent that silently re-downloads and rebuilds the marked block in the
//  background, mirroring PriorityManager's passwordless login-agent pattern.
//
//  The agent runs as the user but /etc/hosts needs root, so it shells out to
//  `sudo -n` (passwordless once admin is unlocked). If passwordless admin isn't
//  set up the refresh just fails quietly — the existing block stays in place.
//

import Foundation
import SwiftUI

/// Single source of truth for the hosts-block shell logic, shared by the tweak,
/// the manual Quick Action, and the weekly auto-updater so they can never drift.
enum AdBlock {
    static let markerStart = Brand.hostsMarkerStart
    static let markerEnd = Brand.hostsMarkerEnd

    /// Strips **both** the current and the legacy MacTweak-era block. A Mac that
    /// had ad-blocking on before the rename still carries `# MacTweak-adblock-*`
    /// markers around ~200k entries; if we only stripped the new markers, that
    /// block would be unremovable from the UI and a rebuild would stack a second
    /// copy on top of it.
    private static let stripBoth =
        "sed -e '/\(Brand.hostsMarkerStart)/,/\(Brand.hostsMarkerEnd)/d'"
        + " -e '/\(Brand.legacyHostsMarkerStart)/,/\(Brand.legacyHostsMarkerEnd)/d'"

    /// Matches either marker, for status checks.
    static let anyMarkerGrep = "grep -qE '\(Brand.hostsMarkerStart)|\(Brand.legacyHostsMarkerStart)'"

    /// Download the StevenBlack list and (re)build the marked `0.0.0.0` block in
    /// /etc/hosts, preserving everything else. Idempotent (strips any prior block
    /// first); a failed or empty download leaves /etc/hosts untouched. Root.
    static let rebuildCommand = "L=$(mktemp); T=$(mktemp); if curl -fsSL --max-time 30 https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts -o \"$L\" && [ -s \"$L\" ]; then \(stripBoth) /etc/hosts > \"$T\"; echo '\(markerStart)' >> \"$T\"; grep '^0\\.0\\.0\\.0 ' \"$L\" >> \"$T\"; echo '\(markerEnd)' >> \"$T\"; cat \"$T\" > /etc/hosts; dscacheutil -flushcache; killall -HUP mDNSResponder; fi; rm -f \"$L\" \"$T\"; true"

    /// Remove the block under either name.
    static let removeCommand = "T=$(mktemp); \(stripBoth) /etc/hosts > \"$T\"; cat \"$T\" > /etc/hosts; rm -f \"$T\"; dscacheutil -flushcache; killall -HUP mDNSResponder; true"

    /// Manual-refresh command for the Quick Action: only refreshes when the
    /// block is already active, so a refresh never silently *enables* blocking.
    static let refreshIfActiveCommand = "if \(anyMarkerGrep) /etc/hosts; then \(rebuildCommand); else echo 'Enable \"Block Ads & Trackers\" first.'; fi"
}

@MainActor
final class AdBlockManager: ObservableObject {

    private let launchAgentDir = Brand.launchAgentDir
    private let supportDir = Brand.supportDir
    private var plistPath: String { "\(launchAgentDir)/\(Brand.adblockLabel).plist" }
    private var legacyPlistPath: String { "\(launchAgentDir)/\(Brand.legacyAdblockLabel).plist" }
    private var scriptPath: String { "\(supportDir)/adblock-update.sh" }

    /// Whether the weekly updater LaunchAgent is currently installed — under
    /// either name, so a pre-rename install isn't reported as "off" (which would
    /// make `reconcile` install a second, duplicate agent).
    @Published private(set) var autoUpdating = false

    init() {
        let fm = FileManager.default
        autoUpdating = fm.fileExists(atPath: plistPath) || fm.fileExists(atPath: legacyPlistPath)
    }

    /// Keep the weekly updater in lock-step with the tweak: install it when
    /// ad-blocking is on, remove it when off. Writes only user-space files and
    /// `launchctl load` (no admin prompt) — the agent itself uses `sudo -n` at
    /// run time.
    func reconcile(adBlockApplied: Bool) {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: plistPath) || fm.fileExists(atPath: legacyPlistPath)
        if adBlockApplied, !exists {
            install()
            Log.audit("adblock.autoUpdate", ["enabled": "yes", "schedule": "weekly-mon-03:00"], result: .ok)
        } else if !adBlockApplied, exists {
            remove()
            Log.audit("adblock.autoUpdate", ["enabled": "no"], result: .ok)
        }
    }

    private func install() {
        autoUpdating = true
        let script = scriptPath, plist = plistPath, sDir = supportDir, lDir = launchAgentDir
        Task.detached { Self.installOffMain(script: script, plist: plist, supportDir: sDir, launchAgentDir: lDir) }
    }

    private func remove() {
        autoUpdating = false
        let script = scriptPath, plist = plistPath, legacy = legacyPlistPath
        Task.detached {
            // Unload/delete both names: a Mac that enabled ad-blocking before the
            // rename has the agent installed under the old label, and skipping it
            // would leave a weekly job running with nothing in the UI to stop it.
            for p in [plist, legacy] {
                _ = CommandRunner.user("launchctl unload \(Self.shellQuote(p)) 2>/dev/null")
                try? FileManager.default.removeItem(atPath: p)
            }
            try? FileManager.default.removeItem(atPath: script)
        }
    }

    // MARK: - Off-main file writing

    nonisolated static func installOffMain(script: String, plist: String, supportDir: String, launchAgentDir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: launchAgentDir, withIntermediateDirectories: true)

        // The refresh logic as a standalone script, so the plist can invoke it
        // via `sudo -n /bin/zsh <script>` without any nested-quote gymnastics.
        let body = "#!/bin/zsh\n\(AdBlock.rebuildCommand)\n"
        guard (try? body.write(toFile: script, atomically: true, encoding: .utf8)) != nil else { return }
        _ = CommandRunner.user("chmod +x \(shellQuote(script))")

        let agentCmd = "/usr/bin/sudo -n /bin/zsh \(shellQuote(script)) 2>/dev/null; true"
        // Weekly: Monday 03:00. launchd runs a missed calendar event at next
        // wake, so a sleeping Mac still gets refreshed. No RunAtLoad — enabling
        // the tweak already downloaded a fresh list, so there's nothing to redo
        // on the immediately-following load/login.
        let plistBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Brand.adblockLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/sh</string>
                <string>-c</string>
                <string>\(xmlEscape(agentCmd))</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Weekday</key><integer>1</integer>
                <key>Hour</key><integer>3</integer>
                <key>Minute</key><integer>0</integer>
            </dict>
            <key>RunAtLoad</key>
            <false/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        guard (try? plistBody.write(toFile: plist, atomically: true, encoding: .utf8)) != nil else { return }
        _ = CommandRunner.user("launchctl unload \(shellQuote(plist)) 2>/dev/null; launchctl load \(shellQuote(plist))")
    }

    nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
