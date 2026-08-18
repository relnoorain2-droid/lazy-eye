//
//  ExerciseStage.swift
//
//  The frame every exercise runs inside. docs/16-EXERCISE-STAGE-SPEC.md.
//
//  WHY ONE CONTAINER INSTEAD OF FIXING 32 SCREENS.
//  Each exercise view had its own copy of: ready state, stimulus area, answer
//  row, status bar, controls. Thirty-two copies of a layout is thirty-two
//  chances to be slightly different, and the first device test showed exactly
//  that — every screen crude in its own particular way. A shared stage means the
//  next visual decision is made once.
//
//  THE RULE THIS TYPE EXISTS TO ENFORCE.
//  The stage may style everything EXCEPT the stimulus. The stimulus field is
//  mid-grey because a Gabor modulates luminance symmetrically about its
//  background and clips against anything darker — so a "nicer" backdrop behind
//  it silently corrupts every threshold the app reports. The content closure is
//  therefore handed a plain field and never a frame, an aspect ratio, or a
//  scale factor. `ExerciseStageTests` checks that no modifier here can resize
//  what it contains.
//
//  Everything that makes the screen feel finished — the countdown ring, the
//  answer bar, the press states, the sound, the haptics — lives outside that
//  field, where it cannot affect a measurement.
//

import SwiftUI

// MARK: - Stage

@MainActor
struct ExerciseStage<Content: View, Answers: View>: View {

    let title: String
    /// Seconds left in the session, and the length it started at, for the ring.
    let secondsRemaining: Int
    let secondsTotal: Int

    /// The exercise being run, so the stage can show its own instructions.
    /// Optional only so a preview can omit it; every real caller passes one.
    var descriptor: ExerciseDescriptor?

    var onPause: () -> Void = {}
    var onFatigue: () -> Void = {}

    @ViewBuilder let content: () -> Content
    @ViewBuilder let answers: () -> Answers

    @Environment(SettingsStore.self) private var settings
    @Environment(\.theme) private var theme
    @State private var showingHowTo = false

    var body: some View {
        VStack(spacing: 0) {
            chrome
            stimulusField
            answerBar
        }
        .background(Color.surfaceBase.ignoresSafeArea())
        .onAppear { Haptics.prepare(settings: settings) }
        .sheet(isPresented: $showingHowTo) {
            if let descriptor { HowToSheet(descriptor: descriptor) }
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        HStack(spacing: Spacing.md) {
            CountdownRing(remaining: secondsRemaining, total: secondsTotal)

            Text(title)
                .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            // "HOW DO I DO THIS?", AVAILABLE MID-EXERCISE AND NOT ONLY BEFORE IT.
            //
            // The instructions were shown once, on the ready screen, and then
            // never again. That is the wrong moment: before the first trial the
            // words describe something the user has not seen yet, and the point
            // at which they actually want them is thirty seconds in, staring at
            // a patch of stripes with no idea what "leans" means. Reading help
            // does not pause the clock by accident either — the sheet pauses it,
            // because otherwise reading how to do it costs you the session.
            Button {
                onPause()
                showingHowTo = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Color.brandPrimary.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brandPrimary)
            .accessibilityLabel("How to do this exercise")

            Button(action: onPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause")

            Button(action: onFatigue) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.caution)
            .accessibilityLabel("My eyes feel tired")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: Stimulus field

    /// The measured surface. Mid-grey, rounded, with the shadow OUTSIDE it so no
    /// stimulus pixel is ever drawn on by decoration.
    private var stimulusField: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.stimulusNeutral)
                .shadow(color: .black.opacity(0.16), radius: 24, y: 10)

            // No frame, no aspectRatio, no scaleEffect. Deliberately.
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.md)
        .clipped()
    }

    // MARK: Answer bar

    private var answerBar: some View {
        answers()
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)
    }
}

// MARK: - Non-trial backdrop

extension View {
    /// The app surface behind ready, paused, break and summary states.
    ///
    /// Those screens are text and buttons; they were sitting on
    /// `stimulusNeutral` only because one `ignoresSafeArea` at the top of each
    /// exercise view covered everything. Mid-grey is a requirement for the area
    /// a stimulus occupies and a mistake everywhere else — it is the specific
    /// reason the ready screen looked unfinished.
    func sessionBackdrop() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surfaceBase.ignoresSafeArea())
    }
}

// MARK: - Countdown ring

/// The remaining time, readable at a glance without competing with the
/// stimulus. It used to be small grey text in a corner of a grey screen, which
/// is to say invisible.
struct CountdownRing: View {

    let remaining: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(remaining) / Double(total)))
    }

    private var label: String {
        let minutes = remaining / 60, seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Amber under a minute. Not red: running out of time is the session ending
    /// normally, not a failure, and this app is used by children.
    private var tint: Color {
        remaining <= 60 ? .caution : .brandPrimary
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.separatorLine.opacity(0.5), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: fraction)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .frame(width: 44, height: 44)
        .accessibilityElement()
        .accessibilityLabel("Time remaining")
        .accessibilityValue(label)
    }
}

// MARK: - Answer button

/// The large iconed button the answer bar is built from.
///
/// The old ones were plain white rectangles with a word in them. These are
/// 56 pt, carry an icon that reads faster than text, and confirm the touch by
/// scaling — which is the whole difference between a screen that feels
/// responsive and one that feels like it might have missed you.
struct AnswerButton: View {

    let title: String
    let systemImage: String
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.theme) private var theme
    @State private var pressed = false

    var body: some View {
        Button {
            Haptics.tap(settings: settings)
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.button + 4,
                                                                  style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button + 4, style: .continuous)
                    .strokeBorder(Color.separatorLine.opacity(0.6), lineWidth: 1)
            )
            .foregroundStyle(isEnabled ? Color.textPrimary : Color.textSecondary)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(Motion.quick, value: pressed)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        // Disabled during feedback so a fast double-tap cannot answer the trial
        // that has not been shown yet.
        .opacity(isEnabled ? 1 : 0.55)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .accessibilityLabel(title)
    }
}
