//
//  RemainingDichopticExercises.swift
//
//  D8 Bead Line, G4 Maze Runner and G7 Rhythm Tap.
//
//  ALL THREE FOLLOW RULES ALREADY ESTABLISHED IN THIS PHASE, and the rules are
//  worth restating because each was learned from a defect:
//
//    · Whatever the user must SEE goes to the amblyopic eye; whatever they
//      already know the position of goes to the fellow eye. (From Space Dodge,
//      where the reverse would have let a suppressing user steer by feel.)
//    · A self-report needs catch trials or it is unfalsifiable. (From Depth
//      Steps, where "I still see one" every time reported a perfect fusion
//      range.)
//    · Targets are sized by FINGERS as well as eyes: 44 points minimum, which is
//      1.48 degrees on the smallest supported screen. (From Stack Drop, where
//      eight columns would have made misses motor rather than visual.)
//
//  docs/03-EXERCISE-CATALOG.md D8, G4, G7.
//

import CoreGraphics
import Foundation

// MARK: - D8 Bead Line

/// A digital Brock string: two lines converge on a bead, one drawn to each eye.
/// Someone fusing sees two strings crossing at the bead; someone suppressing
/// sees one.
///
/// THE SAME UNFALSIFIABILITY PROBLEM AS D7, AND THE SAME FIX
/// "How many strings do you see?" is a self-report, and a user answering "two"
/// every time would be recorded as fusing perfectly at every depth. So one trial
/// in four draws only ONE string, to both eyes, where the honest answer is one.
/// Answering "two" blindly then fails those.
struct BeadLineExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.brockDigital",
        title: "Bead Line",
        track: .dichoptic,
        // Standard optometric practice; the published evidence in amblyopia
        // specifically is limited, and the badge says so.
        evidenceTier: .c,
        summary: "Lines run to a bead. Say how many you can see — one or two.",
        targets: "Noticing when one eye stops contributing",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "bead depth",
            unit: "arcmin",
            startValue: 25,
            hardestValue: 120,
            easiestValue: 8,
            polarity: .higherIsHarder,
            alternatives: 2,
            initialStepSize: 8,
            minimumStepSize: 2,
            renderLimit: .arcminutes(minimumFeaturePoints: 1.0)
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.15
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    enum Answer: Int, CaseIterable, Sendable {
        case one = 0
        case two = 1

        var label: String {
            switch self {
            case .one: "One line"
            case .two: "Two lines"
            }
        }
    }

    /// One trial in four is a single-line catch trial.
    static let catchTrialInterval: Int = 4

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let index = Int(generator.next() % 1_000_000)
        let isCatch = index % Self.catchTrialInterval == 0
        return Trial(
            difficulty: difficulty,
            correctAnswer: (isCatch ? Answer.one : .two).rawValue,
            payload: TrialPayload([
                "beadDepthArcmin": difficulty,
                "isCatch": isCatch ? 1 : 0
            ])
        )
    }

    func isCatchTrial(_ trial: Trial) -> Bool { trial.payload.value("isCatch") > 0.5 }

    /// Horizontal separation of the two lines at the bead, in points.
    func separationPoints(for trial: Trial, calibration: CalibrationProfile) -> Double {
        guard !isCatchTrial(trial) else { return 0 }
        var parameters = StereogramParameters()
        parameters.disparityArcminutes = trial.payload.value("beadDepthArcmin")
        parameters.pointsPerDegree = calibration.points(forDegrees: 1.0)
        return Double(parameters.shiftPoints)
    }

    static func interpretation(beadDepthArcminutes: Double) -> String {
        switch beadDepthArcminutes {
        case ..<15: "Both eyes stay in play only for near beads today"
        case ..<50: "Both eyes stay in play over a moderate range"
        default: "Both eyes stay in play over a wide range"
        }
    }
}

// MARK: - G4 Maze Runner

