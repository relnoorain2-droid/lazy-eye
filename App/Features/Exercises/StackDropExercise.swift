//
//  StackDropExercise.swift
//
//  D3 Stack Drop. The canonical dichoptic game from the literature: the FALLING
//  PIECE goes to the amblyopic eye, the STACK it must land in goes to the fellow
//  eye. Neither eye alone can play it — you cannot aim something you can see at
//  a target you cannot, or vice versa.
//
//  WHY A TARGET COLUMN RATHER THAN TETRIS SCORING
//  Real Tetris scoring is line clears, which is a poor measurement: a line clear
//  depends on the last twenty pieces as much as this one, so a "correct" would
//  not be evidence about the trial in front of you. Instead each piece has one
//  marked column in the stack layer, and landing in it is the trial's outcome.
//  That keeps a piece = a trial, which keeps the same staircase the rest of the
//  app uses, and it makes the dichoptic demand explicit: the marker is only
//  visible to the fellow eye, the piece only to the amblyopic one.
//
//  SIX COLUMNS, NOT EIGHT, AND THE REASON IS A THUMB
//  Eight columns divides the 9-degree field into 1.125-degree cells, which is
//  33 points on an iPhone SE — below Apple's 44-point minimum touch target. A
//  user missing a 33-point column is missing it for MOTOR reasons, and the app
//  would record that as a suppression failure and make the exercise easier in
//  response. Six columns gives 1.5 degrees, 45 points on the smallest screen.
//
//  AND ITS OWN SPEED CEILING
//  The shared ramp reaches 15 deg/s, which drops a piece the full height of the
//  field in 0.8 seconds. That is not aimable — it measures reaction time, not
//  fusion. D3 caps at 8 deg/s, so the slowest drop is 2.4 seconds and the fastest
//  1.5, which leaves room to look at both layers before committing.
//
//  docs/03-EXERCISE-CATALOG.md D3.
//

import CoreGraphics
import Foundation

struct StackDropExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.fallingBlocks",
        title: "Stack Drop",
        track: .dichoptic,
        evidenceTier: .a,
        summary: "Steer the falling block into the marked slot. One eye sees the block, the other sees the slot.",
        targets: "Both eyes working together on one task at the same time",
        defaultDurationSeconds: 300,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            // Six columns, so a blind guess lands correctly one time in six.
            alternatives: 6
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.25
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    /// Six columns: 1.5° each, which is 45 pt on an iPhone SE. Eight columns
    /// would be 33 pt — under the 44 pt touch minimum, so misses would be motor
    /// rather than visual and the staircase would misread them.
    static let columns: Int = 6

    static var cellDegrees: Double { GameField.widthDegrees / Double(columns) }

    /// Whole rows that fit. 8 at 1.5° = 12°, exactly the field height.
    static var rows: Int { Int(GameField.heightDegrees / cellDegrees) }

    /// D3's own ceiling, well under the shared 15 deg/s. At 15 a piece crosses
    /// the whole field in 0.8 s, which measures reaction time rather than
    /// fusion; at 8 the fastest drop is 1.5 s.
    static let maximumDropSpeed: Double = 8.0

    /// Drop speed for a difficulty, on D3's slower schedule.
    static func dropSpeed(for difficulty: GameDifficulty) -> Double {
        min(difficulty.speedDegreesPerSecond, maximumDropSpeed)
    }

    /// Seconds a piece takes to fall the whole field at this difficulty. Used by
    /// the tests to hold the aimability floor.
    static func dropSeconds(for difficulty: GameDifficulty) -> Double {
        GameField.heightDegrees / dropSpeed(for: difficulty)
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let target = Int(generator.next() % UInt64(Self.columns))
        // Never start above the target: the piece must be steered, not dropped.
        var start = Int(generator.next() % UInt64(Self.columns))
        if start == target {
            start = (start + 1 + Int(generator.next() % UInt64(Self.columns - 1)))
                % Self.columns
        }

        return Trial(
            difficulty: difficulty,
            correctAnswer: target,
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "targetColumn": Double(target),
                "startColumn": Double(start)
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    func targetColumn(for trial: Trial) -> Int {
        Int(trial.payload.value("targetColumn"))
    }

    func startColumn(for trial: Trial) -> Int {
        Int(trial.payload.value("startColumn"))
    }

    /// Centre of a column, in degrees.
    static func centreX(ofColumn column: Int) -> Double {
        (Double(column) + 0.5) * cellDegrees
    }

    /// Which column a horizontal position falls in, clamped to the grid.
    static func column(atX x: Double) -> Int {
        let raw = Int(x / cellDegrees)
        return min(max(raw, 0), columns - 1)
    }
}
