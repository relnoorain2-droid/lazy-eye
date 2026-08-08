//
//  TrackingExercises.swift
//
//  M9 Smooth Pursuit, M10 Jump Targets, M11 Hart Chart, M13 Path Tracer,
//  M14 Reading Ladder.
//
//  WHAT COUNTS AS A TRIAL, STATED PER EXERCISE.
//  Everything before this had one obvious trial: show a stimulus, take one
//  answer. These do not, and an inconsistent trial definition is a staircase
//  converging on nothing. Each descriptor below says exactly what one trial is.
//
//  ALL FIVE ARE TIER C EXCEPT M14, AND THE FILE IS HONEST ABOUT WHY.
//  Pursuit, saccade and tracing training are standard optometric practice with
//  limited published evidence in amblyopia specifically. They earn their place
//  by being tolerable and varied, which keeps people practising the tier-A and
//  tier-B work — an exercise nobody opens has an effect size of zero. The
//  evidence badge says C on the card, and the plan generator weights them at
//  0.6 against 1.4 for tier A, so they never crowd out better-supported work.
//
//  docs/03-EXERCISE-CATALOG.md M9-M14, docs/06-AI-ENGINE-SPEC.md section 3.
//

import Foundation

// MARK: - M9 · Smooth Pursuit

/// A trial is ONE COLOUR CHANGE: the target changes colour at random intervals
/// while it moves, and the user taps when it does. Correct means tapping within
/// the response window. That is what makes it a compliance check as well as an
/// exercise — you cannot pass by staring at the middle of the screen.
struct SmoothPursuitExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.pursuits",
        title: "Follow the Dot",
        track: .monocular,
        evidenceTier: .c,
        summary: "A dot moves around a looping path. Tap whenever it changes colour.",
        targets: "Smoothly following a moving object with your eyes",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "speed",
            unit: "°/s",
            startValue: 4,
            // 16 deg/s is near the upper limit of comfortable smooth pursuit;
            // beyond it the eye switches to catch-up saccades and the exercise
            // stops measuring pursuit at all.
            hardestValue: 16,
            easiestValue: 2,
            polarity: .higherIsHarder,
            alternatives: 2
        ),
        // The dot moves smoothly and changes colour at most once every ~2 s,
        // which is well under the 3 Hz ceiling. Colour changes are between two
        // similar-luminance colours so the change is chromatic, not a flash.
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0.5,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.03
        ),
        minimumAgeGroup: .underFive
    )

    /// Window in which a tap counts. Generous, because this measures tracking
    /// rather than reaction time.
    static let responseWindowSeconds: Double = 1.2

    /// Seconds between colour changes, randomised so the user cannot anticipate.
    static let minimumChangeInterval: Double = 1.5
    static let maximumChangeInterval: Double = 3.5

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let delay = Double.random(in: Self.minimumChangeInterval...Self.maximumChangeInterval,
                                  using: &generator)
        return Trial(
            difficulty: difficulty,
            // 0 = tapped in time. The view reports 1 when the window lapses.
            correctAnswer: 0,
            payload: TrialPayload([
                "speedDegreesPerSecond": difficulty,
                "changeDelay": delay,
                "phase": Double.random(in: 0..<(2 * .pi), using: &generator)
            ])
        )
    }

    func path(for trial: Trial, calibration: CalibrationProfile) -> PursuitPath {
        PursuitPath(
            phase: trial.payload.value("phase", default: .pi / 2),
            speedDegreesPerSecond: trial.payload.value("speedDegreesPerSecond", default: 4),
            pointsPerDegree: calibration.points(forDegrees: 1.0)
        )
    }
}

// MARK: - M10 · Jump Targets

