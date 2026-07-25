//
//  DiskCleanupManager.swift
//  MacTweak
//
//  Surfaces the disk-space hogs every dev machine accumulates — Xcode build
//  caches, simulator junk, package-manager caches, Docker's ever-growing
//  Docker.raw — and clears them with one tap instead of a terminal session.
//  Everything here is either fully regenerable (caches, DerivedData) or an
//  explicit, confirmed, destructive action (Docker prune) — never a guess.
//

import Foundation
import SwiftUI

/// One reclaimable item: how to measure it, how to clear it, and how
/// dangerous clearing it is.
struct CleanupItem: Identifiable, Sendable {
    let id: String
    let title: String
    let blurb: String
    let icon: String
    let risk: Risk

    /// Shell that prints a human-readable size (or count) on stdout, e.g. "2.1G".
    let sizeCommand: String
    /// Shell that performs the cleanup. Always safe to re-run (idempotent).
    let clearCommand: String
    /// Button label — "Clear" by default, but some rows aren't deletions.
    let actionLabel: String
    /// Requires a confirmation dialog before running (irreversible / real data risk).
    let destructive: Bool
    /// If present, the item is greyed out ("Not installed") unless this succeeds.
    let checkCommand: String?

    init(id: String, title: String, blurb: String, icon: String, risk: Risk,
         sizeCommand: String, clearCommand: String, actionLabel: String = "Clear",
         destructive: Bool = false, checkCommand: String? = nil) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.icon = icon
        self.risk = risk
        self.sizeCommand = sizeCommand
        self.clearCommand = clearCommand
        self.actionLabel = actionLabel
        self.destructive = destructive
        self.checkCommand = checkCommand
    }
}

@MainActor
final class DiskCleanupManager: ObservableObject {

