//
//  TweakdApp.swift
//  tweakd
//
//  Menu-bar app with a full main window. Also shows a Dock icon (LSUIElement
//  is false in the bundle's Info.plist), so it appears in both places.
//

import SwiftUI
import AppKit

@main
struct TweakdApp: App {
    @StateObject private var model = AppModel()

    /// 80% of the active screen's *visible* frame — which excludes the menu bar
    /// and Dock, so the window never opens partly underneath either. Clamped to
    /// the window's minimum content size, since 80% of a small display can land
    /// below it.
    static var launchSize: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width:  max(minWidth,  visible.width  * 0.8),
                      height: max(minHeight, visible.height * 0.8))
    }

    static let minWidth: CGFloat = 880
    static let minHeight: CGFloat = 620

    init() {
        // Before anything reads a preference or writes a log line: adopt the
        // state the app left behind under its old name.
        LegacyMigration.runIfNeeded()
        Log.installCrashHandlers()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
                .focusEffectDisabled()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window(Brand.name, id: "main") {
            MainWindowView()
                .environmentObject(model)
                .frame(minWidth: Self.minWidth, minHeight: Self.minHeight)
                .focusEffectDisabled()   // the blue focus ring doesn't fit the design
                .background(LaunchFrameSetter())
                .task { model.boot() }
        }
        .windowResizability(.contentSize)
        .defaultSize(Self.launchSize)
        .defaultPosition(.center)
    }
}

/// The menu-bar icon. Also reliably opens the main window once at launch —
/// `Window` scenes don't auto-present for an accessory (menu-bar) app, and
/// `.defaultLaunchBehavior(.presented)` crashes under LaunchServices here.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var openedAtLaunch = false

    var body: some View {
        Image(systemName: "slider.horizontal.3")
            .task {
                guard !openedAtLaunch else { return }
                openedAtLaunch = true
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
    }
}

/// Sizes the main window to 80% of the screen, centred, once per launch.
///
/// `.defaultSize` can't do this on its own: it only applies when AppKit has no
/// saved frame to restore, so on any install that has run before, the window
/// comes back at whatever size it was last left at.
///
/// This lives in the window's own view hierarchy rather than firing off a timer
/// after `openWindow`, because `openWindow` returns before the window exists —
/// reaching for it a tick later finds nothing and silently does nothing.
private struct LaunchFrameSetter: NSViewRepresentable {
    /// The window is sized once per launch, so a resize the user makes
    /// afterwards isn't undone the next time SwiftUI re-renders this view.
    private static var applied = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(view.window) }
    }

    private func apply(_ window: NSWindow?) {
        guard !Self.applied,
              let window,
              let screen = window.screen ?? NSScreen.main else { return }
        Self.applied = true

        let size = TweakdApp.launchSize
        let visible = screen.visibleFrame
        window.setFrame(
            NSRect(x: visible.midX - size.width / 2,
                   y: visible.midY - size.height / 2,
                   width: size.width, height: size.height),
            display: true
        )
    }
}
