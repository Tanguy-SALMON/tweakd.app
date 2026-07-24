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
    /// The single accent — oklch(64.6% 0.222 41.116), a vibrant orange (#F54900 in sRGB).
    static let accent = Color(hex: 0xF54900)

    /// Deep end of the juicy gradient — oklch(57.7% 0.245 27.325), vibrant red (#E7000E).
    static let accentDeep = Color(hex: 0xE7000E)

    /// The juicy MyD1 gradient: a 135° wash of bright-orange → vibrant orange →
    /// vibrant red (mirrors the .acct-avatar avatar gradient). Used on hero tiles,
    /// the ring gauge, and gradient cards.
    static let accentGradient = LinearGradient(
        stops: [
            .init(color: accent,     location: 0.0),   // darker, vibrant orange up top
            .init(color: accentDeep, location: 1.0),   // vibrant red at the bottom
        ],
        startPoint: .top, endPoint: .bottom
    )

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

    /// Pointing-hand cursor on hover — SwiftUI's `Button` keeps the plain arrow
    /// on macOS (only `Link` switches automatically), so every custom clickable
    /// row/button needs this to read as clickable.
    func clickCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

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

/// A square that holds a glyph. Every tile fills with the juicy orange→red
/// gradient and a white glyph — the brand accent leads *every* icon in the app.
/// `active`/`prominent` are accepted for call-site compatibility but no longer
/// change the look (the "everything gradient" design is deliberate and uniform).
struct GlyphTile: View {
    let systemName: String
    var size: CGFloat = 34
    var active: Bool = false
    var prominent: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            .fill(Theme.accentGradient)
            .overlay {
                // Radial white glint (top-left) — the sheen that makes the
                // orange→red gradient read as "juicy", straight from MyD1.
                RadialGradient(colors: [.white.opacity(0.5), .clear],
                               center: UnitPoint(x: 0.24, y: 0.22),
                               startRadius: 0, endRadius: size * 0.9)
                    .allowsHitTesting(false)
            }
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            )
    }
}

// MARK: - Gradient button style (the juicy accent on every action)

/// The app-wide button look: the same plain orange→red gradient fill used to
/// mark the selected sidebar row, on a capsule with a white label. `filled: false`
/// gives the secondary variant — a gradient-tinted outline for less-prominent
/// actions (Back, Lock, Cancel).
struct GradientButtonStyle: ButtonStyle {
    var filled: Bool = true
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    private var scale: CGFloat {
        switch controlSize {
        case .large: return 1.15
        case .small, .mini: return 0.82
        default: return 1
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .font(.system(size: 13 * scale, weight: .semibold))
            .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.accentGradient))
            .padding(.horizontal, 16 * scale)
            .padding(.vertical, 7 * scale)
            .background {
                if filled {
                    shape.fill(Theme.accentGradient)
                } else {
                    shape.fill(Theme.accent.opacity(0.10))
                        .overlay(shape.strokeBorder(Theme.accentGradient, lineWidth: 1.5))
                }
            }
            .clipShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { inside in
                guard isEnabled else { return }
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    /// Filled orange→red gradient — primary actions.
    static var gradient: GradientButtonStyle { .init(filled: true) }
    /// Gradient-tinted outline — secondary actions.
    static var gradientOutline: GradientButtonStyle { .init(filled: false) }
}