/// A wall crosses the field with a single gap in it. The WALL goes to the
/// amblyopic eye and the runner to the fellow eye, and the runner must be
/// steered through the gap.
///
/// WHICH EYE GETS WHICH, AND WHY IT IS EASY TO GET BACKWARDS HERE
/// The catalogue says "walls to one eye, runner to the other", which does not
/// say which way round — and the name "Maze RUNNER" pulls towards putting the
/// runner in the amblyopic eye. That would be wrong. The user's finger controls
/// the runner, so they know where it is without seeing it; the GAP is the thing
/// that must be seen, and the gap belongs to the wall. So the WALL goes to the
/// amblyopic eye and the runner to the fellow eye — the same argument as Space
/// Dodge, where putting the ship in the weak eye would have let a suppressing
/// user steer by feel and train nothing.
struct MazeRunnerExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "g.mazeRunner",
        title: "Maze Runner",
        track: .game,
        evidenceTier: .a,
        summary: "Steer through the gap in each wall. One eye sees the wall, the other sees your runner.",
        targets: "Both eyes working together while steering",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            alternatives: 2
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.30
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    static let runnerDegrees: Double = 1.2
    /// The gap must admit the runner with room to steer: three times its width.
    static let gapDegrees: Double = 3.6
    static let wallThicknessDegrees: Double = 0.8

    /// Walls approach at the shared ramp's speed, capped for steering time.
    static let maximumApproachSpeed: Double = 8.0

    static func approachSpeed(for difficulty: GameDifficulty) -> Double {
        min(difficulty.speedDegreesPerSecond, maximumApproachSpeed)
    }

    static func secondsToReach(for difficulty: GameDifficulty) -> Double {
        GameField.heightDegrees / approachSpeed(for: difficulty)
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        // Gap centre anywhere the whole gap fits.
        let margin = Self.gapDegrees / 2
        let span = GameField.widthDegrees - 2 * margin
        let gapCentre = margin + Double(generator.next() % 1_000) / 1_000.0 * span
        return Trial(
            difficulty: difficulty,
            correctAnswer: 1,               // passed through
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "gapCentre": gapCentre
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    func gapCentre(for trial: Trial) -> Double { trial.payload.value("gapCentre") }

    /// Did the runner pass through the gap rather than into the wall?
    static func passedThrough(runnerX: Double, gapCentre: Double) -> Bool {
        abs(runnerX - gapCentre) <= (gapDegrees - runnerDegrees) / 2
    }
}

// MARK: - G7 Rhythm Tap

/// A marker sweeps towards a line; tap when it arrives.
///
/// VISUAL-ONLY BY DEFAULT, WHICH IS A SAFETY DECISION RATHER THAN A STYLE ONE
/// Every audio channel in this app starts off (docs/14 R1), so a rhythm game
/// that needed sound would be silent and unplayable for most users. The timing
/// cue is the marker's position, and sound is an optional addition.
struct RhythmTapExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "g.rhythmTap",
        title: "Rhythm Tap",
        track: .game,
        evidenceTier: .b,
        summary: "Tap when the marker reaches the line. One eye sees the marker, the other sees the line.",
        targets: "Both eyes working together, with timing",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            alternatives: 2
        ),
        safety: SafetyEnvelope(
            // The marker sweeps once per trial. Not a repeating oscillation.
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.15
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    static let markerDegrees: Double = 1.4
    static let targetLineDegrees: Double = 0.6

    /// How close to the line a tap must land, in seconds. Generous, because this
    /// measures whether the marker was SEEN, not musical timing.
    static let toleranceSeconds: Double = 0.35

    static let maximumSweepSpeed: Double = 8.0

    static func sweepSpeed(for difficulty: GameDifficulty) -> Double {
        min(difficulty.speedDegreesPerSecond, maximumSweepSpeed)
    }

    static func secondsToLine(for difficulty: GameDifficulty) -> Double {
        GameField.heightDegrees / sweepSpeed(for: difficulty)
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        // A small random start offset so the arrival time is not identical every
        // trial — otherwise a user taps to a learned rhythm without looking.
        let offset = Double(generator.next() % 1_000) / 1_000.0 * 1.5
        return Trial(
            difficulty: difficulty,
            correctAnswer: 1,               // tapped in time
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "startDelay": offset
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    func startDelay(for trial: Trial) -> Double { trial.payload.value("startDelay") }

    /// Was the tap close enough in time to the marker's arrival?
    static func inTime(tapAt seconds: Double, arrivalAt arrival: Double) -> Bool {
        abs(seconds - arrival) <= toleranceSeconds
    }
}
