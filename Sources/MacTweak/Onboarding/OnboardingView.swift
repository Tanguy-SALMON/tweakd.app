//
//  OnboardingView.swift
//  MacTweak
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
            Text("Answer a few quick questions and MacTweak will build a setup\ntailored to how you work — nothing you rely on gets disabled.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            stepTitle("How do you use your Mac?", "We'll keep these features on if you need them.")
            questionToggle("Apple Intelligence & Siri", "On-device AI, Siri, Lookup suggestions",
                           "sparkles", $model.wizard.usesAI)
            questionToggle("Spotlight search", "Searching files and content with ⌘Space",
                           "magnifyingglass", $model.wizard.usesSpotlight)
            questionToggle("Photos memories & faces", "Face recognition and auto Memories",
                           "photo.stack", $model.wizard.usesPhotos)
            questionToggle("AirDrop & AirPlay", "Sharing and screen mirroring nearby",
                           "airplayvideo", $model.wizard.usesAirDrop)
            Divider().overlay(Theme.hairline).padding(.vertical, 2)
            questionToggle("Prioritize privacy", "Also disable telemetry and suggestions",
                           "hand.raised", $model.wizard.privacyFocused)
            questionToggle("Snappy interface", "Cut animation and input delays",
                           "hare", $model.wizard.wantsSnappyUI)
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
                Button("Back") { step -= 1 }.buttonStyle(.bordered).controlSize(.large)
            }
            if step < lastStep {
                Button("Next") { step += 1 }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button("Apply Setup") { Task { await model.finishOnboarding(apply: true) } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
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
}
