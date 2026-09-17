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
    @State private var pulse = false
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
            // Blurred rather than hidden: the setup you just reviewed stays
            // recognisable behind the progress, so it reads as "this is being
            // applied" instead of a new screen.
            .blur(radius: model.engine.batchProgress == nil ? 0 : 6)
            .allowsHitTesting(model.engine.batchProgress == nil)

            applyingOverlay
        }
        .animation(.easeInOut(duration: 0.22), value: model.engine.batchProgress == nil)
        .tint(Theme.accent)
    }

    // MARK: Applying

    /// Shown while the wizard's batch runs. Applying a tailored setup shells out
    /// once per tweak and blocks on an authorization prompt for the admin ones,
    /// so the old behaviour — a button that stayed pressed for several seconds
    /// with no other feedback — was indistinguishable from a hang.
    ///
    /// Deliberately quiet: one ring, one accent, no bounce. The ring is real
    /// progress from `batchProgress`, not a spinner pretending to be busy.
    @ViewBuilder private var applyingOverlay: some View {
        if let p = model.engine.batchProgress {
            ZStack {
                // Near-opaque: at 0.82 the form behind stayed legible and
                // competed with the progress text for attention, which made the
                // whole thing read as washed out rather than focused.
                Theme.canvas.opacity(0.94).ignoresSafeArea()

                VStack(spacing: Space.l) {
                    ZStack {
                        // Track.
                        Circle()
                            .stroke(Theme.accent.opacity(0.12), lineWidth: 3)
                            .frame(width: 88, height: 88)

                        // A single slow breath outwards. The only motion that
                        // is not tied to real progress, so it stays faint —
                        // it says "working", the ring says how far.
                        Circle()
                            .stroke(Theme.accent.opacity(0.35), lineWidth: 2)
                            .frame(width: 88, height: 88)
                            .scaleEffect(pulse ? 1.18 : 1.0)
                            .opacity(pulse ? 0 : 0.5)

                        Circle()
                            .trim(from: 0, to: max(0.015, p.fraction))
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 88, height: 88)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.28), value: p.fraction)

                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    VStack(spacing: 5) {
                        Text("Applying your setup")
                            .font(.system(size: 17, weight: .semibold))

                        // Keyed on the title so each tweak crossfades in place
                        // rather than the label snapping between names.
                        Text(p.current.isEmpty ? "Finishing up" : p.current)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .id(p.current)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.18), value: p.current)

                        Text("\(p.done) of \(p.total)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.2), value: p.done)
                    }
                }
                .padding(.vertical, Space.l)
                .padding(.horizontal, Space.xl)
                // Sits on the same card language as every other grouped element
                // in the wizard, so the progress looks like part of the app
                // rather than a system dialog dropped on top of it.
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.10), radius: 20, y: 8)
                .padding(.horizontal, Space.l)
            }
            .transition(.opacity)
            .onAppear {
                pulse = false
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
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

    /// Every tweak the wizard treats as security-driven, and the subset that is
    /// rated safe. Read from the loaded catalog so the copy above cannot drift
    /// from `WizardAnswers.recommendedKeys()`.
    private var securityTweakCount: Int {
        model.engine.tweaks.filter { $0.tags.contains(.security) }.count
    }
    private var safeSecurityTweakCount: Int {
        model.engine.tweaks.filter { $0.tags.contains(.security) && $0.risk == .safe }.count
    }

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
                    Text("How much of the firewall, stealth mode and DNS hardening to switch on")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Picker("Security posture", selection: $model.wizard.securityPosture) {
                ForEach(SecurityPosture.allCases) { posture in
                    Text(posture.label).tag(posture)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            // The three labels name a stance but not a consequence, so the only
            // way to tell them apart was to pick one and count the review list.
            // This line says what changes, and it moves with the selection so
            // the answer is there before committing to it.
            Text(model.wizard.securityPosture.detail(total: securityTweakCount,
                                                     safe: safeSecurityTweakCount))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.18), value: model.wizard.securityPosture)
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
