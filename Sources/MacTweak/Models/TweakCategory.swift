//
//  TweakCategory.swift
//  MacTweak
//

import SwiftUI

enum TweakCategory: String, CaseIterable, Identifiable, Sendable {
    case performance = "Performance"
    case power = "Power"
    case snappiness = "Snappiness"
    case privacy = "Privacy"
    case services = "Background Services"
    case network = "Network"
    case ai = "AI & Intelligence"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .performance: return "gauge.with.dots.needle.67percent"
        case .power: return "bolt.fill"
        case .snappiness: return "hare.fill"
        case .privacy: return "hand.raised.fill"
        case .services: return "gearshape.2.fill"
        case .network: return "network"
        case .ai: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .performance: return .blue
        case .power: return .yellow
        case .snappiness: return .teal
        case .privacy: return .indigo
        case .services: return .purple
        case .network: return .green
        case .ai: return .pink
        }
    }

    var blurb: String {
        switch self {
        case .performance: return "Raw throughput and latency."
        case .power: return "Trade battery for sustained speed."
        case .snappiness: return "Cut animation and input delays."
        case .privacy: return "Reduce telemetry and analytics."
        case .services: return "Silence heavy background daemons."
        case .network: return "Trim chatty discovery traffic."
        case .ai: return "Turn off on-device intelligence work."
        }
    }
}
