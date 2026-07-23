//
//  Tweak.swift
//  MacTweak
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

    var privilegeRunner: (String) -> CommandResult {
        privilege == .admin ? CommandRunner.admin : CommandRunner.user
    }
}
