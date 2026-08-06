//
//  SessionControls.swift
//
//  The two controls that are ALWAYS visible during an exercise: mute and
//  "my eyes feel tired". Both are one tap, from anywhere, with no confirmation.
//
//  These exist because of two specific 1-star reviews of the reference app —
//  "Just downloaded and can't find any way to turn off the noise" and a developer
//  reply telling a user that eye fatigue was a good sign.
//  docs/14-REVIEW-COMPLAINTS-MATRIX.md R1, R2, R4.
//

import SwiftUI

// MARK: - Mute

struct MuteControl: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button {
            settings.toggleMasterMute()
        } label: {
            Image(systemName: settings.masterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.masterMuted ? "Sound is off" : "Sound is on")
        .accessibilityHint("Turns all sound on or off")
        .accessibilityAddTraits(settings.masterMuted ? [] : .isSelected)
    }
}

// MARK: - Fatigue

struct FatigueButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.caution)
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("My eyes feel tired")
        .accessibilityHint("Ends this session and shows rest guidance")
    }
}

// MARK: - The capsule that carries both
//
// Sits top-trailing over a running exercise. Dims to 20% after 3 seconds of no
// interaction so it doesn't compete with the stimulus, but never disappears.

struct SessionControlCapsule: View {
    let onFatigue: () -> Void
    var onPause: (() -> Void)?

    @State private var isDimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        HStack(spacing: Spacing.md) {
            MuteControl()
            if let onPause {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .minimumTouchTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pause")
            }
            FatigueButton(onTap: onFatigue)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.regularMaterial, in: Capsule())
        // Never fully invisible, and never dimmed for VoiceOver or
        // Differentiate Without Colour users.
        .opacity(isDimmed && !differentiate ? 0.35 : 1)
        .animation(reduceMotion ? nil : Motion.gentle, value: isDimmed)
        .onTapGesture { wake() }
        .task { await scheduleDim() }
        .accessibilityElement(children: .contain)
    }

    private func wake() {
        isDimmed = false
        Task { await scheduleDim() }
    }

    private func scheduleDim() async {
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        isDimmed = true
    }
}

// MARK: - First-launch sound card
//
// Sounds are off. Rather than making the user hunt for the setting — the exact
// complaint on the reference app — we show this once and let them choose.

struct SoundChoiceCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.theme) private var theme
    let onComplete: () -> Void

    var body: some View {
        AmblyoCard(accent: .brandPrimary) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Sound is off", systemImage: "speaker.slash")
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))

                Text("Amblyo is silent unless you turn sound on. "
                   + "You can change this any time, and there's a mute button on every exercise.")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.sm) {
                    AmblyoButton(title: "Keep it silent", style: .secondary) {
                        settings.hasSeenSoundChoice = true
                        onComplete()
                    }
                    AmblyoButton(title: "Turn sound on") {
                        settings.soundEffectsEnabled = true
                        settings.musicEnabled = true
                        settings.hasSeenSoundChoice = true
                        onComplete()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Session controls") {
    VStack(spacing: Spacing.xl) {
        SessionControlCapsule(onFatigue: {}, onPause: {})
        SoundChoiceCard {}
    }
    .padding()
    .screenBackground()
    .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
}
