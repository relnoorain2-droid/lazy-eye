//
//  AssessmentTrialView.swift
//
//  Draws the stimulus for one check-in trial, and its answer buttons.
//
//  WHY THIS FILE EXISTS AT ALL.
//  The check-in shipped to TestFlight rendering four buttons labelled "1", "2",
//  "3", "4" over an empty white panel. The code carried a comment saying the
//  stimulus would arrive "in a later pass", and the measurement path underneath
//  was genuinely complete and tested — so it read, to me, as an acceptable
//  staging point. It was not. A measurement screen with nothing to measure is
//  not a partially-built feature; it is a broken one, and it went in front of a
//  user looking exactly as broken as it was.
//
//  THE DESIGN CONSTRAINT THAT MAKES THIS SMALL.
//  The battery deliberately borrows REGISTERED exercises rather than
//  reimplementing tests of its own — see `AssessmentBattery.exerciseID(for:)`
//  and the test that pins it. That decision was made so the measurement matches
//  the training version. Its second dividend is this file: the renderers already
//  exist, so the check-in does not need stimulus code, only a way to reach it.
//
//  docs/16-EXERCISE-STAGE-SPEC.md, docs/03-EXERCISE-CATALOG.md assessment.
//

import SwiftUI

@MainActor
struct AssessmentTrialView: View {

    let trial: Trial
    let presenter: AssessmentPresenter
    let calibration: CalibrationProfile
    var isAnswerable: Bool = true
    let onAnswer: (Int) -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: Spacing.md) {
            stimulusPanel
            answerButtons
        }
    }

    /// Mid-grey and unstyled, for the same reason the training screens are:
    /// a luminance-modulated stimulus clips against anything darker, and a
    /// clipped stimulus measures the display rather than the person. The
    /// check-in produces the numbers that go on the Progress chart, so it is
    /// the LAST screen that should be decorated.
    private var stimulusPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.stimulusNeutral)

            if let image = presenter.stimulus(for: trial,
                                              calibration: calibration,
                                              scale: displayScale) {
                Image(decorative: image, scale: displayScale)
                    .interpolation(.none)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 300)
        .clipped()
    }

    private var answerButtons: some View {
        let options = presenter.answers(for: trial)
        let columns = options.count <= 2 ? options.count : 2
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm),
                           count: max(1, columns)),
            spacing: Spacing.sm
        ) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                AnswerButton(title: option.label,
                             systemImage: option.systemImage,
                             isEnabled: isAnswerable) {
                    onAnswer(index)
                }
            }
        }
    }
}

// MARK: - Live stimuli

/// The stereo sub-test's field.
///
/// Separate from `AssessmentTrialView` because it draws rather than rasterises:
/// a random-dot stereogram is a Canvas of thousands of squares, not an image,
/// so it cannot go through the `AssessmentPresenter` path the acuity and
/// contrast sub-tests use. Same `StereogramField` D6 draws, so the number the
/// check-in produces is measured with the stimulus the user trains on — which
/// is the entire reason the battery borrows registered exercises.
@MainActor
struct AssessmentStereoView: View {

    let trial: Trial
    let calibration: CalibrationProfile
    var isAnswerable: Bool = true
    let onAnswer: (Int) -> Void

    private let exercise = DepthPopExercise()

    /// Built outside `body` rather than with a `let` inside it. Result builders
    /// do allow declarations now, but a plain computed property is one less
    /// thing depending on which Swift version the runner happens to ship.
    private var made: (pair: StereogramPair, parameters: StereogramParameters) {
        StereogramField.make(for: trial, exercise: exercise, calibration: calibration)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            StereogramField(pair: made.pair,
                            parameters: made.parameters,
                            calibration: calibration)
                .frame(maxWidth: .infinity)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm),
                                GridItem(.flexible(), spacing: Spacing.sm)],
                      spacing: Spacing.sm) {
                ForEach(StereogramParameters.Shape.allCases, id: \.rawValue) { shape in
                    AnswerButton(title: shape.label,
                                 systemImage: shape.systemImage,
                                 isEnabled: isAnswerable) {
                        onAnswer(shape.rawValue)
                    }
                }
            }
        }
    }
}

/// The balance sub-test's field — the free tier's only measurement, and the one
/// a reviewer is most likely to open.
///
/// It was showing "not in this build yet" over an empty panel, which is both a
/// broken free tier and a Guideline 2.1 rejection waiting to happen. Same
/// `BalanceField` D5 animates.
@MainActor
struct AssessmentBalanceView: View {

    let trial: Trial
    let calibration: CalibrationProfile
    var isAnswerable: Bool = true
    let onAnswer: (Int) -> Void

    private let exercise = BalanceMeterExercise()

    var body: some View {
        VStack(spacing: Spacing.md) {
            BalanceField(
                signal: exercise.signalField(for: trial, calibration: calibration),
                noise: exercise.noiseField(for: trial, calibration: calibration),
                calibration: calibration,
                signalSeed: UInt64(trial.payload.value("signalSeed")),
                noiseSeed: UInt64(trial.payload.value("noiseSeed")))
                .frame(maxWidth: .infinity)

            VStack(spacing: Spacing.sm) {
                directionButton(.up)
                HStack(spacing: Spacing.sm) {
                    directionButton(.left)
                    directionButton(.right)
                }
                directionButton(.down)
            }
        }
    }

    private func directionButton(_ direction: KinematogramParameters.Direction) -> some View {
        AnswerButton(title: direction.label,
                     systemImage: direction.systemImage,
                     isEnabled: isAnswerable) {
            onAnswer(direction.rawValue)
        }
    }
}

// MARK: - Presenter

/// The subset of a training exercise's presentation the check-in needs.
///
/// Narrower than `ChoiceExercisePresenter` on purpose: the check-in never
/// positions a stimulus off-centre and never shows instructions mid-trial, and
/// a protocol that promises things its only caller ignores is a protocol that
/// will drift.
@MainActor
protocol AssessmentPresenter {
    func answers(for trial: Trial) -> [(label: String, systemImage: String)]
    func stimulus(for trial: Trial, calibration: CalibrationProfile,
                  scale: Double) -> CGImage?
}

/// Bridges any training presenter into the check-in, so the two never diverge.
struct BridgedAssessmentPresenter<Wrapped: ChoiceExercisePresenter>: AssessmentPresenter {
    let wrapped: Wrapped

    func answers(for trial: Trial) -> [(label: String, systemImage: String)] {
        wrapped.answers(for: trial)
    }

    func stimulus(for trial: Trial, calibration: CalibrationProfile,
                  scale: Double) -> CGImage? {
        wrapped.stimulus(for: trial, calibration: calibration, scale: scale)
    }
}