    nonisolated static let items: [CleanupItem] = [
        CleanupItem(
            id: "trash",
            title: "Empty Trash",
            blurb: "Permanently deletes everything in the Trash.",
            icon: "trash", risk: .safe,
            sizeCommand: "du -sh ~/.Trash 2>/dev/null | awk '{print $1}'",
            clearCommand: "osascript -e 'tell application \"Finder\" to empty trash' 2>/dev/null; true",
            actionLabel: "Empty", destructive: true
        ),
        CleanupItem(
            id: "user-caches",
            title: "App Caches",
            blurb: "~/Library/Caches — every app rebuilds what it needs here automatically. Apple's own protected caches (Music, CloudKit, Safari…) are skipped entirely.",
            icon: "internaldrive", risk: .safe,
            // `-not -iname "com.apple.*"` keeps this from ever descending into
            // Apple's TCC-protected per-service caches (Music, CloudKit, HomeKit,
            // Safari…) — touching those triggers a real macOS permission prompt
            // (Media & Apple Music access) instead of a quiet permission error.
            sizeCommand: "du -shc $(find ~/Library/Caches -mindepth 1 -maxdepth 1 -not -iname 'com.apple.*' 2>/dev/null) 2>/dev/null | tail -1 | awk '{print $1}'",
            clearCommand: "find ~/Library/Caches -mindepth 1 -maxdepth 1 -not -iname 'com.apple.*' -exec rm -rf {} + 2>/dev/null; true"
        ),
        CleanupItem(
            id: "xcode-derived",
            title: "Xcode DerivedData",
            blurb: "Pure build cache — Xcode regenerates it on the next build.",
            icon: "hammer", risk: .safe,
            sizeCommand: "du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null | awk '{print $1}'",
            clearCommand: "rm -rf ~/Library/Developer/Xcode/DerivedData/* 2>/dev/null; true",
            checkCommand: "test -d ~/Library/Developer/Xcode"
        ),
        CleanupItem(
            id: "xcode-device-support",
            title: "Old iOS Device Support",
            blurb: "Debug symbols for iOS versions you've connected. Xcode re-downloads the one you need.",
            icon: "iphone", risk: .moderate,
            sizeCommand: "du -sh ~/Library/Developer/Xcode/iOS\\ DeviceSupport 2>/dev/null | awk '{print $1}'",
            clearCommand: "rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport/* 2>/dev/null; true",
            checkCommand: "test -d ~/Library/Developer/Xcode/iOS\\ DeviceSupport"
        ),
        CleanupItem(
            id: "simulator-caches",
            title: "Simulator Caches",
            blurb: "CoreSimulator's own cache — safe, rebuilds as needed.",
            icon: "apps.iphone", risk: .safe,
            sizeCommand: "du -sh ~/Library/Developer/CoreSimulator/Caches 2>/dev/null | awk '{print $1}'",
            clearCommand: "rm -rf ~/Library/Developer/CoreSimulator/Caches/* 2>/dev/null; true",
            checkCommand: "test -d ~/Library/Developer/CoreSimulator"
        ),
        CleanupItem(
            id: "unavailable-simulators",
            title: "Unavailable Simulators",
            blurb: "Orphaned simulator runtimes left behind by Xcode updates (count, not size).",
            icon: "xmark.circle", risk: .safe,
            sizeCommand: "xcrun simctl list devices unavailable 2>/dev/null | grep -c unavailable",
            clearCommand: "xcrun simctl delete unavailable 2>/dev/null; true",
            actionLabel: "Delete", checkCommand: "command -v xcrun"
        ),
        CleanupItem(
            id: "homebrew-cache",
            title: "Homebrew Cache",
            blurb: "Downloaded bottles/archives for formulae you've already installed.",
            icon: "shippingbox", risk: .safe,
            sizeCommand: "du -sh \"$(brew --cache 2>/dev/null)\" 2>/dev/null | awk '{print $1}'",
            clearCommand: "brew cleanup -s 2>/dev/null; true",
            checkCommand: "command -v brew"
        ),
        CleanupItem(
            id: "npm-cache",
            title: "npm Cache",
            blurb: "~/.npm — reinstalled packages just re-download.",
            icon: "cube", risk: .safe,
            sizeCommand: "du -sh ~/.npm 2>/dev/null | awk '{print $1}'",
            clearCommand: "npm cache clean --force 2>/dev/null; true",
            checkCommand: "command -v npm"
        ),
        CleanupItem(
            id: "pip-cache",
            title: "pip Cache",
            blurb: "Downloaded Python wheels — pip re-fetches on next install.",
            icon: "terminal", risk: .safe,
            sizeCommand: "du -sh ~/Library/Caches/pip 2>/dev/null | awk '{print $1}'",
            clearCommand: "(pip cache purge 2>/dev/null || pip3 cache purge 2>/dev/null); true",
            checkCommand: "command -v pip3 || command -v pip"
        ),
        CleanupItem(
            id: "crash-reports",
            title: "Crash & Diagnostic Reports",
            blurb: "~/Library/Logs/DiagnosticReports — crash logs and spin reports macOS keeps after every app crash.",
            icon: "exclamationmark.triangle", risk: .safe,
            sizeCommand: "du -sh ~/Library/Logs/DiagnosticReports 2>/dev/null | awk '{print $1}'",
            clearCommand: "rm -rf ~/Library/Logs/DiagnosticReports/* 2>/dev/null; true",
            checkCommand: "test -d ~/Library/Logs/DiagnosticReports"
        ),
        CleanupItem(
            id: "quicklook-cache",
            title: "QuickLook Thumbnail Cache",
            blurb: "Rebuilds instantly the next time you preview a file — often bloated after browsing large photo/video folders.",
            icon: "eye", risk: .safe,
            sizeCommand: "echo '—'",
            clearCommand: "qlmanage -r cache 2>/dev/null; qlmanage -r 2>/dev/null; true",
            actionLabel: "Reset"
        ),
        CleanupItem(
            id: "mobilesync-backups",
            title: "iOS Device Backups",
            blurb: "Finder/iTunes-style backups can be large and irreplaceable — reveals them instead of deleting.",
            icon: "iphone.gen3", risk: .moderate,
            sizeCommand: "du -sh ~/Library/Application\\ Support/MobileSync/Backup 2>/dev/null | awk '{print $1}'",
            clearCommand: "open ~/Library/Application\\ Support/MobileSync/Backup 2>/dev/null; true",
            actionLabel: "Reveal in Finder",
            checkCommand: "test -d ~/Library/Application\\ Support/MobileSync/Backup"
        ),
        CleanupItem(
            id: "docker-raw",
            title: "Docker Data (Docker.raw)",
            blurb: "Every image, container, and volume lives in one sparse disk image. Shows the space it really occupies, not the much larger size it's allowed to grow to. Requires Docker Desktop running — deletes all unused images, stopped containers, and anonymous volumes.",
            icon: "shippingbox.fill", risk: .advanced,
            // `du`, not `ls -lh`: Docker.raw is *sparse*, so `ls` reports the
            // logical size it may grow into (60G on a machine using 1.5G) — a
            // number that never shrinks no matter how much you prune, which made
            // the row look broken and inflated the reclaimable headline by ~58G.
            // `du` counts blocks actually allocated, so a prune visibly lands.
            sizeCommand: "du -h ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw 2>/dev/null | awk '{print $1}'",
            // Deliberately *not* masked with `2>/dev/null; true` like the `rm`-based
            // rows: if Docker Desktop isn't running, prune fails, and masking it
            // made the row report "done." while freeing nothing. Let the real exit
            // code and daemon error through so the UI can say so.
            clearCommand: "docker system prune -af --volumes 2>&1",
            actionLabel: "Prune", destructive: true,
            checkCommand: "test -f ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
        ),
    ]

    @Published private(set) var sizes: [String: String] = [:]
    @Published private(set) var available: [String: Bool] = [:]
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var scanning = false
    @Published var lastMessage: String?

    /// Orphaned per-app leftovers — a Library entry whose owning app is no
    /// longer installed. Kept separate from `items` since it's a two-phase
    /// scan (find the paths, then show the total) rather than a fixed shell
    /// command.
    @Published private(set) var orphanedPaths: [String] = []
    @Published private(set) var orphanedBytes: Int64 = 0
    @Published private(set) var scanningOrphaned = false

