//
//  MonocularExercises.swift
//
//  M5 Landolt Rings and M2 Contrast Hunt.
//
//  Both declare a `renderLimit`, which is what stops their staircases descending
//  past what the screen can draw. See `RenderLimit` — three of the four bounds
//  originally written for this file were physically impossible, and the failure
//  mode is a confident wrong number rather than an error.
//
//  docs/03-EXERCISE-CATALOG.md M2 and M5.
//

import Foundation

// MARK: - M5 · Landolt Rings

/// The acuity measure, and the closest thing this app has to a number a clinic
/// would recognise. Reported in logMAR because that is the scale eye clinics
/// use — 0.0 is 20/20, higher is worse, and each 0.1 is one chart line.
struct LandoltRingsExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.landoltC",
        title: "Ring Gaps",
        track: .monocular,
        evidenceTier: .b,
        summary: "A ring appears with a gap in it. Tap the side the gap is on.",
        targets: "Fine detail — how small a feature you can still make out",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "detail",
            unit: " logMAR",
            // 1.0 logMAR is a very large ring — roughly the top line of a chart.
            // Starting easy is not politeness; the first trials teach the
            // interaction, and a staircase that starts below threshold wastes
            // its coarse descent climbing back up.
            startValue: 1.0,
            // Aspirational. On a phone at 35 cm the real floor lands near 0.29
            // logMAR, and `renderLimit` raises it to whatever this screen can
            // honestly draw.
            hardestValue: -0.3,
            easiestValue: 1.4,
            polarity: .lowerIsHarder,
            alternatives: 4,
            // A 1.2 pt gap is the smallest that survives antialiasing as a
            // recognisable gap rather than a smudge. Below that the ring reads
            // as a closed circle and the observer guesses.
            renderLimit: .logMAR(minimumFeaturePoints: 1.2)
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.10
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    enum Answer: Int, CaseIterable, Sendable {
        case up = 0, right = 1, down = 2, left = 3

        var label: String {
            switch self {
            case .up: "Up"
            case .right: "Right"
            case .down: "Down"
            case .left: "Left"
            }
        }

        var systemImage: String {
            switch self {
            case .up: "arrow.up"
            case .right: "arrow.right"
            case .down: "arrow.down"
            case .left: "arrow.left"
            }
        }

        /// Degrees clockwise from up, matching `LandoltGenerator.directions`.
        var degrees: Double { Double(rawValue) * 90 }
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let answer = Answer.allCases.randomElement(using: &generator) ?? .up
        return Trial(
            difficulty: difficulty,
            correctAnswer: answer.rawValue,
            payload: TrialPayload([
                "logMAR": difficulty,
                "gapDegrees": answer.degrees
            ])
        )
    }

    func landoltParameters(for trial: Trial,
                           calibration: CalibrationProfile) -> LandoltParameters {
        LandoltParameters(
            gapDirectionDegrees: trial.payload.value("gapDegrees"),
            logMAR: trial.payload.value("logMAR"),
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            contrast: Self.descriptor.safety.maxContrast
        )
    }
}

// MARK: - M2 · Contrast Hunt

/// Contrast sensitivity, which in amblyopia is often reduced even when acuity
/// looks acceptable — so it catches something the acuity test alone misses.
struct ContrastHuntExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.contrastDetection",
        title: "Faint Patch",
        track: .monocular,
        evidenceTier: .b,
        summary: "A faint patch of stripes appears in one corner. Tap the corner it's in.",
        targets: "Contrast sensitivity — how faint a pattern you can still see",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "contrast",
            unit: "",
            startValue: 0.5,
            // Aspirational; 8-bit output puts the true floor near 0.012.
            hardestValue: 0.002,
            easiestValue: 0.95,
            polarity: .lowerIsHarder,
            alternatives: 4,
            // Three quantisation steps of separation. At one or two the
            // modulation is indistinguishable from dithering noise, and the
            // observer is guessing at a uniform grey rectangle while the
            // staircase records a threshold.
            renderLimit: .contrast(minimumQuantisationSteps: 3)
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            // The stimulus is by definition low contrast; the declared maximum
            // is the START of the staircase, not a typical trial.
            maxContrast: 0.95,
            maxHighContrastAreaFraction: 0.10
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    enum Answer: Int, CaseIterable, Sendable {
        case topLeft = 0, topRight = 1, bottomLeft = 2, bottomRight = 3

        var label: String {
            switch self {
            case .topLeft: "Top left"
            case .topRight: "Top right"
            case .bottomLeft: "Bottom left"
            case .bottomRight: "Bottom right"
            }
        }

        var systemImage: String {
            switch self {
            case .topLeft: "arrow.up.left"
            case .topRight: "arrow.up.right"
            case .bottomLeft: "arrow.down.left"
            case .bottomRight: "arrow.down.right"
            }
        }
    }

    /// Spatial frequency the patch is presented at. Fixed rather than varied,
    /// because contrast sensitivity is only meaningful AT a stated frequency —
    /// letting both vary would produce a number that describes neither.
    /// 3 c/deg sits near the peak of the human contrast sensitivity function,
    /// so it is where a deficit shows up most clearly.
    static let cyclesPerDegree: Double = 3.0

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let quadrant = Answer.allCases.randomElement(using: &generator) ?? .topLeft

        // Randomised so the observer cannot learn a fixed pattern, and so a
        // stuck orientation preference in one eye does not bias the threshold.
        let orientation = Double.random(in: 0..<180, using: &generator)
        let phase = Double.random(in: 0..<(2 * .pi), using: &generator)

        return Trial(
            difficulty: difficulty,
            correctAnswer: quadrant.rawValue,
            payload: TrialPayload([
                "contrast": difficulty,
                "quadrant": Double(quadrant.rawValue),
                "orientation": orientation,
                "phase": phase
            ])
        )
    }
}
