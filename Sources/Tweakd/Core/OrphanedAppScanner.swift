//
//  OrphanedAppScanner.swift
//  tweakd
//
//  Finds per-app Library data whose owning app is gone — caches, saved state,
//  and support files left behind after an app was deleted by dragging it to
//  the Trash instead of properly uninstalling. Deliberately scoped to
//  *leftovers*, not a general uninstaller: it never touches anything for an
//  app that's still installed, and it never touches anything under
//  `com.apple.` — that's the OS's own, not a leftover.
//

import Foundation

enum OrphanedAppScanner {

    /// Library subfolders whose entries are conventionally named by bundle
    /// identifier (`com.vendor.app`) or `<bundle id>.savedState`.
    private static let scanRoots: [String] = [
        "~/Library/Caches",
        "~/Library/Application Support",
        "~/Library/Saved Application State",
        "~/Library/HTTPStorages",
        "~/Library/WebKit",
        "~/Library/Containers",
    ]

    private static let appDirs = ["/Applications", NSHomeDirectory() + "/Applications"]

    /// Off-main: cross-reference installed bundle IDs against Library entries
    /// that look like app data but match no installed app. Returns the
    /// leftover paths and their total size.
    nonisolated static func scan() -> (paths: [String], totalBytes: Int64) {
        let installed = installedBundleIDs()
        let fm = FileManager.default
        var paths: [String] = []
        var total: Int64 = 0

        for root in scanRoots {
            let expanded = (root as NSString).expandingTildeInPath
            guard let entries = try? fm.contentsOfDirectory(atPath: expanded) else { continue }
            for entry in entries {
                let bundleLike = entry.hasSuffix(".savedState") ? String(entry.dropLast(".savedState".count)) : entry
                // Only consider entries that look like a bundle identifier —
                // skip loose files (e.g. plain cache dirs, .DS_Store) and
                // anything that's Apple's own.
                guard bundleLike.contains("."), !bundleLike.hasPrefix("com.apple.") else { continue }
                guard !installed.contains(bundleLike) else { continue }

                let full = "\(expanded)/\(entry)"
                paths.append(full)
                total += directorySize(full, fm: fm)
            }
        }
        return (paths, total)
    }

    /// Off-main: delete every path a prior `scan()` reported.
    nonisolated static func delete(paths: [String]) {
        let fm = FileManager.default
        for path in paths { try? fm.removeItem(atPath: path) }
    }

    // MARK: - Internals

    nonisolated private static func installedBundleIDs() -> Set<String> {
        let fm = FileManager.default
        var ids = Set<String>()
        for dir in appDirs {
            guard let apps = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for app in apps where app.hasSuffix(".app") {
                let plistPath = "\(dir)/\(app)/Contents/Info.plist"
                guard let data = fm.contents(atPath: plistPath),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let id = plist["CFBundleIdentifier"] as? String else { continue }
                ids.insert(id)
            }
        }
        return ids
    }

    nonisolated private static func directorySize(_ path: String, fm: FileManager) -> Int64 {
        var size: Int64 = 0
        if let enumerator = fm.enumerator(atPath: path) {
            for case let file as String in enumerator {
                guard let attrs = try? fm.attributesOfItem(atPath: "\(path)/\(file)"),
                      let fileSize = attrs[.size] as? Int64 else { continue }
                size += fileSize
            }
        }
        return size
    }
}