    /// Off-main: measure every item's size/availability in one batch.
    func scan() async {
        scanning = true
        defer { scanning = false }
        let items = Self.items
        let results = await Task.detached { () -> [(String, String, Bool)] in
            items.map { item in
                if let check = item.checkCommand, !CommandRunner.user(check).ok {
                    return (item.id, "—", false)
                }
                let text = CommandRunner.user(item.sizeCommand).output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (item.id, text.isEmpty ? "0B" : text, true)
            }
        }.value
        for (id, size, avail) in results {
            sizes[id] = size
            available[id] = avail
        }
    }

    /// Run one item's cleanup, then re-measure just that row.
    func clean(_ item: CleanupItem) async {
        busy.insert(item.id)
        defer { busy.remove(item.id) }

        let clearCommand = item.clearCommand
        let sizeCommand = item.sizeCommand
        let (result, newSize) = await Task.detached { () -> (CommandResult, String) in
            let r = CommandRunner.user(clearCommand)
            let s = CommandRunner.user(sizeCommand).output.trimmingCharacters(in: .whitespacesAndNewlines)
            return (r, s)
        }.value

        let before = sizes[item.id] ?? "-"
        sizes[item.id] = newSize.isEmpty ? "0B" : newSize
        lastMessage = result.ok
            ? "\(item.title): \(Self.summarize(result.output) ?? "done.")"
            : "\(item.title) failed. \(result.error.isEmpty ? result.output : result.error)"
        // Deletions are irreversible — record what was cleared and how much it freed.
        Log.audit("cleanup.clean",
                  ["item": item.id, "sizeBefore": before, "sizeAfter": sizes[item.id] ?? "-",
                   "exit": "\(result.exitCode)"],
                  result: result.ok ? .ok : .failed)
    }

    /// Off-main: find Library leftovers for apps that are no longer installed.
    func scanOrphaned() async {
        scanningOrphaned = true
        defer { scanningOrphaned = false }
        let (paths, total) = await Task.detached { OrphanedAppScanner.scan() }.value
        orphanedPaths = paths
        orphanedBytes = total
    }

    /// Delete every leftover the last `scanOrphaned()` found, then re-scan.
    func cleanOrphaned() async {
        let id = "orphaned-leftovers"
        busy.insert(id)
        defer { busy.remove(id) }

        let paths = orphanedPaths
        let freed = orphanedBytes
        // Log each deleted path *before* deleting: this is unrecoverable, so the
        // trail has to survive even if the delete pass dies partway through.
        for p in paths { Log.audit("cleanup.orphaned.delete", ["path": p]) }
        await Task.detached { OrphanedAppScanner.delete(paths: paths) }.value
        lastMessage = "Removed \(paths.count) orphaned leftover\(paths.count == 1 ? "" : "s")."
        await scanOrphaned()
        Log.audit("cleanup.orphaned",
                  ["count": "\(paths.count)", "bytesFreed": "\(freed)",
                   "remaining": "\(orphanedPaths.count)"],
                  result: orphanedPaths.isEmpty ? .ok : .failed)
    }

    /// Best-effort sum of every parseable ("1.2G", "340M", …) size, for a
    /// friendly "~N GB reclaimable" headline. Count-style rows (simulators)
    /// don't parse as a size and are simply skipped from the total.
    var totalReclaimableBytes: Double {
        let itemsTotal = Self.items.reduce(0.0) { sum, item in
            guard available[item.id] != false, let s = sizes[item.id] else { return sum }
            return sum + (Self.parseSize(s) ?? 0)
        }
        return itemsTotal + Double(max(0, orphanedBytes))
    }

    /// Pull the useful one-liner out of a cleanup command's output, so the UI can
    /// say *what happened* rather than a bare "done." The tools that know how much
    /// they freed say so — `docker system prune` ends with "Total reclaimed space:
    /// 1.2GB", `brew cleanup -s` with "==> This operation has freed…".
    ///
    /// Matched by keyword rather than by "take the last line", because plenty of
    /// these commands end on something that isn't a summary at all: `npm cache
    /// clean` prints a `--force` warning and a failing `brew` ends on a Ruby
    /// backtrace frame. Returns nil (→ "done.") unless a line really reports space.
    nonisolated static func summarize(_ output: String) -> String? {
        let keywords = ["reclaimed", "freed", "deleted", "removed"]
        for raw in output.split(separator: "\n").reversed() {
            let text = raw.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "==> ", with: "")
            guard !text.isEmpty, text.count <= 120 else { continue }
            let lower = text.lowercased()
            if keywords.contains(where: lower.contains) { return text }
        }
        return nil
    }

    nonisolated static func parseSize(_ s: String) -> Double? {
        guard let unit = s.last, let value = Double(s.dropLast()) else { return nil }
        switch unit {
        case "T": return value * 1_000_000_000_000
        case "G": return value * 1_000_000_000
        case "M": return value * 1_000_000
        case "K": return value * 1_000
        case "B": return value
        default: return nil
        }
    }
}
