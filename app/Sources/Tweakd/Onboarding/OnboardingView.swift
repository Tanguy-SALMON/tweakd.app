//
//  OnboardingView.swift
//  tweakd
//
//  A short guided setup that tailors the recommended tweaks to how the user
//  actually uses their Mac.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = 0
    private let lastStep = 3

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                content
                    .frame(maxHeight: .infinity)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .animation(.spring(duration: 0.4), value: step)
                controls
            }
            .padding(Space.l)
        }
        .tint(Theme.accent)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: usage
        case 2: priority
        default: review
        }
    }

    private var welcome: some View {
        VStack(spacing: Space.m) {
            Spacer()
            RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 89, height: 89)
                .overlay(Image(systemName: "wand.and.stars")
                    .font(.system(size: 38, weight: .semibold)).foregroundStyle(.white))
                .shadow(color: Theme.accent.opacity(0.25), radius: 18, y: 8)
            Text("Let's tune your Mac")
                .font(.system(size: 30, weight: .bold))
            Text("Answer a few quick questions and \(Brand.displayName) will build a setup\ntailored to how you work — nothing you rely on gets disabled.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            stepTitle("What should we turn off?", "Every switch you turn on applies a change. Anything left off stays exactly as it is.")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s) {
                    // These four bind to "do you *use* this feature?" flags, so the
                    // switch is inverted: turning it on means "I don't use it, go
                    // ahead and disable it". Every other row on this screen already
                    // reads as on = apply, and one screen must not carry two opposite
                    // meanings for the same control.
                    questionToggle("Disable Apple Intelligence & Siri", "Turns off on-device AI, Siri and Lookup suggestions",
                                   "sparkles", $model.wizard.usesAI.not)
                    questionToggle("Disable Spotlight indexing", "Stops ⌘Space from searching file contents",
                                   "magnifyingglass", $model.wizard.usesSpotlight.not)
                    questionToggle("Disable Photos analysis", "Turns off face recognition and auto Memories",
                                   "photo.stack", $model.wizard.usesPhotos.not)
                    questionToggle("Disable AirDrop & AirPlay", "Stops nearby sharing and screen mirroring",
                                   "airplayvideo", $model.wizard.usesAirDrop.not)
                    Divider().overlay(Theme.hairline).padding(.vertical, 2)
                    questionToggle("Prioritize privacy", "Also disable telemetry and suggestions",
                                   "hand.raised", $model.wizard.privacyFocused)
                    questionToggle("Snappy interface", "Cut animation and input delays",
                                   "hare", $model.wizard.wantsSnappyUI)
                    Divider().overlay(Theme.hairline).padding(.vertical, 2)
                    questionToggle("Run network services", "Web servers, SSH, or containers",
                                   "server.rack", $model.wizard.runsNetworkServices)
                    questionSecurityPosture()
                    questionToggle("Need low latency", "Gaming or remote desktop",
                                   "gauge.with.dots.needle.67percent", $model.wizard.needsLowLatency)
                }
                .padding(.bottom, Space.xs)
            }
        }
    }

    private var priority: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            stepTitle("What matters most?", "This biases the borderline tweaks.")
            HStack(spacing: Space.s) {
                ForEach(Priority.allCases) { p in
                    let selected = model.wizard.priority == p
                    Button {
                        model.wizard.priority = p
                    } label: {
                        VStack(spacing: Space.s) {
                            Image(systemName: p.icon).font(.system(size: 28, weight: .medium))
                            Text(p.rawValue).font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.l)
                        .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface),
                                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(selected ? .clear : Theme.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    private var review: some View {
        let keys = model.wizard.recommendedKeys()
        let picked = model.engine.tweaks.filter { keys.contains($0.key) }
        return VStack(alignment: .leading, spacing: Space.s) {
            stepTitle("Your tailored setup", "\(picked.count) tweaks selected. You can change any of these later.")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(picked) { t in
                        HStack(spacing: Space.s) {
                            Image(systemName: t.icon).foregroundStyle(.secondary).frame(width: 22)
                            Text(t.title).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Pill(text: t.risk.label)
                        }
                        .padding(.vertical, Space.xs).padding(.horizontal, Space.s)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile))
                        .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Theme.hairline))
                    }
                    if picked.isEmpty {
                        Text("No changes — you're keeping everything as-is. 👍")
                            .font(.system(size: 13)).foregroundStyle(.secondary).padding()
                    }
                }
            }
            .frame(maxHeight: 267)   // 89 · 3
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack {
            Button("Skip") { Task { await model.finishOnboarding(apply: false) } }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: Space.xs) {
                ForEach(0...lastStep, id: \.self) { i in
                    Circle().fill(i == step ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(.gradientOutline).controlSize(.large)
            }
            if step < lastStep {
                Button("Next") { step += 1 }
                    .buttonStyle(.gradient).controlSize(.large)
            } else {
                Button("Apply Setup") { Task { await model.finishOnboarding(apply: true) } }
                    .buttonStyle(.gradient).controlSize(.large)
            }
        }
        .padding(.top, Space.s)
    }

    // MARK: Bits

    private func stepTitle(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold))
            Text(sub).font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    private func questionToggle(_ title: String, _ sub: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: Space.s) {
                Image(systemName: icon).font(.system(size: 16)).frame(width: 26).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(Space.s)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Theme.hairline))
    }

    private func questionSecurityPosture() -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "lock.shield").font(.system(size: 16)).frame(width: 26).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Security posture").font(.system(size: 13, weight: .semibold))
                    Text("Firewall, stealth mode, and privacy DNS").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Picker("Security posture", selection: $model.wizard.securityPosture) {
                ForEach(SecurityPosture.allCases) { posture in
                    Text(posture.label).tag(posture)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .padding(Space.s)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Theme.hairline))
    }
}

extension Binding where Value == Bool {
    /// Reads and writes the inverse. Lets a "do you use this?" flag drive a
    /// switch phrased as "disable this", so every toggle on a step can mean the
    /// same thing — on applies a change — without reshaping the wizard model.
    var not: Binding<Bool> {
        Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
    }
}
