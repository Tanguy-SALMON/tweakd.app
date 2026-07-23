//
//  ProcessPriorityView.swift
//  MacTweak
//
//  The "Process Priority" pane: a live table of known network/UI processes with
//  a nice-value slider per row, an "Apply at login" toggle, and an emergency
//  "Reset all to default" button.
//
//  NOTE: skeleton — the full implementation is filled in by the Process-Priority
//  worktree agent. Keep the type name and the `PriorityManager` dependency stable.
//

import SwiftUI

struct ProcessPriorityView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                HeroHeader(icon: "cpu", title: "Process Priority",
                           blurb: "Give network and UI processes more CPU under load — or make background daemons yield.")
            }
            .padding(Space.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await model.priority.refresh() }
    }
}
