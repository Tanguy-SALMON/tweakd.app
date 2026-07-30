//
//  Tweak.swift
//  tweakd
//
//  The data model for a single, reversible system optimization.
//  Everything the engine needs to apply, revert, and probe a tweak lives here,
//  as data — so adding a tweak is a one-entry change in the catalog.
//

import SwiftUI

enum Privilege: Sendable {
    case user   // runs as you
    case admin  // prompts for your password
}

enum Risk: Int, Sendable, Comparable {
    case safe = 0       // reversible, no functional loss
    case moderate = 1   // disables a convenience feature
    case advanced = 2   // can break workflows if you rely on them

    static func < (l: Risk, r: Risk) -> Bool { l.rawValue < r.rawValue }

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .moderate: return "Moderate"
        case .advanced: return "Advanced"
        }
    }
}

/// Where a tweak currently stands on this machine.
enum TweakState: Equatable, Sendable {
    case applied        // optimization active
    case notApplied     // stock behavior
    case unknown        // couldn't determine
    case unavailable    // can't be applied here (e.g. SIP on, or feature absent)

    /// Stable token for the audit log — spelled out rather than derived from the
    /// case name so renaming a case can't silently change the log format.
    var auditName: String {
        switch self {
        case .applied:     return "applied"
        case .notApplied:  return "notApplied"
        case .unknown:     return "unknown"
        case .unavailable: return "unavailable"
        }
    }
}

/// Tags drive the onboarding wizard's recommendations.
enum TweakTag: String, CaseIterable, Sendable {
    case usesAI            // keep on if the user wants Apple Intelligence
    case usesSpotlight     // keep on if the user searches with Spotlight
    case usesPhotos        // keep on if the user relies on Photos memories/faces
    case usesAirDropAirPlay
    case prioritizeBattery
    case prioritizePerformance
    case privacyFocused
    case snappyUI
    case serverWorkload    // throughput/latency tuning for local servers & dev tooling
    case security          // firewall / stealth / network hardening
    case lowLatency        // network-latency tuning (buffers, backlog, priorities)
    /// Only pays off with a fan behind it. On a passively-cooled Mac the ceiling
    /// is thermal budget, not scheduling or I/O brakes — letting *more* work run
    /// concurrently just spends heat the foreground app needed, so the wizard
    /// won't auto-recommend these on a fanless machine. See docs/TWEAKS.md.
    case needsActiveCooling
}

/// The benefit a tweak delivers — shown as a small chip in the UI (and mirrored
/// by the website's gain indicator). Keep in sync with `docs/TWEAKS.md`.
enum Gain: String, Hashable, Sendable {
    case faster, snappier, privacy, battery, frees, throughput, disk, secure, latency

    var label: String {
        switch self {
        case .faster:     return "Faster"
        case .snappier:   return "Snappier UI"
        case .privacy:    return "More private"
        case .battery:    return "Better battery"
        case .frees:      return "Frees resources"
        case .throughput: return "More throughput"
        case .disk:       return "Frees disk"
        case .secure:     return "Hardened"
        case .latency:    return "Lower latency"
        }
    }
    /// SF Symbol paired with the label (the app's native equivalent of the
    /// website's wireframe gain icons).
    var symbol: String {
        switch self {
        case .faster:     return "bolt.fill"
        case .snappier:   return "speedometer"
        case .privacy:    return "lock.shield.fill"
        case .battery:    return "leaf.fill"
        case .frees:      return "wind"
        case .throughput: return "arrow.up.arrow.down"
        case .disk:       return "internaldrive.fill"
        case .secure:     return "checkerboard.shield"
        case .latency:    return "timer"
        }
    }
}

struct Tweak: Identifiable, Sendable {
    let key: String
    let title: String
    let summary: String
    let category: TweakCategory
    let privilege: Privilege
    let risk: Risk
    let sipRequired: Bool

    /// Shell run to activate the optimization.
    let applyCommand: String
    /// Shell run to restore stock behavior.
    let revertCommand: String
    /// Shell whose stdout we inspect to decide current state.
    let statusCommand: String
    /// If `statusCommand` stdout contains this token, the tweak is considered *applied*.
    let appliedWhenOutputContains: String

    /// Tags the wizard uses to decide whether to recommend this tweak.
    let tags: Set<TweakTag>

    /// Recommended as part of the default "one-click tune" set.
    let recommended: Bool

    var id: String { key }

    /// Per-tweak SF Symbol, falling back to the category glyph.
    var icon: String { TweakCatalog.iconOverrides[key] ?? category.icon }

    /// What this tweak improves (usually one, sometimes two). Drives the gain chips.
    var gains: [Gain] { TweakCatalog.gainsByKey[key] ?? [] }

    var privilegeRunner: (String) -> CommandResult {
        privilege == .admin ? CommandRunner.admin : CommandRunner.user
    }
}