/// A trial is ONE TARGET: it appears away from centre, the user taps it.
/// Eccentricity is the staircase axis — how far into the periphery a target can
/// appear and still be found and hit.
struct JumpTargetsExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.saccades",
        title: "Quick Taps",
        track: .monocular,
        evidenceTier: .c,
        summary: "A dot appears somewhere on the screen. Tap it as quickly as you can.",
        targets: "Moving your eyes quickly and landing accurately",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "distance",
            unit: "°",
            startValue: 1.4,
            // 2.5 degrees, not 9.
            //
            // An iPhone SE can only place a target 2.77 degrees from centre
            // before it runs off the edge. Asking for 9 would have clamped
            // silently on three of four supported devices - the staircase
            // climbing toward a difficulty the screen never presented, exactly
            // the bug Find It had. iPads could manage 10 degrees, but a fixed
            // ceiling keeps the measurement comparable across devices, which is
            // the whole reason this app calibrates.
            //
            // NO renderLimit here: this dimension is an ECCENTRICITY, bounded by
            // screen size rather than by feature legibility, and the RenderLimit
            // cases all describe the latter. Using one would be a unit error.
            hardestValue: 2.5,
            easiestValue: 1.0,
            polarity: .higherIsHarder,
            alternatives: 2
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.05
        ),
        minimumAgeGroup: .underFive
    )

    /// A tap slower than this counts as a miss — the target was found by search
    /// rather than by a saccade.
    static let responseWindowSeconds: Double = 2.0

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        Trial(
            difficulty: difficulty,
            correctAnswer: 0,
            payload: TrialPayload([
                "eccentricityDegrees": difficulty,
                "seed": Double(generator.next() % 1_000_000)
            ])
        )
    }
}

// MARK: - M11 · Hart Chart

/// A trial is ONE COMPLETED ROW: the user taps the prompted letters in order.
/// Getting one wrong ends the row and counts as incorrect. Grid density is the
/// staircase axis.
struct HartChartExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.hartChart",
        title: "Letter Rows",
        track: .monocular,
        evidenceTier: .c,
        summary: "Tap the highlighted letters in order, left to right.",
        targets: "Holding focus across a line of small print",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "columns",
            unit: "",
            startValue: 5,
            hardestValue: 10,
            easiestValue: 3,
            polarity: .higherIsHarder,
            alternatives: 10,
            initialStepSize: 0.45,
            // Integer columns: a small step rounds to no change and the
            // staircase stalls. Same lesson as Find It's item count.
            minimumStepSize: 0.15
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.15
        ),
        minimumAgeGroup: .fiveToTwelve
    )

    /// Letter size, fixed so DENSITY is what varies. 0.6 logMAR is comfortably
    /// readable for the target population.
    static let fixedLogMAR: Double = 0.6

    static let rows = 5

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        Trial(
            difficulty: difficulty,
            correctAnswer: 0,
            payload: TrialPayload([
                "columns": difficulty.rounded(),
                "seed": Double(generator.next() % 1_000_000)
            ])
        )
    }

    func chart(for trial: Trial, calibration: CalibrationProfile,
               generator: inout SeededGenerator) -> HartChart {
        let columns = max(3, Int(trial.payload.value("columns", default: 5)))
        let height = pow(10, Self.fixedLogMAR) * (calibration.points(forDegrees: 1.0) / 60) * 5
        return HartChartGenerator.make(
            columns: columns, rows: Self.rows,
            letterHeightPoints: height,
            sequenceLength: min(columns, 5),
            generator: &generator)
    }
}

// MARK: - M13 · Path Tracer

