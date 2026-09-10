//
//  BetaWarningDialog.swift
//  tweakd
//
//  Confirmation shown before turning ON a tweak flagged `isBeta` — these are
//  unverified/experimental and haven't been validated across the Mac fleet
//  the way the rest of the catalog has. Turning one off never shows this.
//

import SwiftUI

/// Reusable "enable this beta tweak?" alert. Attach with `.betaWarningDialog(...)`
/// from any view that owns a toggle bound to `TweakEngine.set(tweak:to:)`, so the
/// same copy and behavior are shared by the main window and the menu-bar popover.
struct BetaWarningDialog: ViewModifier {
    @Binding var isPresented: Bool
    let tweakTitle: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert("Enable “\(tweakTitle)”?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Enable Beta Tweak", role: .destructive) { onConfirm() }
        } message: {
            Text("This tweak is experimental and hasn't been fully verified. It may not work correctly — or at all — on this Mac. Enable it only if you're comfortable troubleshooting it yourself.")
        }
    }
}

extension View {
    /// Shows a beta-tweak warning alert bound to `isPresented`, calling `onConfirm`
    /// only when the user explicitly confirms enabling it.
    func betaWarningDialog(isPresented: Binding<Bool>, tweakTitle: String, onConfirm: @escaping () -> Void) -> some View {
        modifier(BetaWarningDialog(isPresented: isPresented, tweakTitle: tweakTitle, onConfirm: onConfirm))
    }
}
