//
//  GaborOrientationExercise.swift
//
//  M1 — Gabor Orientation. The reference implementation: every other exercise
//  follows this shape.
//
//  THE TASK
//  A Gabor patch appears at a random base orientation, tilted either clockwise
//  or anticlockwise by delta degrees. The user says which way it leans. Two
//  alternatives, so chance is 50%, and the staircase drives delta down toward
//  the smallest tilt the observer can still call reliably.
//
//  WHY THIS ONE FIRST
//  Orientation discrimination with Gabors is the single best-evidenced task in
//  the perceptual-learning literature, it is trivially explainable to a user
//  ("which way do the stripes lean"), and it exercises every part of the engine:
//  angular sizing, procedural rendering, a two-alternative staircase, and the
//  safety envelope. If M1 is right, M2-M14 are variations.
//
//  EVIDENCE TIER B, AND WHAT THAT LICENSES US TO SAY
//  The METHOD comes from published perceptual-learning studies, largely in
//  adults, using laboratory apparatus. It does not license any claim about what
//  this app achieves. docs/08-COMPLIANCE-LEGAL.md section 3A.
//
//  docs/03-EXERCISE-CATALOG.md M1.
//

import Foundation

struct GaborOrientationExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.gaborOrientation",
        title: "Stripe Tilt",
        track: .monocular,
        evidenceTier: .b,
        summary: "A patch of soft stripes appears. Say which way it leans.",
        targets: "Fine detail and orientation sensitivity",
        defaultDurationSeconds: 300,
        staircase: StaircaseConfiguration(
            dimensionName: "tilt",
            unit: "°",
            // 20° is unmissable for almost everyone, which is the point: the
            // first minute should feel easy so the user learns the interaction
            // before the task starts costing anything.
            startValue: 20,
            // 1° is near the limit of normal orientation discrimination. Going
            // below it would measure the display's angular resolution instead of
            // the observer.
            hardestValue: 1,
            easiestValue: 40,
            polarity: .lowerIsHarder,
            alternatives: 2
        ),
        // Static stimulus. The patch appears, the user answers, it disappears.
        // Nothing oscillates, so the temporal rate is genuinely zero rather than
        // "low" - the safest possible declaration.
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.12
        ),
        // The one full exercise the free tier gets. Chosen deliberately: it is
        // the most credible thing we have, so the free experience is the
        // strongest argument for the paid one.
        isFreeTier: true,
        minimumAgeGroup: .fiveToTwelve
    )

    // MARK: Answers

    enum Answer: Int, CaseIterable, Sendable {
        case anticlockwise = 0
        case clockwise = 1

        var label: String {
            switch self {
            case .anticlockwise: "Left"
            case .clockwise: "Right"
            }
        }

        var systemImage: String {
            switch self {
            case .anticlockwise: "arrow.turn.up.left"
            case .clockwise: "arrow.turn.up.right"
            }
        }
    }

    // MARK: Trial generation

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let tilt = Answer.allCases.randomElement(using: &generator) ?? .clockwise

        // Random base orientation every trial. Without this the observer can
        // learn "the stripes are usually near vertical" and answer from memory
        // of the previous trial rather than from the current one - which the
        // staircase would faithfully record as improvement.
        let baseOrientation = Double.random(in: 0..<180, using: &generator)

        let signedDelta = tilt == .clockwise ? difficulty : -difficulty

        // Random phase for the same reason: it stops the observer tracking the
        // position of a single bright bar instead of judging orientation.
        let phase = Double.random(in: 0..<(2 * .pi), using: &generator)

        return Trial(
            difficulty: difficulty,
            correctAnswer: tilt.rawValue,
            payload: TrialPayload([
                "orientation": baseOrientation + signedDelta,
                "baseOrientation": baseOrientation,
                "phase": phase,
                "delta": difficulty
            ])
        )
    }

    // MARK: Rendering parameters

    /// Turns a trial into something `GaborGenerator` can draw, using this
    /// profile's calibration so the patch is the same ANGULAR size on every
    /// device. This function is the payoff for the whole calibration step.
    func gaborParameters(for trial: Trial,
                         calibration: CalibrationProfile) -> GaborParameters {
        let pointsPerDegree = calibration.points(forDegrees: 1.0)

        // A 4° patch at 3 cycles per degree gives roughly 12 visible cycles -
        // enough for orientation to be unambiguous, small enough to sit well
        // within central vision at any supported distance.
        let patchDegrees = 4.0
        let sigmaDegrees = patchDegrees / 6   // ±3σ fits inside the patch

        return GaborParameters(
            orientationDegrees: trial.payload.value("orientation"),
            cyclesPerDegree: 3.0,
            contrast: Self.descriptor.safety.maxContrast,
            sigmaDegrees: sigmaDegrees,
            phase: trial.payload.value("phase"),
            sizePoints: pointsPerDegree * patchDegrees,
            pointsPerDegree: pointsPerDegree
        )
    }
}
