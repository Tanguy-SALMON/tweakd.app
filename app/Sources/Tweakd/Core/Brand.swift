//
//  Brand.swift
//  tweakd
//
//  Every name, path and identifier the app writes, in one place — plus the
//  **legacy** values it used when it was called MacTweak.
//
//  The rename isn't cosmetic: this app leaves real artifacts on the system
//  (a sudoers rule, LaunchAgents, marked blocks inside /etc/hosts and Firefox's
//  user.js). Change an identifier without keeping the old one, and the artifact
//  it names becomes an orphan the app can no longer see or remove — the
//  /etc/sudoers.d rule being the serious case, since that one grants
//  passwordless root and the UI would report admin as locked while it stays.
//
//  So: **write the new name, recognise both.** Detection and removal accept the
//  legacy value everywhere it might still exist on disk.
//

import Foundation

enum Brand {
    /// User-visible name. Lowercase on purpose — it matches the domain.
    static let name = "tweakd"
    static let domain = "tweakd.app"
    /// Reverse-DNS of the domain. Bundle ID, log subsystem, LaunchAgent prefix.
    static let bundleID = "app.tweakd"

    static let legacyName = "MacTweak"
    static let legacyBundleID = "com.tanguy.MacTweak"
    static let legacyAgentPrefix = "com.mactweak"

    // MARK: Paths we own

    static var supportDir: String { "\(NSHomeDirectory())/Library/Application Support/\(name)" }
    static var legacySupportDir: String { "\(NSHomeDirectory())/Library/Application Support/\(legacyName)" }

    static var logDir: String { "\(NSHomeDirectory())/Library/Logs/\(name)" }
    static var legacyLogDir: String { "\(NSHomeDirectory())/Library/Logs/\(legacyName)" }

    static var launchAgentDir: String { "\(NSHomeDirectory())/Library/LaunchAgents" }

    static var revertScript: String { "\(NSHomeDirectory())/Documents/\(name)_Revert.sh" }

    /// Root-owned sudoers drop-in. `sudoersPath` is what we write; `allSudoersPaths`
    /// is what we look for and remove, so a rule left by the old name is still
    /// discoverable and revocable from the UI.
    static let sudoersPath = "/etc/sudoers.d/tweakd"
    static let legacySudoersPath = "/etc/sudoers.d/mactweak"
    static var allSudoersPaths: [String] { [sudoersPath, legacySudoersPath] }

    // MARK: Markers we write into other people's files

    /// `/etc/hosts` ad-block block delimiters.
    static let hostsMarkerStart = "# tweakd-adblock-start"
    static let hostsMarkerEnd = "# tweakd-adblock-end"
    static let legacyHostsMarkerStart = "# MacTweak-adblock-start"
    static let legacyHostsMarkerEnd = "# MacTweak-adblock-end"

    /// First-line marker in the Firefox `user.js` we write, so revert only ever
    /// deletes a file this app created.
    static let firefoxMarker = "tweakd privacy"
    static let legacyFirefoxMarker = "MacTweak privacy"

    // MARK: LaunchAgent labels

    static var adblockLabel: String { "\(bundleID).adblock" }
    static var legacyAdblockLabel: String { "\(legacyAgentPrefix).adblock" }

    static func priorityLabel(_ id: String) -> String { "\(bundleID).priority.\(id)" }
    /// Both prefixes, for scanning `~/Library/LaunchAgents`.
    static var priorityPrefixes: [String] { ["\(bundleID).priority.", "\(legacyAgentPrefix).priority."] }

    /// True for any label this app has ever installed — used to group its own
    /// agents on the Services page under either name.
    static func isOwnAgent(_ label: String) -> Bool {
        label.hasPrefix(bundleID) || label.hasPrefix(legacyAgentPrefix)
    }
}
