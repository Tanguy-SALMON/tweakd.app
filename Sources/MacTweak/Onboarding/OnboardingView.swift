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
    @Environment(\.colorScheme) private var scheme
    @State private var step = 0
    private let lastStep = 3

    var body: some View {
        ZStack {
            Theme.heroBackground(scheme)
            VStack(spacing: 0) {
                content
                    .frame(maxHeight: .infinity)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .animation(.spring(duration: 0.4), value: step)
                controls
            }
            .padding(28)
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
        VStack(spacing: 18) {
            Spacer()
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.brand)
                .frame(width: 96, height: 96)
                .overlay(Image(systemName: "wand.and.stars")
                    .font(.system(size: 42, weight: .bold)).foregroundStyle(.white))
                .shadow(color: .purple.opacity(0.4), radius: 20, y: 8)
            Text("Let's tune your Mac")
                .font(.system(size: 34, design: .rounded).weight(.bold))
            Text("Answer a few quick questions and MacTweak will build a setup\ntailored to how you work — nothing you rely on gets disabled.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("How do you use your Mac?", "We'll keep these features on if you need them.")
            questionToggle("Apple Intelligence & Siri", "On-device AI, Siri, Lookup suggestions",
                           "sparkles", $model.wizard.usesAI)
            questionToggle("Spotlight search", "Searching files and content with ⌘Space",
                           "magnifyingglass", $model.wizard.usesSpotlight)
            questionToggle("Photos memories & faces", "Face recognition and auto Memories",
                           "photo.stack", $model.wizard.usesPhotos)
            questionToggle("AirDrop & AirPlay", "Sharing and screen mirroring nearby",
                           "airplayvideo", $model.wizard.usesAirDrop)
            Divider().padding(.vertical, 2)
            questionToggle("Prioritize privacy", "Also disable telemetry and suggestions",
                           "hand.raised.fill", $model.wizard.privacyFocused)
            questionToggle("Snappy interface", "Cut animation and input delays",
                           "hare.fill", $model.wizard.wantsSnappyUI)
        }
    }

    private var priority: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("What matters most?", "This biases the borderline tweaks.")
            HStack(spacing: 14) {
                ForEach(Priority.allCases) { p in
                    Button {
                        model.wizard.priority = p
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: p.icon).font(.system(size: 30))
                            Text(p.rawValue).font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                        .background(model.wizard.priority == p ?
                                    AnyShapeStyle(Theme.brand.opacity(0.9)) : AnyShapeStyle(.ultraThinMaterial),
                                    in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
                        .foregroundStyle(model.wizard.priority == p ? .white : .primary)
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                            .strokeBorder(.white.opacity(0.1)))
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
        return VStack(alignment: .leading, spacing: 14) {
            stepTitle("Your tailored setup", "\(picked.count) tweaks selected. You can change any of these later.")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(picked) { t in
                        HStack(spacing: 10) {
                            Image(systemName: t.category.icon).foregroundStyle(t.category.tint).frame(width: 22)
                            Text(t.title).font(.subheadline.weight(.medium))
                            Spacer()
                            Pill(text: t.risk.label, color: t.risk.tint)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if picked.isEmpty {
                        Text("No changes — you're keeping everything as-is. 👍")
                            .foregroundStyle(.secondary).padding()
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack {
            Button("Skip") { Task { await model.finishOnboarding(apply: false) } }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { i in
                    Circle().fill(i == step ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(.bordered).controlSize(.large)
            }
            if step < lastStep {
                Button("Next") { step += 1 }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(.purple)
            } else {
                Button("Apply Setup") { Task { await model.finishOnboarding(apply: true) } }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(.purple)
            }
        }
        .padding(.top, 12)
    }

    // MARK: Bits

    private func stepTitle(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(.title2, design: .rounded).weight(.bold))
            Text(sub).foregroundStyle(.secondary)
        }
    }

    private func questionToggle(_ title: String, _ sub: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).frame(width: 26).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
