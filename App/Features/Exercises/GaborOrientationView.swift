//
//  GaborOrientationView.swift
//
//  The M1 session screen. Also the template every other exercise view follows:
//  stimulus area, response area, session controls, break card, summary.
//
//  THE BACKGROUND IS MID-GREY AND THAT IS NOT A STYLE CHOICE.
//  A Gabor modulates luminance symmetrically above and below the background. On
//  a dark background the negative half of the sinusoid has nowhere to go, it
//  clips, and the contrast you asked for is not the contrast presented. Every
//  threshold measured on a black background is therefore measuring something
//  other than what it claims to. This is one of the specific reasons the
//  reference app's numbers are not meaningful, and it is why `stimulusNeutral`
//  is theme-independent in the token file.
//
//  docs/05-DESIGN-SYSTEM.md sections 4 and 6, docs/03-EXERCISE-CATALOG.md M1.
//

import SwiftUI
import SwiftData

@MainActor
struct GaborOrientationView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = GaborOrientationExercise()

    @State private var stimulus: CGImage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch runner.phase {
            case .ready:
                readyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surfaceBase.ignoresSafeArea())

            case .presenting, .feedback:
                // THE STIMULUS FIELD IS NO LONGER THE WHOLE SCREEN.
                //
                // `Color.stimulusNeutral.ignoresSafeArea()` used to fill every
                // pixel, which is what made this screen read as an unfinished
                // grey slab. The grey is a measurement requirement for the area
                // the Gabor occupies — it clips against anything darker — and it
                // was never a requirement for the timer, the buttons or the
                // margins. ExerciseStage draws the field as a defined surface
                // and styles everything outside it.
                ExerciseStage(
                    title: GaborOrientationExercise.descriptor.title,
                    secondsRemaining: runner.secondsRemaining,
                    secondsTotal: runner.plannedSessionSeconds,
                    descriptor: runner.descriptor,
                    onPause: { runner.pause() },
                    onFatigue: { runner.reportFatigue() }
                ) {
                    stimulusLayer
                } answers: {
                    answerButtons
                }

            case .onBreak(let remaining):
                BreakCard(secondsRemaining: remaining)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surfaceBase.ignoresSafeArea())

            case .paused:
                pausedState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surfaceBase.ignoresSafeArea())

            case .finished(let reason):
                SessionSummaryView(runner: runner, reason: reason) { onFinish(reason) }
            }
        }
        .statusBarHidden(runner.phase.acceptsResponses)
        .onChange(of: runner.currentTrial?.id) { _, _ in renderStimulus() }
        .onDisappear { runner.stop() }
    }

    /// The stimulus and its feedback mark. NOTHING here resizes the image: the
    /// Gabor is rendered at the exact pixel size the calibration demands, and
    /// `.interpolation(.none)` plus the absence of any frame is what keeps it
    /// that way.
    @ViewBuilder
    private var stimulusLayer: some View {
        ZStack {
            if let stimulus, runner.phase.acceptsResponses {
                Image(decorative: stimulus, scale: displayScale)
                    .interpolation(.none)
                    .accessibilityHidden(true)
            }
            if case .feedback(let correct) = runner.phase {
                FeedbackMark(correct: correct)
            }
        }
    }

    // MARK: States

    private var readyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "eye")
                .font(.system(size: 48))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            Text(GaborOrientationExercise.descriptor.title)
                .font(TypeScale.displayLarge())

            Text("A patch of soft stripes will appear. Tap the side it leans toward. It gets harder as you go — getting some wrong is how it finds your level.")
                .font(TypeScale.body())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            EvidenceBadge(tier: GaborOrientationExercise.descriptor.evidenceTier)

            if calibration.isComplete == false {
                SafetyBanner(level: .caution,
                             title: "Screen not calibrated",
                             message: "Sizes will be approximate until you finish calibration in Settings.")
            }

            AmblyoButton(title: "Start", systemImage: "play.fill") { runner.start() }
        }
        .padding(Spacing.lg)
        .readableContentWidth()
    }

    private var trialState: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                if let stimulus, runner.phase.acceptsResponses {
                    Image(decorative: stimulus, scale: displayScale)
                        .interpolation(.none)      // never resample a Gabor
                        .accessibilityHidden(true)
                }
                if case .feedback(let correct) = runner.phase {
                    FeedbackMark(correct: correct)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            answerButtons
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, 96)   // clear of the session control capsule
        }
    }

    private var answerButtons: some View {
        HStack(spacing: Spacing.md) {
            ForEach(GaborOrientationExercise.Answer.allCases, id: \.rawValue) { answer in
                AnswerButton(title: answer.label,
                             systemImage: answer.systemImage,
                             isEnabled: runner.phase.acceptsResponses) {
                    runner.respond(answer: answer.rawValue)
                }
                .accessibilityLabel("Leaning \(answer.label.lowercased())")
            }
        }
    }

    private var pausedState: some View {
        VStack(spacing: Spacing.lg) {
            Text("Paused").font(TypeScale.title())
            Text("Your progress is saved.")
                .font(TypeScale.callout())
                .foregroundStyle(Color.textSecondary)
            AmblyoButton(title: "Continue", systemImage: "play.fill") { runner.resume() }
            AmblyoButton(title: "Finish session", style: .tertiary) { runner.stopEarly() }
        }
        .padding(Spacing.lg)
        .readableContentWidth()
    }

    // MARK: Chrome

    @ViewBuilder
    private var statusBar: some View {
        if runner.phase.acceptsResponses || runner.phase == .paused {
            HStack {
                Text(timeString(runner.secondsRemaining))
                    .font(TypeScale.caption().monospacedDigit())
                Spacer()
                ProgressView(value: runner.progress)
                    .frame(width: 120)
                    .tint(.brandPrimary)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(runner.secondsRemaining / 60) minutes remaining")
        }
    }

    @ViewBuilder
    private var controls: some View {
        if !runner.phase.isTerminal && runner.phase != .ready {
            SessionControlCapsule(
                onFatigue: { runner.reportFatigue() },
                onPause: { runner.pause() }
            )
            .padding(.bottom, Spacing.md)
        }
    }

    // MARK: Rendering

    /// Generates the patch for the current trial.
    ///
    /// SYNCHRONOUS, ON THE MAIN ACTOR, DELIBERATELY.
    /// A 4-degree Gabor at 2x on a typical phone is roughly 345x345 = 119k
    /// pixels, each costing one cos and one exp - a couple of milliseconds in an
    /// optimised build, and it happens once per trial rather than once per
    /// frame. Moving it to a detached task would mean sending a `CGImage` and a
    /// SwiftData `@Model` across an isolation boundary, which under Swift 6
    /// strict concurrency costs more in unsafe-Sendable escape hatches than the
    /// two milliseconds are worth.
    ///
    /// If a future exercise needs a genuinely expensive stimulus - a large dot
    /// field regenerated per frame - that one gets a Metal path, not a thread.
    private func renderStimulus() {
        guard let trial = runner.currentTrial else {
            stimulus = nil
            return
        }
        let parameters = exercise.gaborParameters(for: trial, calibration: calibration)
        // Explicit Double(): displayScale is a CGFloat, and relying on the
        // implicit CGFloat/Double bridge inside a generic call is a needless
        // inference risk.
        stimulus = GaborGenerator.makeImage(parameters, scale: Double(displayScale))
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Feedback

/// Deliberately restrained. Loud celebration on a correct answer trains people
/// to chase the reward, and in an adaptive task the reward rate is pinned at
/// 79% by design - so the celebration stops meaning anything by trial twenty
/// while still costing attention.
private struct FeedbackMark: View {
    let correct: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: correct ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 44))
            .foregroundStyle(correct ? Color.success : Color.textSecondary)
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            .accessibilityLabel(correct ? "Correct" : "Not that one")
    }
}

