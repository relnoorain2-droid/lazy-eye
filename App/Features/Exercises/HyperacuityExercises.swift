//
//  HyperacuityExercises.swift
//
//  M4 Vernier Line-Up, M8 Glass Pattern, M3 Crowded Gabor.
//
//  All three share the choice shell and all three declare render limits.
//  docs/03-EXERCISE-CATALOG.md M3, M4, M8.
//

import Foundation

// MARK: - M4 · Vernier Line-Up

/// Positional precision. Vernier thresholds improve markedly with training in
/// the perceptual-learning literature, and because it is a hyperacuity it can
/// resolve differences finer than the acuity test can — so it keeps measuring
/// after Ring Gaps has hit the display floor.
struct VernierExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.vernier",
        title: "Line Up",
        track: .monocular,
        evidenceTier: .b,
        summary: "Two short lines, one above the other. Say which way the top one is shifted.",
        targets: "Positional precision — how small a misalignment you can spot",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "offset",
            unit: "\"",
            startValue: 400,
            // Normal vernier thresholds are 5-10 arcsec. Unreachable on a phone,
            // and the render limit says so rather than pretending otherwise.
            hardestValue: 5,
            easiestValue: 1200,
            polarity: .lowerIsHarder,
            alternatives: 2,
            renderLimit: .arcseconds(
                minimumFeaturePoints: VernierGenerator.minimumTrustworthyOffsetPoints)
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.05
        ),
        minimumAgeGroup: .fiveToTwelve
    )

    enum Answer: Int, CaseIterable, Sendable {
        case left = 0, right = 1
        var label: String { self == .left ? "Left" : "Right" }
        var systemImage: String { self == .left ? "arrow.left" : "arrow.right" }
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let answer = Answer.allCases.randomElement(using: &generator) ?? .left
        let signed = answer == .right ? difficulty : -difficulty
        return Trial(
            difficulty: difficulty,
            correctAnswer: answer.rawValue,
            payload: TrialPayload(["offsetArcseconds": signed])
        )
    }

    func parameters(for trial: Trial, calibration: CalibrationProfile) -> VernierParameters {
        VernierParameters(
            offsetArcseconds: trial.payload.value("offsetArcseconds"),
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            contrast: Self.descriptor.safety.maxContrast
        )
    }
}

// MARK: - M8 · Glass Pattern

/// Global form. No local patch of the image contains the answer — it only
/// exists across the whole field — so this probes integration rather than
/// resolution, and it keeps working at sizes the acuity task cannot reach.
struct GlassPatternExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.globalForm",
        title: "Dot Swirl",
        track: .monocular,
        evidenceTier: .b,
        summary: "A field of dot pairs forms either rings or spokes. Say which.",
        targets: "Global form — pulling a whole shape out of scattered detail",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "signal",
            unit: "%",
            startValue: 90,
            // 4% is near the floor of what is measurable with 300 pairs: below
            // it, a single run's estimate is dominated by which dots happened to
            // land where.
            hardestValue: 4,
            easiestValue: 100,
            polarity: .lowerIsHarder,
            alternatives: 2
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            // A large field, but of small sparse dots — the high-contrast AREA
            // is the sum of the dots, not the bounding box.
            maxHighContrastAreaFraction: 0.20
        ),
        minimumAgeGroup: .fiveToTwelve
    )

    enum Answer: Int, CaseIterable, Sendable {
        case rings = 0, spokes = 1
        var label: String { self == .rings ? "Rings" : "Spokes" }
        var systemImage: String {
            self == .rings ? "circle.circle" : "rays"
        }
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let answer = Answer.allCases.randomElement(using: &generator) ?? .rings
        // Seed carried in the payload so the exact dot field can be regenerated
        // for a bug report — the dots are random, but reproducibly so.
        let seed = Double(generator.next() % 1_000_000)
        return Trial(
            difficulty: difficulty,
            correctAnswer: answer.rawValue,
            payload: TrialPayload([
                "signalPercent": difficulty,
                "form": Double(answer.rawValue),
                "seed": seed
            ])
        )
    }

    func parameters(for trial: Trial,
                    calibration: CalibrationProfile) -> GlassPatternParameters {
        GlassPatternParameters(
            form: GlassPatternParameters.Form(
                rawValue: Int(trial.payload.value("form"))) ?? .concentric,
            signalFraction: trial.payload.value("signalPercent") / 100.0,
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            contrast: Self.descriptor.safety.maxContrast
        )
    }
}

// MARK: - M3 · Crowded Gabor

/// Crowding: a target that is perfectly visible alone becomes unidentifiable
/// when flanked. The effect is disproportionately severe in amblyopia, which
/// makes it a specific deficit rather than a general one — and it is a large
/// part of why reading is hard for people whose acuity looks acceptable.
struct CrowdedGaborExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.flankedGabor",
        title: "Crowded Stripes",
        track: .monocular,
        evidenceTier: .b,
        summary: "A faint striped patch sits between two strong ones. Say which way the middle one leans.",
        targets: "Seeing detail when it's surrounded by clutter",
        defaultDurationSeconds: 300,
        staircase: StaircaseConfiguration(
            dimensionName: "spacing",
            unit: "λ",
            startValue: 6,
            // Below ~1λ the patches physically overlap and it stops being a
            // crowding task at all — it becomes a superposition of gratings.
            hardestValue: 1.2,
            // 8, not 12. At 12λ the triplet is 392 pt wide on an iPhone SE and
            // the flankers fall off a 320 pt screen — which quietly removes the
            // crowding the exercise exists to measure.
            easiestValue: 8,
            polarity: .lowerIsHarder,
            alternatives: 2
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.15
        ),
        minimumAgeGroup: .thirteenPlus
    )

    typealias Answer = GaborOrientationExercise.Answer

    /// Tilt of the centre patch. Fixed, and deliberately generous: this exercise
    /// varies SPACING, so the tilt must stay easy enough that a wrong answer
    /// means crowding rather than a tilt too fine to see. Letting both vary
    /// would produce a threshold describing neither.
    static let centreTiltDegrees: Double = 15

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let tilt = Answer.allCases.randomElement(using: &generator) ?? .clockwise
        let signed = tilt == .clockwise ? Self.centreTiltDegrees : -Self.centreTiltDegrees
        return Trial(
            difficulty: difficulty,
            correctAnswer: tilt.rawValue,
            payload: TrialPayload([
                "separationLambda": difficulty,
                "centreOrientation": 90 + signed,
                "phase": Double.random(in: 0..<(2 * .pi), using: &generator),
                "flankerPhase": Double.random(in: 0..<(2 * .pi), using: &generator)
            ])
        )
    }

    func parameters(for trial: Trial,
                    calibration: CalibrationProfile) -> CrowdedGaborParameters {
        CrowdedGaborParameters(
            centreOrientationDegrees: trial.payload.value("centreOrientation"),
            separationLambda: trial.payload.value("separationLambda"),
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            phase: trial.payload.value("phase"),
            flankerPhase: trial.payload.value("flankerPhase")
        )
    }
}
