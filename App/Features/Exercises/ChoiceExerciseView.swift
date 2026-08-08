//
//  ChoiceExerciseView.swift
//
//  One session screen shared by every "look at a stimulus, tap which one"
//  exercise. M1, M2 and M5 use it today; M3, M6, M7, M8 and M12 will.
//
//  WHY A SHARED SHELL RATHER THAN A VIEW PER EXERCISE
//  The chrome is where the safety behaviour lives — the fatigue button, the
//  break card, the cap, the honest summary. Duplicating that across thirteen
//  exercises means thirteen chances to omit the fatigue button, and the one that
//  omits it will not be caught by a test because it is a layout, not a value.
//  One shell, one place those guarantees exist, and each exercise supplies only
//  its stimulus and its answer labels.
//
//  docs/03-EXERCISE-CATALOG.md, docs/05-DESIGN-SYSTEM.md section 6.
//

import SwiftUI

/// What an exercise must provide to use the shared shell.
@MainActor
protocol ChoiceExercisePresenter {
    /// Buttons, in answer-index order, when they are the same every trial.
    var answers: [(label: String, systemImage: String)] { get }

    /// Buttons for a SPECIFIC trial, when they change — M6 shows four different
    /// letters each time. Defaults to `answers`, so exercises with fixed buttons
    /// ignore this entirely.
    func answers(for trial: Trial) -> [(label: String, systemImage: String)]

    /// The stimulus for this trial. Returning nil draws nothing, which is
    /// correct during feedback rather than an error.
    func stimulus(for trial: Trial, calibration: CalibrationProfile,
                  scale: Double) -> CGImage?

    /// Where to draw it, as a unit offset from centre in (-1...1). Most
    /// exercises centre their stimulus; M2 puts it in one of four corners.
    func offset(for trial: Trial) -> CGPoint

    /// Instructions shown before the first trial.
    var instructions: String { get }
}

extension ChoiceExercisePresenter {
    func offset(for trial: Trial) -> CGPoint { .zero }
    func answers(for trial: Trial) -> [(label: String, systemImage: String)] { answers }
}