// MARK: - Break card

struct BreakCard: View {
    let secondsRemaining: Int

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "figure.walk")
                .font(.system(size: 44))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            Text("Look away for a moment")
                .font(TypeScale.title())

            Text("Focus on something across the room. It gives your eyes a rest from close work.")
                .font(TypeScale.body())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Text("\(secondsRemaining)")
                .font(TypeScale.metric())
                .foregroundStyle(Color.brandPrimary)
                .contentTransition(.numericText())
                .accessibilityLabel("\(secondsRemaining) seconds left")
        }
        .padding(Spacing.lg)
        .readableContentWidth()
    }
}

// MARK: - Summary

struct SessionSummaryView: View {
    let runner: SessionRunner
    let reason: EndReason
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(headline).font(TypeScale.title())

                if reason == .fatigue {
                    SafetyBanner(level: .info,
                                 title: FatigueMonitor(consecutiveFatigueEndings: 0).guidance.title,
                                 message: FatigueMonitor(consecutiveFatigueEndings: 0).guidance.message)
                }

                HStack(spacing: Spacing.md) {
                    MetricTile(title: "Practice",
                               value: "\(runner.elapsedSeconds / 60)",
                               unit: "min",
                               needsScoreQualifier: false)
                    MetricTile(title: "Answers",
                               value: "\(runner.validTrialCount)",
                               needsScoreQualifier: false)
                }

                if let threshold = runner.formattedThreshold {
                    MetricTile(title: runner.descriptor.staircase.dimensionName.capitalized,
                               value: threshold)
                } else {
                    // Honesty over decoration. A number from a handful of trials
                    // is noise, and showing it would make every later trend line
                    // start from a fiction.
                    AmblyoCard {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Not enough answers yet")
                                .font(TypeScale.callout().weight(.semibold))
                            Text("A reliable level needs a longer session. Keep going and it will appear.")
                                .font(TypeScale.caption())
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                AmblyoButton(title: "Done", action: onDone)
            }
            .padding(Spacing.lg)
            .readableContentWidth()
        }
    }

    private var icon: String {
        switch reason {
        case .completed: "checkmark.circle.fill"
        case .fatigue: "moon.zzz.fill"
        case .cap: "clock.badge.checkmark"
        default: "flag.checkered"
        }
    }

    private var tint: Color {
        reason == .completed ? .success : .brandPrimary
    }

    private var headline: String {
        switch reason {
        case .completed: "Session complete"
        case .fatigue: "Stopped for today"
        case .cap: "That's today's practice done"
        case .userStopped: "Session ended"
        case .interrupted: "Session interrupted"
        }
    }
}
