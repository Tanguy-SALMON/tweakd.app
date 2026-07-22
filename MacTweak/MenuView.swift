//
//  MenuView.swift
//  MacTweak
//
//  The menu-bar panel content. Skeleton: title, a button to open the main
//  window, and Quit.
//

import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(.tint)
                Text("MacTweak").font(.headline)
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("Open MacTweak", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 240)
    }
}
