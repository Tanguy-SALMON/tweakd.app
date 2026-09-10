//
//  LegacyMigration.swift
//  tweakd
//
//  Adopts the state the app left behind when it was called MacTweak.
//
//  Renaming an app changes its bundle identifier, and the bundle identifier is
//  what macOS keys preferences on. Ship the rename with nothing else and the app
//  looks *brand new* on an existing install: onboarding runs again, favorites and
//  tweak order are gone, the window forgets its position, benchmark history
//  vanishes, and the audit log starts from zero — while all of it sits intact in
//  directories nothing reads any more.
//
//  So this runs once, before the first preference read or log write, and moves
//  that state across. It is deliberately conservative: it never overwrites a
//  value the new name already has, and it never deletes anything it couldn't
//  move.
//
//  Artifacts NOT handled here, on purpose — they live in root-owned files or in
//  other applications' config, so migrating them would mean a password prompt at
//  launch. Those are handled by *recognising both names* at the point of use
//  instead (see `Brand` and its callers):
//    • /etc/sudoers.d/mactweak      → CommandRunner removes either path
//    • /etc/hosts ad-block markers  → AdBlock strips either marker pair
//    • Firefox user.js marker       → the tweak's status/revert match either
//

import Foundation

enum LegacyMigration {

    private static let flagKey = "migrated.from.mactweak"

    /// Idempotent. Cheap enough to call unconditionally at launch.
    static func runIfNeeded() {
        // Agent re-registration is guarded by its own on-disk condition rather
        // than the flag, so it still completes if a previous run was interrupted.
        migrateAdblockAgent()

        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        // File moves first: logging here would create the new log directory and
        // make the directory move below fall back to the slower per-file path.
        let movedSupport = moveDirectory(from: Brand.legacySupportDir, to: Brand.supportDir)
        let movedLogs = migrateLogs()
        let keys = migratePreferences()

        UserDefaults.standard.set(true, forKey: flagKey)

        // Only now is it safe to log.
        if movedSupport || movedLogs || keys > 0 {
            Log.audit("migration.rename", [
                "from": Brand.legacyName,
                "prefKeys": "\(keys)",
                "support": movedSupport ? "moved" : "none",
                "logs": movedLogs ? "moved" : "none",
            ], result: .ok)
        }
    }

    // MARK: - Preferences

    /// Copy the old domain's keys into the new one. Returns how many were taken.
    ///
    /// The old domain is left in place: it's inert once nothing reads it, and
    /// deleting a user's only copy of their settings to save a few kilobytes is
    /// a bad trade if any of this turns out to be wrong.
    private static func migratePreferences() -> Int {
        guard let old = UserDefaults.standard.persistentDomain(forName: Brand.legacyBundleID),
              !old.isEmpty else { return 0 }
        var taken = 0
        for (key, value) in old where UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(value, forKey: key)
            taken += 1
        }
        return taken
    }

    // MARK: - Directories

    /// Move `src` to `dst`. If `dst` already exists, move the *contents* in
    /// instead, so an early-created empty directory doesn't block the migration.
    private static func moveDirectory(from src: String, to dst: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src) else { return false }
        if !fm.fileExists(atPath: dst) {
            try? fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
            if (try? fm.moveItem(atPath: src, toPath: dst)) != nil { return true }
        }
        var moved = false
        for item in (try? fm.contentsOfDirectory(atPath: src)) ?? [] {
            let target = "\(dst)/\(item)"
            guard !fm.fileExists(atPath: target) else { continue }
            if (try? fm.moveItem(atPath: "\(src)/\(item)", toPath: target)) != nil { moved = true }
        }
        // Only remove the source if it's now empty — never discard files we
        // failed to move.
        if ((try? fm.contentsOfDirectory(atPath: src)) ?? []).isEmpty {
            try? fm.removeItem(atPath: src)
        }
        return moved
    }

    /// Same as above, but renames `MacTweak.log` → `tweakd.log` on the way so the
    /// audit history stays in the file the app now appends to.
    private static func migrateLogs() -> Bool {
        let fm = FileManager.default
        let oldLog = "\(Brand.legacyLogDir)/\(Brand.legacyName).log"
        let newLog = "\(Brand.logDir)/\(Brand.name).log"
        guard fm.fileExists(atPath: oldLog) else { return moveDirectory(from: Brand.legacyLogDir, to: Brand.logDir) }
        try? fm.createDirectory(atPath: Brand.logDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: newLog) {
            // Both exist: keep the old one alongside rather than clobbering either.
            let keep = "\(Brand.logDir)/\(Brand.legacyName).log"
            return (try? fm.moveItem(atPath: oldLog, toPath: keep)) != nil
        }
        let ok = (try? fm.moveItem(atPath: oldLog, toPath: newLog)) != nil
        _ = moveDirectory(from: Brand.legacyLogDir, to: Brand.logDir)
        return ok
    }

    // MARK: - LaunchAgent

    /// Re-register the weekly ad-block updater under the new label.
    ///
    /// Two reasons this can't just be a file rename: launchd keys the loaded job
    /// on the `Label` *inside* the plist, and the old agent's helper script has
    /// the old `/etc/hosts` markers baked into it. So the new one is written from
    /// scratch and the old job is booted out and deleted — otherwise the Mac ends
    /// up running two weekly rebuilds that fight over the same block.
    private static func migrateAdblockAgent() {
        let fm = FileManager.default
        let legacyPlist = "\(Brand.launchAgentDir)/\(Brand.legacyAdblockLabel).plist"
        guard fm.fileExists(atPath: legacyPlist) else { return }

        let newPlist = "\(Brand.launchAgentDir)/\(Brand.adblockLabel).plist"
        let script = "\(Brand.supportDir)/adblock-update.sh"
        let supportDir = Brand.supportDir, agentDir = Brand.launchAgentDir

        Task.detached {
            _ = CommandRunner.user("launchctl unload '\(legacyPlist)' 2>/dev/null")
            try? FileManager.default.removeItem(atPath: legacyPlist)
            AdBlockManager.installOffMain(script: script, plist: newPlist,
                                          supportDir: supportDir, launchAgentDir: agentDir)
            Log.audit("migration.adblockAgent",
                      ["from": Brand.legacyAdblockLabel, "to": Brand.adblockLabel], result: .ok)
        }
    }
}
