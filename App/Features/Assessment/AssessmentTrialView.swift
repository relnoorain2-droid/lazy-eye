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
