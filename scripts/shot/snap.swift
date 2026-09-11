// snap.swift — render an HTML file to a PNG at an exact pixel size.
//
// For hero art and social cards: WebKit does the typesetting, so the result
// uses real fonts and real CSS instead of an approximation drawn by hand.
//
//   swift scripts/shot/snap.swift marketing/hero/hero.html out.png 1600 900 [scale]
//
// scale defaults to 2 (so 1600x900 above writes a 3200x1800 file).
import Cocoa
import WebKit

let args = CommandLine.arguments
guard args.count >= 5 else {
    fputs("usage: snap <file.html> <out.png> <width> <height> [scale]\n", stderr)
    exit(1)
}
let htmlURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
// Bound at top level rather than through `guard let`: a guard binding is local,
// and the WKNavigationDelegate below is a class, which cannot close over a
// local. Globals it can reach.
let parsedW = Double(args[3])
let parsedH = Double(args[4])
if parsedW == nil || parsedH == nil {
    fputs("error: width and height must be numbers\n", stderr)
    exit(1)
}
let w = parsedW!
let h = parsedH!
let scale = args.count > 5 ? (Double(args[5]) ?? 2.0) : 2.0

guard FileManager.default.fileExists(atPath: htmlURL.path) else {
    fputs("error: no such file: \(htmlURL.path)\n", stderr)
    exit(1)
}

let app = NSApplication.shared
// .prohibited keeps this off the Dock and out of the window list, so a capture
// running alongside it never picks up our own borderless window.
app.setActivationPolicy(.prohibited)

let web = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h),
                    configuration: WKWebViewConfiguration())
// Transparent background, so a hero with rounded corners or a drop shadow
// composites onto any page colour instead of carrying a white box with it.
web.setValue(false, forKey: "drawsBackground")
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = web

final class Done: NSObject, WKNavigationDelegate {
    func webView(_ web: WKWebView, didFinish nav: WKNavigation!) {
        // didFinish fires when the document is parsed, not when webfonts have
        // loaded and CSS animations have settled. Snapshotting immediately
        // catches fallback type and half-played transitions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = web.bounds
            // snapshotWidth is in POINTS, and WebKit then multiplies by the
            // display's backing scale to get pixels. Asking for `w * scale`
            // on a Retina Mac therefore yields `w * scale * 2` — a 1600pt
            // hero at scale 2 came out 6400px wide instead of 3200. Divide it
            // back out so `scale` means what it says regardless of which
            // display renders it.
            let bsf = NSScreen.main?.backingScaleFactor ?? 2.0
            cfg.snapshotWidth = NSNumber(value: w * scale / bsf)
            web.takeSnapshot(with: cfg) { image, err in
                guard let image,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    fputs("snapshot failed: \(err?.localizedDescription ?? "unknown")\n", stderr)
                    exit(2)
                }
                do {
                    try png.write(to: outURL)
                } catch {
                    fputs("could not write \(outURL.path): \(error.localizedDescription)\n", stderr)
                    exit(3)
                }
                print("\(outURL.path)  (\(rep.pixelsWide)x\(rep.pixelsHigh))")
                exit(0)
            }
        }
    }

    func webView(_ web: WKWebView, didFail nav: WKNavigation!, withError error: Error) {
        fputs("load failed: \(error.localizedDescription)\n", stderr)
        exit(4)
    }
}

let done = Done()
web.navigationDelegate = done
// Read access reaches two levels up, not one: a hero in marketing/hero/ needs
// to pull the screenshot it frames out of marketing/shots/. Granting only the
// containing folder makes that <img> fail silently — WebKit renders the page
// without it and the snapshot looks merely "empty" rather than broken.
web.loadFileURL(htmlURL,
                allowingReadAccessTo: htmlURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent())
app.run()
