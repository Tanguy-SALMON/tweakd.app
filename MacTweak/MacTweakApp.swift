//
//  MacTweakApp.swift
//  MacTweak
//
//  Menu-bar-only app (LSUIElement). No dock icon → a lightweight, premium feel.
//  Skeleton: a menu-bar icon, a panel, and a main window. Fill in later.
//

import SwiftUI

@main
struct MacTweakApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuBarExtraStyle(.window)

        Window("MacTweak", id: "main") {
            MainWindowView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
