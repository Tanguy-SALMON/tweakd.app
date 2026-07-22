//
//  MacTweakApp.swift
//  MacTweak
//
//  Menu-bar app with a full main window. LSUIElement is set in the bundle's
//  Info.plist so there's no Dock icon — the whole thing lives in the menu bar.
//

import SwiftUI

@main
struct MacTweakApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuBarExtraStyle(.window)

        Window("MacTweak", id: "main") {
            MainWindowView()
                .environmentObject(model)
                .frame(minWidth: 880, minHeight: 620)
                .task { model.boot() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 680)
        .defaultPosition(.center)
    }
}
