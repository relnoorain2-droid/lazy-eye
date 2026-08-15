//
//  HiddenHalfExercise.swift
//
//  D9 Hidden Half. A conjunction search where the two features live in
//  DIFFERENT EYES.
//
//  THE MECHANIC, AND WHY IT CANNOT BE CHEATED
//  Every item on screen carries up to two marks: a ring, drawn only to the
//  amblyopic eye, and a dot, drawn only to the fellow eye. The target is the one
//  item that has BOTH. Distractors have one or the other.
//
//  Close either eye and the display collapses into "some items have rings" or
//  "some items have dots" — and in each case several items qualify. The target
//  is not hidden, it is ABSENT from either monocular view. That is a stronger
//  guarantee than a contrast manipulation, which a determined suppressor can
//  sometimes squint past.
//
//  ONE MEASURED DIMENSION, AGAIN
//  The catalogue lists this as "contrast ratio plus distractor count". As with
//  the games, only the ratio is staircased; the item count rises with it on a
//  fixed schedule (5 items at the easy end, 12 at the hard end). Two independent
//  dimensions would produce a threshold describing neither.
//
//  CHANCE LEVEL IS SET BY THE EASIEST TRIAL, NOT THE AVERAGE
//  With 4 items a guesser is right 25% of the time; with 12, 8%. The staircase
//  takes ONE `alternatives` value for its guess correction, so it has to be the
//  worst case — the fewest items — or the app will read a lucky guesser as a
//  performer and keep making the exercise harder.
//
//  ITEMS ARE 1.6 DEGREES BECAUSE OF FINGERS
//  Same reasoning as Balloon Pop: 1.6 degrees is 48 points on an iPhone SE,
//  clear of Apple's 44-point touch minimum. Verified by rejection sampling that
//  12 items at 2.0 degrees minimum separation place successfully in 200 out of
//  200 attempted layouts, so a trial never quietly shows fewer items than the
//  difficulty called for — the defect found in M12 Find It during Phase 6.
//
//  docs/03-EXERCISE-CATALOG.md D9.
//

import CoreGraphics
import Foundation

struct HiddenHalfExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.dichopticSearch",
        title: "Hidden Half",
        track: .dichoptic,
        evidenceTier: .b,
        summary: "Find the one shape with BOTH a ring and a dot. Each eye only sees one of the two marks.",
        targets: "Combining what each eye sees into one picture",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            // The EASIEST trial's item count, because that is the highest a
            // guesser's success rate ever gets.
            alternatives: minimumItems
        ),
        safety: SafetyEnvelope(
            // A static display. Items appear, the user taps, the next trial
            // begins — nothing repeats at a rate.
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.25
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    /// 1.6°: 48 pt on an iPhone SE, past the 44 pt touch minimum.
    static let itemDegrees: Double = 1.6
    /// Centre-to-centre minimum. Verified to place 12 items in 200/200 layouts.
    static let minimumSeparationDegrees: Double = 2.0

    static let minimumItems: Int = 4
    static let maximumItems: Int = 12

    /// Item count for a difficulty. Rises with the ratio on a fixed schedule so
    /// it never becomes a second measured dimension.
    static func itemCount(for difficulty: GameDifficulty) -> Int {
        let progress = min(max(difficulty.contrastRatio / 1.0, 0), 1)
        let span = Double(maximumItems - minimumItems)
        return minimumItems + Int((span * progress).rounded())
    }

    /// One searchable item.
    struct Item: Sendable, Equatable {
        /// Centre, in degrees.
        let position: CGPoint
        /// Drawn to the amblyopic eye.
        let hasRing: Bool
        /// Drawn to the fellow eye.
        let hasDot: Bool

        /// Only the target has both.
        var isTarget: Bool { hasRing && hasDot }
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let level = GameDifficulty(contrastRatio: difficulty)
        let count = Self.itemCount(for: level)
        let targetIndex = Int(generator.next() % UInt64(count))

        return Trial(
            difficulty: difficulty,
            correctAnswer: targetIndex,
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "itemCount": Double(count),
                "targetIndex": Double(targetIndex),
                "layoutSeed": Double(generator.next() % 1_000_000)
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    /// 4 to 12 items, so the answer indexes into the trial's own count rather
    /// than the declared `alternatives` (which is 4 — the chance level on the
    /// easiest trial, and deliberately not the same number).
    func optionCount(for trial: Trial) -> Int {
        Int(trial.payload.value("itemCount"))
    }

    /// Places the items for a trial.
    ///
    /// Rejection sampling with a retry ceiling. If the ceiling is ever hit the
    /// layout comes back SHORT, which is exactly the defect that made M12 Find
    /// It report thresholds for item counts it never displayed — so
    /// `layout(for:)` is checked by a test that demands the full count on the
    /// smallest supported field.
    func layout(for trial: Trial) -> [Item] {
        let count = Int(trial.payload.value("itemCount"))
        let targetIndex = Int(trial.payload.value("targetIndex"))
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("layoutSeed")))

        let margin = Self.itemDegrees / 2
        var positions: [CGPoint] = []
        var attempts = 0
        while positions.count < count, attempts < 4_000 {
            attempts += 1
            let x = margin + Double(generator.next() % 10_000) / 10_000.0
                * (GameField.widthDegrees - 2 * margin)
            let y = margin + Double(generator.next() % 10_000) / 10_000.0
                * (GameField.heightDegrees - 2 * margin)
            let candidate = CGPoint(x: x, y: y)
            let clear = positions.allSatisfy { existing in
                let dx = existing.x - candidate.x
                let dy = existing.y - candidate.y
                return (dx * dx + dy * dy).squareRoot() >= Self.minimumSeparationDegrees
            }
            if clear { positions.append(candidate) }
        }

        // Half the distractors carry a ring and half a dot, so neither monocular
        // view is sparse enough to make the target obvious by elimination. An
        // all-ring distractor set would mean the fellow eye saw exactly one dot
        // — and that dot IS the target.
        return positions.enumerated().map { index, position in
            if index == targetIndex {
                return Item(position: position, hasRing: true, hasDot: true)
            }
            let ringed = index % 2 == 0
            return Item(position: position, hasRing: ringed, hasDot: !ringed)
        }
    }

    /// Which item a tap landed on, or nil for a tap on empty space.
    ///
    /// A miss on empty space is NOT scored, deliberately. Punishing a stray
    /// finger would make the threshold partly a measure of dexterity.
    static func item(at point: CGPoint, in items: [Item]) -> Int? {
        let reach = itemDegrees / 2 * 1.2
        for (index, item) in items.enumerated() {
            let dx = point.x - item.position.x
            let dy = point.y - item.position.y
            if (dx * dx + dy * dy).squareRoot() <= reach { return index }
        }
        return nil
    }
}
