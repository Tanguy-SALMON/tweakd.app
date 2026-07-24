//
//  AdBlockManager.swift
//  MacTweak
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
    static let markerStart = "# MacTweak-adblock-start"
    static let markerEnd = "# MacTweak-adblock-end"

    /// Download the StevenBlack list and (re)build the marked `0.0.0.0` block in
    /// /etc/hosts, preserving everything else. Idempotent (strips any prior block
    /// first); a failed or empty download leaves /etc/hosts untouched. Root.
    static let rebuildCommand = "L=$(mktemp); T=$(mktemp); if curl -fsSL --max-time 30 https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts -o \"$L\" && [ -s \"$L\" ]; then sed '/# MacTweak-adblock-start/,/# MacTweak-adblock-end/d' /etc/hosts > \"$T\"; echo '# MacTweak-adblock-start' >> \"$T\"; grep '^0\\.0\\.0\\.0 ' \"$L\" >> \"$T\"; echo '# MacTweak-adblock-end' >> \"$T\"; cat \"$T\" > /etc/hosts; dscacheutil -flushcache; killall -HUP mDNSResponder; fi; rm -f \"$L\" \"$T\"; true"

    /// Manual-refresh command for the Quick Action: only refreshes when the
    /// block is already active, so a refresh never silently *enables* blocking.
    static let refreshIfActiveCommand = "if grep -q '\(markerStart)' /etc/hosts; then \(rebuildCommand); else echo 'Enable \"Block Ads & Trackers\" first.'; fi"
}

@MainActor
final class AdBlockManager: ObservableObject {

    private let launchAgentDir = "\(NSHomeDirectory())/Library/LaunchAgents"
    private let supportDir = "\(NSHomeDirectory())/Library/Application Support/MacTweak"
    private var plistPath: String { "\(launchAgentDir)/com.mactweak.adblock.plist" }
    private var scriptPath: String { "\(supportDir)/adblock-update.sh" }

    /// Whether the weekly updater LaunchAgent is currently installed.
    @Published private(set) var autoUpdating = false

    init() { autoUpdating = FileManager.default.fileExists(atPath: plistPath) }

    /// Keep the weekly updater in lock-step with the tweak: install it when
    /// ad-blocking is on, remove it when off. Writes only user-space files and
    /// `launchctl load` (no admin prompt) — the agent itself uses `sudo -n` at
    /// run time.
    func reconcile(adBlockApplied: Bool) {
        let exists = FileManager.default.fileExists(atPath: plistPath)
        if adBlockApplied, !exists { install() }
        else if !adBlockApplied, exists { remove() }
    }

    private func install() {
        autoUpdating = true
        let script = scriptPath, plist = plistPath, sDir = supportDir, lDir = launchAgentDir
        Task.detached { Self.installOffMain(script: script, plist: plist, supportDir: sDir, launchAgentDir: lDir) }
    }

    private func remove() {
        autoUpdating = false
        let script = scriptPath, plist = plistPath
        Task.detached {
            _ = CommandRunner.user("launchctl unload \(Self.shellQuote(plist)) 2>/dev/null")
            try? FileManager.default.removeItem(atPath: plist)
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
            <string>com.mactweak.adblock</string>
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
