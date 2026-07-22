//
//  MainWindowView.swift
//  MacTweak
//
//  The main window. Skeleton placeholder — real controls go here later.
//

import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("MacTweak")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))

            Text("Skeleton window — ready for controls.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 320)
    }
}
