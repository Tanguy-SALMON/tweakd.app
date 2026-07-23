//
//  Theme.swift
//  MacTweak
//
//  Apple-like design system. Neutral greys from apple.com, a single accent,
//  monochrome iconography, and a Fibonacci spacing scale (8·13·21·34·55·89)
//  that approximates the golden ratio for harmonious rhythm.
//

import SwiftUI
import AppKit

// MARK: - Adaptive colour helper

extension Color {
    static func dynamic(_ light: Color, _ dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Tokens

/// Fibonacci spacing — the ratio between neighbours tends to φ (≈1.618).
enum Space {
    static let xxs: CGFloat = 5
    static let xs:  CGFloat = 8
    static let s:   CGFloat = 13
    static let m:   CGFloat = 21
    static let l:   CGFloat = 34
    static let xl:  CGFloat = 55
    static let xxl: CGFloat = 89
}

enum Radius {
    static let control: CGFloat = 8
    static let tile:    CGFloat = 10
    static let card:    CGFloat = 13
    static let sheet:   CGFloat = 21
}

enum Theme {
    /// The single accent. Apple's website blue, adapted for dark mode.
    static let accent = Color.dynamic(Color(hex: 0x0071E3), Color(hex: 0x2997FF))

    /// Page background — the exact apple.com grey.
    static let canvas = Color.dynamic(Color(hex: 0xF5F5F7), Color(hex: 0x1D1D1F))

    /// Elevated surfaces (cards) sit on the canvas.
    static let surface = Color.dynamic(.white, Color(hex: 0x2C2C2E))

    /// Hairline separators / borders.
    static let hairline = Color.dynamic(.black.opacity(0.08), .white.opacity(0.10))

    /// Neutral icon tint (everything that isn't the accent).
    static let icon = Color.secondary
}

// MARK: - Surfaces

/// A flat, elevated card. Apple-style: white on grey, hairline border, whisper shadow.
struct Card: ViewModifier {
    var padding: CGFloat = Space.m
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
                    .allowsHitTesting(false)   // decorative — never intercept row taps
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = Space.m) -> some View { modifier(Card(padding: padding)) }

    /// A restrained section heading — SF Pro, tight, secondary.
    func sectionTitle() -> some View {
        self.font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }
}

// MARK: - Pill (monochrome by default, accent when prominent)

struct Pill: View {
    let text: String
    var prominent: Bool = false          // filled accent (e.g. "Applied")
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Space.xxs) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, Space.xs).padding(.vertical, 3)
        .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        .background(
            prominent ? AnyShapeStyle(Theme.accent)
                      : AnyShapeStyle(Color.secondary.opacity(0.12)),
            in: Capsule()
        )
    }
}

/// A neutral square that holds a monochrome glyph (sidebar/list/menu icons).
struct GlyphTile: View {
    let systemName: String
    var size: CGFloat = 34
    var active: Bool = false
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            .fill(active ? AnyShapeStyle(Theme.accent.opacity(0.14)) : AnyShapeStyle(Color.secondary.opacity(0.10)))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            )
    }
}
