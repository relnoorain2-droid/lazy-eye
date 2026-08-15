//
//  SplitMatchExercise.swift
//
//  D2 Split Match. A matching task where each card's identity is split down the
//  middle between the two eyes.
//
//  THE MECHANIC
//  Every card carries two halves of a symbol: the LEFT half is drawn only to the
//  amblyopic eye, the RIGHT half only to the fellow eye. A card's identity is the
//  PAIR. One target card sits at the top; the user picks the option below that
//  matches it.
//
//  WHY THE DISTRACTORS MATTER MORE THAN THE TARGET
//  Every distractor matches the target on exactly ONE half. So with either eye
//  closed, several options look right — the correct one is not merely harder to
//  spot, it is indistinguishable from its neighbours. Fill the distractors
//  randomly instead and roughly half of them would differ in both halves, which
//  would let one eye eliminate enough options to guess well. That is the
//  difference between a dichoptic task and a task that merely uses two colours,
//  and it is entirely invisible from a screenshot.
//
//  A CONSEQUENCE WORTH STATING: HALF THE DISTRACTORS MATCH ON EACH SIDE
//  If every distractor matched the target's left half, the amblyopic eye would
//  see all options as identical and the fellow eye would see exactly one match —
//  handing the answer to the fellow eye alone. The split has to be even.
//
//  docs/03-EXERCISE-CATALOG.md D2.
//

import Foundation

struct SplitMatchExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.dichopticMatch",
        title: "Split Match",
        track: .dichoptic,
        evidenceTier: .a,
        summary: "Each card is half-drawn to each eye. Find the card that matches the one at the top.",
        targets: "Joining what each eye sees into a single picture",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            // Chance is set by the EASIEST trial, as in D9: fewest options means
            // the highest a guesser's success rate ever reaches.
            alternatives: minimumOptions
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

    /// Half-symbols available for each side. Four of each gives sixteen possible
    /// cards, which is ample: with six options on screen there is never a need
    /// to repeat a card within a trial.
    static let halfCount: Int = 4

    static let minimumOptions: Int = 3
    static let maximumOptions: Int = 6

    /// Option count rises with the ratio on a fixed schedule, so it never
    /// becomes a second measured dimension.
    static func optionCount(for difficulty: GameDifficulty) -> Int {
        let progress = min(max(difficulty.contrastRatio / 1.0, 0), 1)
        let span = Double(maximumOptions - minimumOptions)
        return minimumOptions + Int((span * progress).rounded())
    }

    /// A card is a pair of half-symbol indices: one per eye.
    struct Card: Sendable, Equatable {
        /// Drawn to the amblyopic eye.
        let leftHalf: Int
        /// Drawn to the fellow eye.
        let rightHalf: Int
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let level = GameDifficulty(contrastRatio: difficulty)
        let count = Self.optionCount(for: level)
        let answer = Int(generator.next() % UInt64(count))
        let target = Card(leftHalf: Int(generator.next() % UInt64(Self.halfCount)),
                          rightHalf: Int(generator.next() % UInt64(Self.halfCount)))

        return Trial(
            difficulty: difficulty,
            correctAnswer: answer,
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "optionCount": Double(count),
                "answerIndex": Double(answer),
                "targetLeft": Double(target.leftHalf),
                "targetRight": Double(target.rightHalf),
                "layoutSeed": Double(generator.next() % 1_000_000)
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    /// 3 to 6 cards. `alternatives` stays at 3 for the chance level.
    func optionCount(for trial: Trial) -> Int {
        Int(trial.payload.value("optionCount"))
    }

    func target(for trial: Trial) -> Card {
        Card(leftHalf: Int(trial.payload.value("targetLeft")),
             rightHalf: Int(trial.payload.value("targetRight")))
    }

    /// The options, in display order.
    ///
    /// Every distractor matches the target on EXACTLY ONE half, and the halves
    /// alternate so neither eye sees a unique match. Two distractors are never
    /// identical to each other either — duplicates would silently reduce the
    /// number of distinguishable options below what the difficulty called for.
    func options(for trial: Trial) -> [Card] {
        let count = Int(trial.payload.value("optionCount"))
        let answer = Int(trial.payload.value("answerIndex"))
        let target = target(for: trial)
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("layoutSeed")))

        var cards: [Card] = []
        var used: Set<String> = ["\(target.leftHalf),\(target.rightHalf)"]
        var matchLeftNext = true

        for index in 0..<count {
            if index == answer {
                cards.append(target)
                continue
            }
            // Alternate which half matches, so neither monocular view contains a
            // unique candidate.
            var card: Card?
            for _ in 0..<64 where card == nil {
                let other = Int(generator.next() % UInt64(Self.halfCount))
                let candidate = matchLeftNext
                    ? Card(leftHalf: target.leftHalf, rightHalf: other)
                    : Card(leftHalf: other, rightHalf: target.rightHalf)
                let key = "\(candidate.leftHalf),\(candidate.rightHalf)"
                if !used.contains(key) {
                    used.insert(key)
                    card = candidate
                }
            }
            // Falls back to the first unused pair rather than repeating one:
            // a duplicate option would mean two identical cards on screen and
            // an unanswerable trial.
            if card == nil {
                outer: for left in 0..<Self.halfCount {
                    for right in 0..<Self.halfCount {
                        let key = "\(left),\(right)"
                        if !used.contains(key) {
                            used.insert(key)
                            card = Card(leftHalf: left, rightHalf: right)
                            break outer
                        }
                    }
                }
            }
            if let card {
                cards.append(card)
                matchLeftNext.toggle()
            }
        }
        return cards
    }
}
