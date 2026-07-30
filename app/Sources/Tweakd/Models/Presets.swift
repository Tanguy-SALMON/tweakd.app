//
//  Presets.swift
//  tweakd
//
//  One-tap bundles of tweaks. Presets only ever include real, available tweaks:
//  SIP-blocked and advanced-risk tweaks are excluded so a preset never fails or
//  surprises the user.
//

import Foundation

struct Preset: Identifiable {
    let id: String
    let name: String
    let icon: String
    let blurb: String
    let matches: (Tweak) -> Bool

    /// Resolve to concrete tweak keys, skipping anything unavailable or advanced.
    func keys() -> Set<String> {
        Set(TweakCatalog.all
            .filter { !($0.sipRequired && SystemInfo.sipEnabled) && $0.risk != .advanced && matches($0) }
            .map(\.key))
    }
}

enum Presets {
    static let all: [Preset] = [
        Preset(id: "balanced", name: "Balanced", icon: "circle.lefthalf.filled",
               blurb: "The safe recommended set.",
               matches: { $0.recommended }),
        Preset(id: "performance", name: "Performance", icon: "flame.fill",
               blurb: "Throughput and snappiness.",
               matches: { $0.risk <= .moderate && ($0.tags.contains(.prioritizePerformance) || $0.tags.contains(.snappyUI)) }),
        Preset(id: "snappy", name: "Snappy UI", icon: "hare.fill",
               blurb: "Kill animations and delays.",
               matches: { $0.risk <= .moderate && $0.tags.contains(.snappyUI) }),
        Preset(id: "battery", name: "Battery", icon: "leaf.fill",
               blurb: "Trim background wake-ups.",
               matches: { $0.risk <= .moderate && $0.tags.contains(.prioritizeBattery) }),
        Preset(id: "privacy", name: "Privacy", icon: "hand.raised.fill",
               blurb: "Reduce telemetry & suggestions.",
               matches: { $0.risk <= .moderate && $0.tags.contains(.privacyFocused) }),
        Preset(id: "server", name: "AI / Server", icon: "server.rack",
               blurb: "Throughput for local LLM & dev servers.",
               matches: { $0.risk <= .moderate && $0.tags.contains(.serverWorkload) }),
        Preset(id: "hardened", name: "Hardened Security", icon: "lock.shield.fill",
               blurb: "Firewall, stealth & privacy DNS.",
               matches: { $0.risk <= .moderate && $0.tags.contains(.security) }),
        Preset(id: "lowlatency", name: "Low-Latency Net", icon: "bolt.horizontal.fill",
               blurb: "Tune the network stack for latency.",
               matches: { $0.risk <= .moderate && $0.tags.contains(.lowLatency) }),
    ]
}
