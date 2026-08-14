//
//  PeekabooAndSortExercises.swift
//
//  G3 Peekaboo and G6 Colour Sort. Both reuse mechanics already verified
//  elsewhere rather than inventing new ones — Peekaboo is Balloon Pop's tap with
//  a fixed set of burrows, and Colour Sort is Split Match's two-half card with a
//  sorting answer instead of a matching one.
//
//  WHY REUSE RATHER THAN INVENT
//  Each new mechanic brings its own way of being silently wrong: a target too
//  small to tap, a trial that cannot end in a miss, a distractor set one eye can
//  solve. Those three have each already been found and fixed once in this
//  project. Building on the fixed versions costs a little novelty and avoids
//  finding them a fourth time.
//
//  docs/03-EXERCISE-CATALOG.md G3, G6.
//

import CoreGraphics
import Foundation

// MARK: - G3 Peekaboo

/// Creatures appear in one of a fixed set of burrows and must be tapped before
/// they duck back down.
///
/// THE BURROWS ARE DRAWN TO BOTH EYES, THE CREATURE TO ONE
/// Both eyes see where the burrows are — that is the scene. Only the creature is
/// carried by the amblyopic eye, so a suppressing user sees a field of empty
/// holes and nothing to tap. Put the burrows in one eye too and the task becomes
/// "find the odd hole", which is a different measurement.
struct PeekabooExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "g.whackMole",
        title: "Peekaboo",
        track: .game,
        evidenceTier: .a,
        summary: "Tap the creature when it pops up. Only one eye can see it, so both eyes have to be working.",
        targets: "Both eyes working together, with a simple tapping game",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.25,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            // Tapped in time, or not.
            alternatives: 2
        ),
        safety: SafetyEnvelope(
            // A creature appearing and ducking is a transition, not a repeating
            // rate: one appearance per trial, and the trial ends on the tap.
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.15
        ),
        isFreeTier: false,
        minimumAgeGroup: .underFive
    )

    /// Six burrows in a 3 x 2 grid. Same reasoning as Stack Drop's six columns:
    /// each cell must be comfortably tappable on the smallest screen.
    static let columns: Int = 3
    static let rows: Int = 2

    static var burrowCount: Int { columns * rows }

    /// 2.2°: 66 pt on an iPhone SE, well past the 44 pt touch minimum, and large
    /// enough for a four-year-old aiming loosely.
    static let burrowDegrees: Double = 2.2

    /// How long the creature stays up. Falls with difficulty but never below a
    /// floor a small child can act on.
    static let longestVisible: Double = 3.0
    static let shortestVisible: Double = 1.5

    static func secondsVisible(for difficulty: GameDifficulty) -> Double {
        let progress = min(max(difficulty.contrastRatio / 1.0, 0), 1)
        return longestVisible - (longestVisible - shortestVisible) * progress
    }

    /// Centre of a burrow, in degrees.
    static func centre(ofBurrow index: Int) -> CGPoint {
        let column = index % columns
        let row = index / columns
        let cellWidth = GameField.widthDegrees / Double(columns)
        let cellHeight = GameField.heightDegrees / Double(rows)
        return CGPoint(x: (Double(column) + 0.5) * cellWidth,
                       y: (Double(row) + 0.5) * cellHeight)
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let burrow = Int(generator.next() % UInt64(Self.burrowCount))
        return Trial(
            difficulty: difficulty,
            correctAnswer: 1,               // tapped in time
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "burrow": Double(burrow)
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    func burrow(for trial: Trial) -> Int { Int(trial.payload.value("burrow")) }

    /// Did a tap land on the creature? Forgiving by a fifth of the burrow, for
    /// the same reason Balloon Pop is: this measures seeing, not pointing.
    static func tapped(at point: CGPoint, burrow index: Int) -> Bool {
        let centre = centre(ofBurrow: index)
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        return (dx * dx + dy * dy).squareRoot() <= burrowDegrees / 2 * 1.2
    }
}

// MARK: - G6 Colour Sort

/// Items carry one mark per eye, and the user sorts them by the COMBINATION.
///
/// The rule is deliberately simple — do the two halves match or not? — because
/// the difficulty must come from the contrast ratio, not from remembering a
/// rule. A four-category sort would measure working memory as much as vision.
struct ColourSortExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "g.colorSort",
        title: "Colour Sort",
        track: .game,
        evidenceTier: .b,
        summary: "Each shape has one mark for each eye. Say whether the two marks match.",
        targets: "Comparing what one eye sees against what the other sees",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            // Match or no match.
            alternatives: 2
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

    /// Four marks per side, as in Split Match.
    static let markCount: Int = 4

    /// The two answers.
    enum Answer: Int, CaseIterable, Sendable {
        case different = 0
        case same = 1

        var label: String {
            switch self {
            case .same: "Same"
            case .different: "Different"
            }
        }
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        // Half the trials match, so neither answer is a better guess than the
        // other. An unbalanced set would let a user beat chance by always
        // saying "different", and the staircase would read that as performance.
        let shouldMatch = generator.next() % 2 == 0
        let left = Int(generator.next() % UInt64(Self.markCount))
        let right = shouldMatch
            ? left
            : (left + 1 + Int(generator.next() % UInt64(Self.markCount - 1)))
                % Self.markCount

        return Trial(
            difficulty: difficulty,
            correctAnswer: (shouldMatch ? Answer.same : .different).rawValue,
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "leftMark": Double(left),
                "rightMark": Double(right)
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    /// Mark for the amblyopic eye.
    func leftMark(for trial: Trial) -> Int { Int(trial.payload.value("leftMark")) }
    /// Mark for the fellow eye.
    func rightMark(for trial: Trial) -> Int { Int(trial.payload.value("rightMark")) }
}
