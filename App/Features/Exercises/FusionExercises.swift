//
//  FusionExercises.swift
//
//  D7 Depth Steps and D10 Hold the Fusion. Both measure the RANGE and STAMINA of
//  fusion rather than its acuity, and both had to be designed around the same
//  problem: a self-report is not a measurement.
//
//  THE PROBLEM, STATED PLAINLY
//  The natural way to write either of these is "tell us when it doubles" or
//  "hold this button while it stays fused". Both are unfalsifiable. A user who
//  answers "still single" every time, or holds the button throughout, produces a
//  staircase that walks steadily to the easiest end and reports an excellent
//  fusion range — and nothing in the data distinguishes them from someone with
//  genuinely excellent fusion. For an app that exists to measure suppression,
//  shipping a metric that rewards not looking would be worse than shipping no
//  metric at all.
//
//  WHAT EACH DOES INSTEAD
//    D7  keeps the report, and mixes in CATCH TRIALS at a disparity far beyond
//        any human fusion range, where the honest answer is "two". A user who
//        always answers "single" fails every catch trial, and the staircase sees
//        those failures.
//    D10 replaces the report entirely. A shape is drawn that is only identifiable
//        while the two eyes are fused; after the hold period the user names it.
//        Holding fusion is then demonstrated by the answer rather than asserted
//        by the user.
//
//  docs/03-EXERCISE-CATALOG.md D7, D10.
//

import CoreGraphics
import Foundation

// MARK: - D7 Depth Steps

struct DepthStepsExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.vergenceJump",
        title: "Depth Steps",
        track: .dichoptic,
        // Tier C, honestly: digital jump-vergence is standard optometric
        // practice but the published evidence for it in amblyopia specifically
        // is thin.
        evidenceTier: .c,
        summary: "A shape steps towards you and away. Say whether you still see one of it, or two.",
        targets: "How far your eyes can converge and diverge while staying fused",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "disparity",
            unit: "arcmin",
            startValue: 20,
            // Beyond about 200 arcmin almost nobody fuses, so that is the
            // practical ceiling rather than a target.
            hardestValue: 200,
            easiestValue: 5,
            // MORE disparity is harder to fuse.
            polarity: .higherIsHarder,
            alternatives: 2,
            initialStepSize: 10,
            minimumStepSize: 2,
            // Same one-point floor as D6: below a point of shift there is no
            // disparity on screen, only two identical images.
            renderLimit: .arcminutes(minimumFeaturePoints: 1.0)
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.20
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    enum Answer: Int, CaseIterable, Sendable {
        case two = 0
        case one = 1

        var label: String {
            switch self {
            case .one: "I see one"
            case .two: "I see two"
            }
        }
    }

    /// Every fifth trial is a catch trial. Frequent enough that a user answering
    /// "one" blindly fails several within a session; rare enough not to dominate
    /// the staircase, which is still measuring the real thing on the other four.
    static let catchTrialInterval: Int = 5

    /// Disparity used for catch trials — far past any human fusion range, so
    /// "two" is the only honest answer.
    static let catchDisparityArcminutes: Double = 600

    /// Target size. Large and simple: this measures fusion range, not acuity.
    static let targetDegrees: Double = 2.0

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        // Trial index drives the catch schedule deterministically rather than at
        // random, so a session always contains a predictable share of them.
        let index = Int(generator.next() % 1_000_000)
        let isCatch = index % Self.catchTrialInterval == 0
        let crossed = generator.next() % 2 == 0

        return Trial(
            difficulty: difficulty,
            correctAnswer: (isCatch ? Answer.two : .one).rawValue,
            payload: TrialPayload([
                "disparityArcmin": isCatch ? Self.catchDisparityArcminutes : difficulty,
                "isCatch": isCatch ? 1 : 0,
                "crossed": crossed ? 1 : 0
            ])
        )
    }

    func isCatchTrial(_ trial: Trial) -> Bool { trial.payload.value("isCatch") > 0.5 }

    /// Disparity actually presented, after the same quantisation D6 uses.
    func parameters(for trial: Trial,
                    calibration: CalibrationProfile) -> StereogramParameters {
        var parameters = StereogramParameters()
        parameters.disparityArcminutes = trial.payload.value("disparityArcmin")
        parameters.pointsPerDegree = calibration.points(forDegrees: 1.0)
        parameters.depth = trial.payload.value("crossed") > 0.5 ? .nearer : .further
        return parameters
    }

    /// Plain reading of a converged range.
    static func interpretation(disparityArcminutes: Double) -> String {
        switch disparityArcminutes {
        case ..<15: "A narrow fusion range today"
        case ..<40: "A moderate fusion range"
        case ..<100: "A comfortable fusion range"
        default: "A wide fusion range"
        }
    }
}

// MARK: - D10 Hold the Fusion

struct HoldTheFusionExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.fusionLock",
        title: "Hold the Fusion",
        track: .dichoptic,
        evidenceTier: .b,
        summary: "Keep both eyes working together while a hidden shape stays visible, then name it.",
        targets: "How long you can keep both eyes working together",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "hold",
            unit: "s",
            startValue: 4,
            // Twenty seconds of continuous fusion is a lot; beyond it the trial
            // becomes tedious rather than more informative.
            hardestValue: 20,
            easiestValue: 2,
            // LONGER is harder.
            polarity: .higherIsHarder,
            alternatives: 4,
            initialStepSize: 3,
            minimumStepSize: 1
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.35
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    typealias Answer = StereogramParameters.Shape

    /// The disparity the hidden shape is drawn at. Fixed and generous: this
    /// exercise measures how LONG fusion holds, not how fine it is. Letting the
    /// disparity vary too would make the threshold a mixture of the two.
    static let holdDisparityArcminutes: Double = 12

    static let fieldDegrees: Double = 6.5

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let shape = Answer.allCases.randomElement(using: &generator) ?? .square
        return Trial(
            difficulty: difficulty,
            correctAnswer: shape.rawValue,
            payload: TrialPayload([
                "holdSeconds": difficulty,
                "shape": Double(shape.rawValue),
                "seed": Double(generator.next() % 1_000_000)
            ])
        )
    }

    /// How long the user must keep looking before the question is asked.
    func holdSeconds(for trial: Trial) -> Double { trial.payload.value("holdSeconds") }

    /// The stereogram carrying the hidden shape.
    ///
    /// The shape is only identifiable while both eyes are fused, so a correct
    /// answer DEMONSTRATES the hold rather than asserting it. That is the whole
    /// reason this exercise is not a button the user holds down.
    func parameters(for trial: Trial,
                    calibration: CalibrationProfile) -> StereogramParameters {
        var parameters = StereogramParameters()
        parameters.shape = Answer(rawValue: Int(trial.payload.value("shape"))) ?? .square
        parameters.disparityArcminutes = Self.holdDisparityArcminutes
        parameters.pointsPerDegree = calibration.points(forDegrees: 1.0)
        parameters.fieldPoints = calibration.points(forDegrees: Self.fieldDegrees)
        parameters.dotPoints = max(2, (calibration.points(forDegrees: 1.0) * 6.0 / 60.0)
            .rounded())
        return parameters
    }

    static func interpretation(holdSeconds: Double) -> String {
        switch holdSeconds {
        case ..<4: "Fusion slips quickly today"
        case ..<8: "Fusion holds for a few seconds"
        case ..<15: "Fusion holds well"
        default: "Fusion holds for a long stretch"
        }
    }
}
