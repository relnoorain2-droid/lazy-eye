//
//  BalanceMeterExercise.swift
//
//  D5 Balance Meter. Not a game — the MEASUREMENT, and the most defensible
//  number this app produces.
//
//  HOW IT WORKS
//  Coherently-moving signal dots go to the amblyopic eye at fixed contrast.
//  Random noise dots go to the fellow eye at contrast ratio R. The user reports
//  which way the coherent flow moves. As R rises the fellow eye's noise starts
//  to swamp the signal, and the R at which that happens is the BINOCULAR BALANCE
//  RATIO.
//
//  WHAT THE NUMBER MEANS
//      R near 1.0   the two eyes contribute about equally
//      R around 0.5 moderate suppression of the amblyopic eye
//      R below 0.3  the fellow eye dominates even when its signal is faint
//  Rising R over weeks is the outcome the contrast-rebalance literature reports,
//  which is why this is tracked weekly and shown as the headline on Progress.
//
//  POLARITY, WHICH IS EASY TO GET BACKWARDS
//  Low R means faint noise, so the signal is EASY to see. High R means the noise
//  swamps it. Therefore `higherIsHarder`, and the converged threshold IS the
//  balance point rather than something to be transformed afterwards.
//
//  AND THE HONEST LIMIT
//  It is a behavioural balance point measured on a phone through consumer
//  glasses. It is not a clinical suppression measurement, and the score
//  qualifier stays attached to it everywhere it appears.
//
//  docs/03-EXERCISE-CATALOG.md D5, docs/01-RESEARCH-BRIEF.md section 4.
//

import Foundation

struct BalanceMeterExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.suppressionCheck",
        title: "Balance Meter",
        track: .dichoptic,
        evidenceTier: .a,
        summary: "Moving dots, split between your two eyes. Say which way the flow goes.",
        targets: "How evenly your two eyes are working together",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            // A ratio, so the range is logarithmic and multiplicative steps fit
            // naturally. 0.1...2.0 is about 7 steps of 1.5x — enough resolution
            // without a session spending its whole budget travelling.
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            alternatives: 4
        ),
        safety: SafetyEnvelope(
            // Dots translate smoothly; no region oscillates in luminance. Same
            // reasoning as M7 Dot Drift.
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            // Bounded by the compositor's headroom, not by choice.
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.15
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    typealias Answer = KinematogramParameters.Direction

    /// Contrast the SIGNAL dots are drawn at, in the amblyopic eye. Fixed, so
    /// the ratio is the only thing that varies — letting both move would produce
    /// a threshold describing neither.
    static let signalContrast: Double = 0.7

    /// Coherence of the signal field. High and fixed: this exercise measures
    /// interocular balance, not motion sensitivity. M7 measures that.
    static let signalCoherence: Double = 0.9

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let direction = Answer.allCases.randomElement(using: &generator) ?? .up
        return Trial(
            difficulty: difficulty,
            correctAnswer: direction.rawValue,
            payload: TrialPayload([
                "balanceRatio": difficulty,
                "direction": Double(direction.rawValue),
                "signalSeed": Double(generator.next() % 1_000_000),
                "noiseSeed": Double(generator.next() % 1_000_000)
            ])
        )
    }

    /// The coherent field, shown to the amblyopic eye.
    func signalField(for trial: Trial,
                     calibration: CalibrationProfile) -> KinematogramParameters {
        var parameters = KinematogramParameters(
            direction: Answer(rawValue: Int(trial.payload.value("direction"))) ?? .up,
            coherence: Self.signalCoherence,
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            contrast: Self.signalContrast)
        parameters.dotCount = 120
        return parameters
    }

    /// The noise field, shown to the fellow eye. Zero coherence by definition —
    /// it carries no direction, only interference.
    func noiseField(for trial: Trial,
                    calibration: CalibrationProfile) -> KinematogramParameters {
        var parameters = KinematogramParameters(
            direction: .up,
            coherence: 0,
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            contrast: min(Self.signalContrast * trial.payload.value("balanceRatio"),
                          AnaglyphCompositor.maximumContrast))
        parameters.dotCount = 120
        return parameters
    }

    /// Human-readable reading of a converged threshold, for the Progress screen.
    ///
    /// Deliberately banded rather than precise: a single session's estimate is
    /// +-20% at the 95th percentile, so quoting two decimal places would imply a
    /// precision the measurement does not have.
    static func interpretation(balanceRatio: Double) -> String {
        switch balanceRatio {
        case ..<0.3: "One eye is doing most of the work"
        case ..<0.7: "Still uneven, but both eyes are contributing"
        case ..<1.3: "Fairly even between the two eyes"
        default: "Even, with the weaker eye holding its own"
        }
    }
}
