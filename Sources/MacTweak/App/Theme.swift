//
//  Theme.swift
//  MacTweak
//
//  Small design system: gradients, card surfaces, and reusable modifiers that
//  give the app a consistent, premium feel in light and dark.
//

import SwiftUI

enum Theme {
    static let corner: CGFloat = 16
    static let cardCorner: CGFloat = 14

    static let brand = LinearGradient(
        colors: [Color(red: 0.36, green: 0.44, blue: 1.0),
                 Color(red: 0.62, green: 0.35, blue: 0.98),
                 Color(red: 0.95, green: 0.42, blue: 0.72)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func heroBackground(_ scheme: ColorScheme) -> some View {
        ZStack {
            (scheme == .dark ? Color(white: 0.07) : Color(white: 0.96))
            RadialGradient(colors: [Color(red: 0.36, green: 0.44, blue: 1.0).opacity(0.18), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(red: 0.95, green: 0.42, blue: 0.72).opacity(0.14), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

/// A frosted card surface used throughout the detail panes.
struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }

    func sectionTitle() -> some View {
        self.font(.system(.title3, design: .rounded).weight(.semibold))
    }
}

/// A pill badge, used for state and risk.
struct Pill: View {
    let text: String
    let color: Color
    var filled: Bool = false
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(filled ? .white : color)
        .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.15)),
                    in: Capsule())
    }
}
