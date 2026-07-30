//
//  make_icon.swift
//  Renders the tweakd app icon (a rounded square with a brand gradient and
//  the slider glyph) to a 1024×1024 PNG. Run:  swift Scripts/make_icon.swift <out.png>
//
//  Rendering model: a soft directional light from the top, a multi-stop
//  orange→red gradient, a feathered radial highlight, an edge vignette,
//  a 2px inner rim light along the top of the squircle, a soft inner shadow
//  at the bottom, and a white glyph with a whisper of drop shadow so it
//  reads as embossed rather than pasted.
//

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"
let S = 1024
let sz = CGFloat(S)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let full = NSRect(x: 0, y: 0, width: sz, height: sz)
NSColor.clear.set()
full.fill()

// Rounded-square mask (macOS-ish continuous corner).
let radius = sz * 0.2237
let squircle = NSBezierPath(roundedRect: full, xRadius: radius, yRadius: radius)
squircle.addClip()

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// ── 1. Base: silky multi-stop vertical gradient, warm orange up top deepening
//    to vibrant red at the bottom. Stays saturated through the midtones.
//    Brand anchors: #F54900 (Theme.accent) → #E7000E (Theme.accentDeep).
let baseGradTopLit = NSGradient(colorsAndLocations:
    (c(196,   0,  22), 0.00),   // shadowed vibrant red (bottom)
    (c(216,   0,  16), 0.12),   // deep vibrant red
    (c(231,   8,  14), 0.32),   // ~#E7000E brand deep red
    (c(240,  44,   6), 0.55),   // vivid orange-red midtone
    (c(247,  76,   2), 0.78),   // ~brand accent #F54900
    (c(255, 108,  16), 1.00)    // sunlit warm orange (top)
)!
baseGradTopLit.draw(in: full, angle: 90)   // 90° = bottom → top (location 0 at bottom)

// ── 2. Soft radial key light near the top — a feathered warm glow, barely there.
ctx.saveGState()
if let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 1, green: 0.80, blue: 0.50, alpha: 0.26).cgColor,
        NSColor(calibratedRed: 1, green: 0.66, blue: 0.34, alpha: 0.10).cgColor,
        NSColor(calibratedRed: 1, green: 0.6,  blue: 0.3,  alpha: 0).cgColor,
    ] as CFArray,
    locations: [0, 0.42, 1]
) {
    let center = CGPoint(x: sz * 0.42, y: sz * 1.04)  // above the top edge, biased left
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: sz * 0.85, options: [])
}
ctx.restoreGState()

// ── 3. Edge vignette — soft darkening toward the bottom corners for roundness.
ctx.saveGState()
if let vig = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.45, green: 0, blue: 0.06, alpha: 0).cgColor,
        NSColor(calibratedRed: 0.45, green: 0, blue: 0.06, alpha: 0).cgColor,
        NSColor(calibratedRed: 0.42, green: 0, blue: 0.06, alpha: 0.22).cgColor,
    ] as CFArray,
    locations: [0, 0.62, 1]
) {
    let center = CGPoint(x: sz * 0.5, y: sz * 0.62)
    ctx.drawRadialGradient(vig, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: sz * 0.78,
                           options: [.drawsAfterEndLocation])
}
ctx.restoreGState()

// ── 4. Bottom inner shadow — a soft linear darken hugging the bottom edge.
let bottomShade = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.50, green: 0, blue: 0.06, alpha: 0.24), 0.0),
    (NSColor(calibratedRed: 0.50, green: 0, blue: 0.06, alpha: 0.0),  1.0)
)!
bottomShade.draw(in: NSRect(x: 0, y: 0, width: sz, height: sz * 0.14), angle: 90)

// ── 5. Inner rim light — a ~2px bright line along the top edge of the squircle,
//    fading down the sides. Drawn by stroking the inset squircle clipped to the
//    top region, masked by a vertical alpha ramp.
ctx.saveGState()
// Alpha-ramp mask via transparency layer: stroke with a gradient by clipping to
// the stroke path.
let rimInset: CGFloat = 1.5
let rimRect = full.insetBy(dx: rimInset, dy: rimInset)
let rimPath = NSBezierPath(roundedRect: rimRect, xRadius: radius - rimInset, yRadius: radius - rimInset)
rimPath.lineWidth = 3.0
// Clip to the stroke of the rim path:
let cgRim = CGPath(roundedRect: rimRect, cornerWidth: radius - rimInset, cornerHeight: radius - rimInset, transform: nil)
ctx.addPath(cgRim.copy(strokingWithWidth: 3.0, lineCap: .round, lineJoin: .round, miterLimit: 10))
ctx.clip()
// Vertical gradient: bright white at very top, gone by ~65% down.
if let rim = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(white: 1, alpha: 0.70).cgColor,
        NSColor(white: 1, alpha: 0.14).cgColor,
        NSColor(white: 1, alpha: 0).cgColor,
    ] as CFArray,
    locations: [0, 0.20, 0.50]
) {
    ctx.drawLinearGradient(rim, start: CGPoint(x: 0, y: sz), end: CGPoint(x: 0, y: 0), options: [])
}
ctx.restoreGState()

// ── 6. Glyph: slider.horizontal.3, white, centered, with a soft drop shadow
//    so it feels raised off the surface.
let cfg = NSImage.SymbolConfiguration(pointSize: sz * 0.46, weight: .semibold)
if let base = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    // Tint pure white.
    let g = NSImage(size: base.size)
    g.lockFocus()
    base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    g.unlockFocus()

    let gs = g.size
    let origin = NSPoint(x: (sz - gs.width) / 2, y: (sz - gs.height) / 2)

    // Soft drop shadow: low opacity, small blur, slight downward offset.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -sz * 0.008),
                  blur: sz * 0.018,
                  color: NSColor(calibratedRed: 0.4, green: 0, blue: 0.02, alpha: 0.35).cgColor)
    g.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    ctx.restoreGState()
}

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
