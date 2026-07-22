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

// Brand gradient, diagonal.
let grad = NSGradient(colors: [
    NSColor(red: 0.36, green: 0.44, blue: 1.00, alpha: 1),
    NSColor(red: 0.62, green: 0.35, blue: 0.98, alpha: 1),
    NSColor(red: 0.95, green: 0.42, blue: 0.72, alpha: 1),
])!
grad.draw(in: full, angle: -45)

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
