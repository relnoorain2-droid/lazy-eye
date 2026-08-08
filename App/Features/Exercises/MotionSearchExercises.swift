//
//  MotionSearchExercises.swift
//
//  M7 Motion Field, M6 Crowded Letters, M12 Find It.
//
//  M12 is the first HIGHER-IS-HARDER exercise in the catalogue: more items on
//  screen means a harder search. The staircase handles that through `polarity`,
//  and getting it backwards would produce a confident measurement of the exact
//  opposite of what the card claims - which is why polarity has no default value
//  anywhere in this codebase.
//
//  docs/03-EXERCISE-CATALOG.md M6, M7, M12.
//

import Foundation

// MARK: - M7 · Motion Field

/// Global motion — the dorsal stream. Amblyopia affects motion integration
/// beyond what the acuity loss alone predicts, so this measures something the
/// detail tasks miss entirely.
struct MotionFieldExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.globalMotion",
        title: "Dot Drift",
        track: .monocular,
        evidenceTier: .b,
        summary: "A cloud of dots drifts one way. Say which way.",
        targets: "Motion perception — spotting movement in a noisy field",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "coherence",
            unit: "%",
            startValue: 90,
            // 3% with 200 dots is about six coherent dots. Below that a single
            // run's estimate is dominated by which dots happened to be signal.
            hardestValue: 3,
            easiestValue: 100,
            polarity: .lowerIsHarder,
            alternatives: 4
        ),
        // Dots translate smoothly; no screen region oscillates in luminance, so
        // the rate that FlickerGuard cares about is genuinely zero. Dot lifetime
        // is long and staggered so the field never refreshes wholesale.
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.15
        ),
        minimumAgeGroup: .fiveToTwelve
    )

    typealias Answer = KinematogramParameters.Direction

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let direction = Answer.allCases.randomElement(using: &generator) ?? .up
        let seed = Double(generator.next() % 1_000_000)
        return Trial(
            difficulty: difficulty,
            correctAnswer: direction.rawValue,
            payload: TrialPayload([
                "coherencePercent": difficulty,
                "direction": Double(direction.rawValue),
                "seed": seed
            ])
        )
    }

    func parameters(for trial: Trial,
                    calibration: CalibrationProfile) -> KinematogramParameters {
        KinematogramParameters(
            direction: Answer(rawValue: Int(trial.payload.value("direction"))) ?? .up,
            coherence: trial.payload.value("coherencePercent") / 100.0,
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            contrast: Self.descriptor.safety.maxContrast
        )
    }
}

// MARK: - M6 · Crowded Letters

