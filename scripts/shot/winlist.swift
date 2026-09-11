// winlist.swift — list an app's on-screen windows, with their IDs and sizes.
//
// `screencapture -l<id>` needs a window ID, and there is no way to ask for
// "Tweakd's main window" directly. This prints the candidates so capture.sh
// can pick one.
//
//   swift scripts/shot/winlist.swift            # defaults to Tweakd
//   swift scripts/shot/winlist.swift Finder
//
// Layer 0 is a normal window. The menu-bar popover sits on a higher layer,
// which is how capture.sh tells the two apart.
import CoreGraphics
import Foundation

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tweakd"

guard let list = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] else {
    fputs("error: could not read the window list\n", stderr)
    exit(1)
}

var found = 0
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.lowercased().contains(target.lowercased()) else { continue }
    found += 1
    let id = w[kCGWindowNumber as String] as? Int ?? 0
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let name = w[kCGWindowName as String] as? String ?? "-"
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = b["Width"] as? Double ?? 0
    let height = b["Height"] as? Double ?? 0
    print("id=\(id) layer=\(layer) size=\(Int(width))x\(Int(height)) owner=\(owner) name=\(name)")
}

if found == 0 {
    fputs("no on-screen windows owned by '\(target)' — is it running and unminimised?\n", stderr)
    exit(1)
}