/// A trial is ONE TRACE from start to finish. Correct means never leaving the
/// corridor. Corridor width is the staircase axis.
struct PathTracerExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.tracing",
        title: "Stay on the Path",
        track: .monocular,
        evidenceTier: .c,
        summary: "Drag your finger along the winding path without leaving it.",
        targets: "Coordinating what you see with what your hand does",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "width",
            unit: "'",
            // ARCMINUTES, NOT DEGREES — and the unit matters more than it looks.
            //
            // This was 0.35...2.5 degrees with `.arcminutes(14)` as the render
            // limit. RenderLimit.arcminutes returns a value in ARCMINUTES, so
            // the clamp produced 21.4 and the staircase read it as 21.4 DEGREES:
            // an 840 pt corridor, wider than the screen. A silent unit mismatch
            // between a dimension and its own limit, which no type checker
            // catches because both sides are Double.
            //
            // 96 arcmin = 1.6 deg start, 21 arcmin = 0.35 deg floor.
            startValue: 96,
            // Below about 21 arcminutes the corridor is narrower than a
            // fingertip, so it would measure finger size rather than control.
            hardestValue: 21,
            easiestValue: 150,
            polarity: .lowerIsHarder,
            alternatives: 2,
            renderLimit: .arcminutes(minimumFeaturePoints: 14)
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.10
        ),
        minimumAgeGroup: .underFive
    )

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        Trial(
            difficulty: difficulty,
            correctAnswer: 0,
            payload: TrialPayload([
                "widthArcminutes": difficulty,
                "curviness": Double.random(in: 0.5...0.9, using: &generator),
                "seed": Double(generator.next() % 1_000_000)
            ])
        )
    }

    func path(for trial: Trial, calibration: CalibrationProfile,
              canvasPoints: Double, generator: inout SeededGenerator) -> TracePath {
        TracePathGenerator.make(
            canvasPoints: canvasPoints,
            // Payload is in arcminutes; convert to points here.
            corridorWidthPoints: trial.payload.value("widthArcminutes")
                * (calibration.points(forDegrees: 1.0) / 60),
            curviness: trial.payload.value("curviness", default: 0.7),
            generator: &generator)
    }
}

// MARK: - M14 · Reading Ladder

/// A trial is ONE PASSAGE plus its comprehension question. Correct requires
/// answering the question right — reading speed alone measures how fast someone
/// can scan past text they did not take in.
///
/// Tier B, and the only one of these five above tier C: functional reading is
/// the most meaningful monocular outcome in the amblyopia literature, and
/// crowded print is where the deficit actually shows up in daily life.
struct ReadingLadderExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "m.readingRate",
        title: "Reading Ladder",
        track: .monocular,
        evidenceTier: .b,
        summary: "Read a short passage, then answer one question about it. The print gets smaller.",
        targets: "Reading comfortably at small print sizes",
        defaultDurationSeconds: 300,
        staircase: StaircaseConfiguration(
            dimensionName: "print size",
            unit: " logMAR",
            startValue: 1.0,
            hardestValue: -0.1,
            easiestValue: 1.4,
            polarity: .lowerIsHarder,
            alternatives: 4,
            // 1.5 pt, not 2.5. At 2.5 the smallest print the ladder could reach
            // was 25 pt, which is larger than ordinary body text - the exercise
            // would never actually get to small print. Antialiased type resolves
            // well below that; 1.5 pt puts the floor near 15 pt, which is small
            // but genuinely readable.
            renderLimit: .logMAR(minimumFeaturePoints: 1.5)
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.25
        ),
        minimumAgeGroup: .fiveToTwelve
    )

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let index = Int(generator.next() % UInt64(ReadingPassages.all.count))
        let passage = ReadingPassages.passage(at: index)
        return Trial(
            difficulty: difficulty,
            correctAnswer: passage.correctOption,
            payload: TrialPayload([
                "logMAR": difficulty,
                "passageIndex": Double(index)
            ])
        )
    }

    func passage(for trial: Trial) -> ReadingPassage {
        ReadingPassages.passage(at: Int(trial.payload.value("passageIndex")))
    }

    /// Point size for the body text at this trial's logMAR.
    ///
    /// logMAR is defined on the gap of an optotype, and a letter's x-height is
    /// roughly half its cap height, so the multiplier below converts the acuity
    /// figure into something a text renderer can use. Approximate by nature —
    /// which is why the exercise reports a print SIZE the user can compare
    /// against their own history, not an acuity to compare against a clinic's.
    func fontPointSize(for trial: Trial, calibration: CalibrationProfile) -> Double {
        let arcminutes = pow(10, trial.payload.value("logMAR"))
        let pointsPerArcminute = calibration.points(forDegrees: 1.0) / 60
        // x-height = 5 gap widths; a typeface's point size is about 2x x-height.
        return max(6, arcminutes * pointsPerArcminute * 5 * 2)
    }
}