/// Crowding with real optotypes. Closer to reading than the Gabor version, and
/// crowded letter acuity is the measure that best predicts reading difficulty in
/// amblyopia.
struct CrowdedLettersExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.crowdedLetters",
        title: "Squeezed Letters",
        track: .monocular,
        evidenceTier: .b,
        summary: "A letter sits between two others. Tap the middle one.",
        targets: "Reading letters when they're packed close together",
        defaultDurationSeconds: 300,
        staircase: StaircaseConfiguration(
            dimensionName: "spacing",
            unit: "x",
            startValue: 2.5,
            // 1.0 means the letters touch. Below that they overlap and it stops
            // being a crowding task.
            hardestValue: 1.0,
            easiestValue: 3.5,
            polarity: .lowerIsHarder,
            alternatives: 4
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.12
        ),
        // Reading letters. Pointless for a four-year-old, and frustrating for a
        // child who has not learned them all yet.
        minimumAgeGroup: .fiveToTwelve
    )

    /// Letter size, held fixed at a comfortably readable value so that SPACING
    /// is the only thing under test. 0.5 logMAR is roughly a large chart line.
    static let fixedLogMAR: Double = 0.5

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let choices = SloanLetters.choices(generator: &generator)
        guard choices.count == 4 else {
            return Trial(difficulty: difficulty, correctAnswer: 0,
                         payload: TrialPayload(["spacingRatio": difficulty]))
        }

        // The target is one of the four buttons; which one is randomised so the
        // correct answer is not always in the same position.
        let answerIndex = Int(generator.next() % 4)

        var payload: [String: Double] = [
            "spacingRatio": difficulty,
            "answerIndex": Double(answerIndex)
        ]
        // Letters travel as character codes so the payload stays a plain
        // [String: Double] and remains JSON-encodable for the trial record.
        for (index, letter) in choices.enumerated() {
            payload["choice\(index)"] = Double(letter.unicodeScalars.first?.value ?? 65)
        }
        // Flankers are two of the non-target letters. Indexed rather than
        // `.enumerated().map(\.element)`: a key path into an enumerated tuple
        // compiles, but tuple-rooted key paths are what produced the
        // "cannot infer key path type" failure in PlanGenerator, and avoiding
        // them costs nothing.
        var flankers: [String] = []
        for (index, letter) in choices.enumerated() where index != answerIndex {
            flankers.append(letter)
        }
        payload["flanker0"] = Double(flankers.first?.unicodeScalars.first?.value ?? 65)
        payload["flanker1"] = Double(flankers.dropFirst().first?.unicodeScalars.first?.value ?? 66)

        return Trial(difficulty: difficulty,
                     correctAnswer: answerIndex,
                     payload: TrialPayload(payload))
    }

    /// The four button labels for this trial, in order.
    func choices(for trial: Trial) -> [String] {
        (0..<4).map { index in
            let code = UInt32(trial.payload.value("choice\(index)", default: 65))
            return String(UnicodeScalar(code) ?? "A")
        }
    }

    func parameters(for trial: Trial,
                    calibration: CalibrationProfile) -> CrowdedLettersParameters {
        let answerIndex = Int(trial.payload.value("answerIndex"))
        let target = choices(for: trial)[min(max(answerIndex, 0), 3)]
        let flankers = ["flanker0", "flanker1"].map { key -> String in
            let code = UInt32(trial.payload.value(key, default: 65))
            return String(UnicodeScalar(code) ?? "A")
        }
        return CrowdedLettersParameters(
            target: target,
            flankers: flankers,
            logMAR: Self.fixedLogMAR,
            spacingRatio: trial.payload.value("spacingRatio"),
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            contrast: Self.descriptor.safety.maxContrast
        )
    }
}

// MARK: - M12 · Find It

/// Visual search. Lower evidence than the psychophysical tasks, and honest about
/// it — but it is the exercise children will actually keep opening, and an
/// exercise nobody does has an effect size of zero whatever its tier.
struct FindItExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.visualSearch",
        title: "Find It",
        track: .monocular,
        evidenceTier: .c,
        summary: "One shape points a different way from all the others. Tap it.",
        targets: "Searching and attention across the whole scene",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "items",
            unit: "",
            startValue: 8,
            // HIGHER IS HARDER here — more clutter, harder search. The only
            // exercise in the catalogue with this polarity so far.
            //
            // 20, not 40: an iPhone SE field can only hold about 36 items
            // without overlap, and asking for more than it can place would mean
            // the staircase measuring a difficulty the screen never presented.
            hardestValue: 20,
            easiestValue: 4,
            polarity: .higherIsHarder,
            alternatives: 2,
            // Coarser steps: item count is an integer, so a 3% step would round
            // to no change at all and the staircase would stall.
            initialStepSize: 0.5,
            minimumStepSize: 0.12
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.20
        ),
        minimumAgeGroup: .underFive
    )

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let seed = Double(generator.next() % 1_000_000)
        return Trial(
            difficulty: difficulty,
            // The answer is "which item", resolved by tap location rather than
            // a button index, so this is a placeholder the view does not use.
            correctAnswer: 0,
            payload: TrialPayload([
                "itemCount": difficulty.rounded(),
                "seed": seed
            ])
        )
    }

    func parameters(for trial: Trial,
                    calibration: CalibrationProfile) -> SearchFieldParameters {
        SearchFieldParameters(
            itemCount: max(2, Int(trial.payload.value("itemCount", default: 8))),
            pointsPerDegree: calibration.points(forDegrees: 1.0)
        )
    }
}
