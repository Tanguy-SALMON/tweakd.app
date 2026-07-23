//
//  make_icon.swift
//  Renders the MacTweak app icon (a rounded square with a brand gradient and
//  the slider glyph) to a 1024×1024 PNG. Run:  swift Scripts/make_icon.swift <out.png>
//

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"
let S = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let full = NSRect(x: 0, y: 0, width: S, height: S)
NSColor.clear.set()
full.fill()

// Rounded-square mask (macOS-ish continuous corner).
let radius = CGFloat(S) * 0.2237
let squircle = NSBezierPath(roundedRect: full, xRadius: radius, yRadius: radius)
squircle.addClip()

// Brand gradient — the app-wide orange→red, vertical top→bottom.
// Matches Theme.accent (#F54900, oklch 64.6% .222 41.116) → Theme.accentDeep
// (#E7000E, oklch 57.7% .245 27.325), i.e. the exact gradient used on the website.
let grad = NSGradient(colors: [
    NSColor(red: 0.9608, green: 0.2863, blue: 0.0000, alpha: 1),  // #F54900 (top)
    NSColor(red: 0.9059, green: 0.0000, blue: 0.0549, alpha: 1),  // #E7000E (bottom)
])!
grad.draw(in: full, angle: -90)   // -90° = top → bottom

// Soft top highlight for a glossy, premium feel.
let gloss = NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)])!
gloss.draw(in: NSRect(x: 0, y: CGFloat(S) * 0.52, width: CGFloat(S), height: CGFloat(S) * 0.48), angle: -90)

// Glyph: slider.horizontal.3, tinted white, centered.
let cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(S) * 0.46, weight: .semibold)
if let base = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let g = NSImage(size: base.size)
    g.lockFocus()
    base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    g.unlockFocus()

    let gs = g.size
    let origin = NSPoint(x: (CGFloat(S) - gs.width) / 2, y: (CGFloat(S) - gs.height) / 2)
    g.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 0.96)
}

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
