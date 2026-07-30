//
//  TweakdApp.swift
//  tweakd
//
//  Menu-bar app with a full main window. LSUIElement is set in the bundle's
//  Info.plist so there's no Dock icon — the whole thing lives in the menu bar.
//

import SwiftUI

@main
struct TweakdApp: App {
    @StateObject private var model = AppModel()

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
                .frame(minWidth: 880, minHeight: 620)
                .focusEffectDisabled()   // the blue focus ring doesn't fit the design
                .task { model.boot() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 680)
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