@MainActor
struct ChoiceExerciseView<Presenter: ChoiceExercisePresenter>: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    let presenter: Presenter
    var onFinish: (EndReason) -> Void = { _ in }

    @State private var stimulus: CGImage?
    @State private var stimulusOffset: CGPoint = .zero

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Color.stimulusNeutral.ignoresSafeArea()

            switch runner.phase {
            case .ready:
                readyState
            case .presenting, .feedback:
                trialState
            case .onBreak(let remaining):
                BreakCard(secondsRemaining: remaining)
            case .paused:
                pausedState
            case .finished(let reason):
                SessionSummaryView(runner: runner, reason: reason) { onFinish(reason) }
            }
        }
        .overlay(alignment: .top) { statusBar }
        .overlay(alignment: .bottom) { controls }
        .statusBarHidden(runner.phase.acceptsResponses)
        .onChange(of: runner.currentTrial?.id) { _, _ in renderStimulus() }
        .onDisappear { runner.stop() }
    }

    // MARK: States

    private var readyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "eye")
                .font(.system(size: 48))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            Text(runner.descriptor.title).font(TypeScale.displayLarge())

            Text(presenter.instructions)
                .font(TypeScale.body())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            EvidenceBadge(tier: runner.descriptor.evidenceTier)

            if !calibration.isComplete {
                SafetyBanner(level: .caution,
                             title: "Screen not calibrated",
                             message: "Sizes will be approximate until you finish calibration in Settings.")
            } else if runner.descriptor.staircase.isLimitedByDisplay(for: calibration) {
                // Honest, and worth saying out loud: hitting the floor here means
                // the device ran out of resolution, NOT that the person did.
                SafetyBanner(
                    level: .info,
                    title: "This screen sets the limit",
                    message: "At your viewing distance this exercise can only get so hard. Holding the device further away raises the ceiling."
                )
            }

            AmblyoButton(title: "Start", systemImage: "play.fill") { runner.start() }
        }
        .padding(Spacing.lg)
        .readableContentWidth()
    }

    private var trialState: some View {
        GeometryReader { geometry in
            ZStack {
                if let stimulus, runner.phase.acceptsResponses {
                    Image(decorative: stimulus, scale: displayScale)
                        .interpolation(.none)          // never resample a stimulus
                        .position(
                            x: geometry.size.width / 2
                                + stimulusOffset.x * geometry.size.width * 0.26,
                            y: geometry.size.height / 2
                                + stimulusOffset.y * geometry.size.height * 0.18
                        )
                        .accessibilityHidden(true)
                }
                if case .feedback(let correct) = runner.phase {
                    ChoiceFeedbackMark(correct: correct)
                }
            }
        }
        .overlay(alignment: .bottom) {
            answerButtons.padding(.horizontal, Spacing.lg).padding(.bottom, 96)
        }
    }

    private var answerButtons: some View {
        // Per-trial where the exercise needs it (M6's letters), otherwise the
        // fixed set. Falls back to the fixed set between trials so the buttons
        // do not vanish during the feedback moment.
        let answers = runner.currentTrial.map { presenter.answers(for: $0) } ?? presenter.answers
        // Two across for a 2AFC, a 2x2 grid for a 4AFC. Beyond four the layout
        // would need rethinking, which is why nothing here has more.
        let columns = answers.count <= 2 ? answers.count : 2

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md),
                           count: columns),
            spacing: Spacing.md
        ) {
            ForEach(Array(answers.enumerated()), id: \.offset) { index, answer in
                Button {
                    runner.respond(answer: index)
                } label: {
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: answer.systemImage).font(.system(size: 24))
                        Text(answer.label)
                            .font(TypeScale.callout().weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: answers.count <= 2 ? 88 : 68)
                    .background(Color.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!runner.phase.acceptsResponses)
                .accessibilityLabel(answer.label)
            }
        }
    }

    private var pausedState: some View {
        VStack(spacing: Spacing.lg) {
            Text("Paused").font(TypeScale.title())
            Text("Your progress is saved.")
                .font(TypeScale.callout()).foregroundStyle(Color.textSecondary)
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
                ProgressView(value: runner.progress).frame(width: 120).tint(.brandPrimary)
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
            SessionControlCapsule(onFatigue: { runner.reportFatigue() },
                                  onPause: { runner.pause() })
                .padding(.bottom, Spacing.md)
        }
    }

    // MARK: Rendering

    private func renderStimulus() {
        guard let trial = runner.currentTrial else {
            stimulus = nil
            return
        }
        stimulusOffset = presenter.offset(for: trial)
        stimulus = presenter.stimulus(for: trial,
                                      calibration: calibration,
                                      scale: Double(displayScale))
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Feedback

private struct ChoiceFeedbackMark: View {
    let correct: Bool
    var body: some View {
        Image(systemName: correct ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 44))
            .foregroundStyle(correct ? Color.success : Color.textSecondary)
            .accessibilityLabel(correct ? "Correct" : "Not that one")
    }
}

// MARK: - Presenters

struct LandoltPresenter: ChoiceExercisePresenter {
    private let exercise = LandoltRingsExercise()

    var answers: [(label: String, systemImage: String)] {
        LandoltRingsExercise.Answer.allCases.map { ($0.label, $0.systemImage) }
    }

    var instructions: String {
        "A ring will appear with a small gap in it. Tap the side the gap is on. It gets smaller as you go."
    }

    func stimulus(for trial: Trial, calibration: CalibrationProfile,
                  scale: Double) -> CGImage? {
        LandoltGenerator.makeImage(
            exercise.landoltParameters(for: trial, calibration: calibration),
            scale: scale)
    }
}

struct ContrastHuntPresenter: ChoiceExercisePresenter {

    var answers: [(label: String, systemImage: String)] {
        ContrastHuntExercise.Answer.allCases.map { ($0.label, $0.systemImage) }
    }

    var instructions: String {
        "A very faint patch of stripes will appear in one corner. Tap that corner. If you can't see it, guess — that's expected, and it's how the app finds your level."
    }

    func stimulus(for trial: Trial, calibration: CalibrationProfile,
                  scale: Double) -> CGImage? {
        ContrastPatchGenerator.makeImage(
            contrast: trial.payload.value("contrast"),
            cyclesPerDegree: ContrastHuntExercise.cyclesPerDegree,
            orientationDegrees: trial.payload.value("orientation"),
            phase: trial.payload.value("phase"),
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            scale: scale)
    }

    func offset(for trial: Trial) -> CGPoint {
        let index = Int(trial.payload.value("quadrant"))
        let offsets = ContrastPatchGenerator.quadrantOffsets
        return offsets.indices.contains(index) ? offsets[index] : .zero
    }
}
