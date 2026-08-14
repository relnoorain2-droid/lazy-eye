//
//  CatchAndDodgeExercises.swift
//
//  G2 Sky Catch and G8 Space Dodge. Two games, one mechanic, opposite goals:
//  something falls, a bar sits at the bottom, and either they must meet or they
//  must not.
//
//  WHY THE EYE ASSIGNMENT IS OPPOSITE IN THE TWO GAMES, AND WHY THAT IS RIGHT
//  The rule is not "the moving thing goes to the amblyopic eye". The rule is
//  THE THING YOU MUST SEE goes to the amblyopic eye, and the thing you already
//  know the position of goes to the fellow eye.
//
//    Sky Catch  — the fruit falls somewhere unpredictable, so the FRUIT is the
//                 thing you must see. Fruit to the amblyopic eye, basket to the
//                 fellow eye.
//    Space Dodge — you are steering the ship, so you know where the ship is
//                 whether you can see it or not. The OBSTACLES are the thing you
//                 must see. Obstacles to the amblyopic eye, ship to the fellow.
//
//  Get Space Dodge the other way round and a suppressing user simply steers by
//  feel and never looks: the ship is where their finger is, and the obstacles
//  they can see clearly in their good eye. The game would play beautifully and
//  train nothing. This is the same failure the whole dichoptic track is designed
//  around, and it is invisible from a screenshot.
//
//  docs/03-EXERCISE-CATALOG.md G2, G8.
//

import CoreGraphics
import Foundation

// MARK: - G2 Sky Catch

struct SkyCatchExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "g.skyCatch",
        title: "Sky Catch",
        track: .game,
        evidenceTier: .a,
        summary: "Catch the falling fruit in your basket. One eye sees the fruit, the other sees the basket.",
        targets: "Both eyes working together, with a simple catch-and-move game",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.25,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            alternatives: 2
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.15
        ),
        isFreeTier: false,
        minimumAgeGroup: .underFive
    )

    /// 1.6°, matching Balloon Pop: 48 pt on an iPhone SE, past Apple's 44 pt
    /// touch minimum. A smaller fruit is missed with fingers, not eyes.
    static let fruitDegrees: Double = 1.6
    /// A wide basket, because this is the under-five game. Catching is meant to
    /// be possible; SEEING is what is being measured.
    static let basketWidthDegrees: Double = 3.0
    static let basketThicknessDegrees: Double = 0.8
    static var basketY: Double { GameField.heightDegrees - 1.2 }

    /// Slower than the adult games, same reasoning as G1.
    static let maximumFallSpeed: Double = 6.0

    static func fallSpeed(for difficulty: GameDifficulty) -> Double {
        min(difficulty.speedDegreesPerSecond, maximumFallSpeed)
    }

    static func secondsToFall(for difficulty: GameDifficulty) -> Double {
        GameField.heightDegrees / fallSpeed(for: difficulty)
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let margin = Self.fruitDegrees / 2
        let span = GameField.widthDegrees - 2 * margin
        let x = margin + Double(generator.next() % 1_000) / 1_000.0 * span
        return Trial(
            difficulty: difficulty,
            correctAnswer: 1,                 // caught
            payload: TrialPayload(["contrastRatio": difficulty, "startX": x])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    func drop(for trial: Trial) -> GamePhysics.Body {
        GamePhysics.Body(
            position: CGPoint(x: trial.payload.value("startX"),
                              y: Self.fruitDegrees / 2),
            velocity: CGPoint(x: 0, y: Self.fallSpeed(for: difficulty(for: trial))),
            size: Self.fruitDegrees)
    }

    static func caught(previous: CGPoint, current: CGPoint,
                       basketCentreX: Double) -> Bool {
        let half = basketWidthDegrees / 2
        return GamePhysics.crossesBar(
            from: previous, to: current,
            radius: fruitDegrees / 2,
            barY: basketY,
            barMinX: basketCentreX - half,
            barMaxX: basketCentreX + half)
    }

    static func fellPast(_ body: GamePhysics.Body) -> Bool {
        body.position.y - body.radius > GameField.heightDegrees
    }
}

// MARK: - G8 Space Dodge

struct SpaceDodgeExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "g.spaceDodge",
        title: "Space Dodge",
        track: .game,
        evidenceTier: .a,
        summary: "Steer your ship around the rocks. One eye sees the rocks, the other sees the ship.",
        targets: "Both eyes working together, with a steering game for older children",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            // Dodged or hit.
            alternatives: 2
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.20
        ),
        isFreeTier: false,
        // 8+ in the catalogue; the app's nearest band is 5-12, and the steering
        // demand keeps it out of the under-five list.
        minimumAgeGroup: .fiveToTwelve
    )

    static let rockDegrees: Double = 1.4
    static let shipWidthDegrees: Double = 1.8
    static let shipThicknessDegrees: Double = 0.8
    static var shipY: Double { GameField.heightDegrees - 1.2 }

    /// Faster than the under-five games but still inside the pursuit ceiling.
    static let maximumFallSpeed: Double = 10.0

    static func fallSpeed(for difficulty: GameDifficulty) -> Double {
        min(difficulty.speedDegreesPerSecond, maximumFallSpeed)
    }

    static func secondsToFall(for difficulty: GameDifficulty) -> Double {
        GameField.heightDegrees / fallSpeed(for: difficulty)
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let margin = Self.rockDegrees / 2
        let span = GameField.widthDegrees - 2 * margin
        let x = margin + Double(generator.next() % 1_000) / 1_000.0 * span
        return Trial(
            difficulty: difficulty,
            // DODGED is the correct answer, so the scoring is inverted relative
            // to Sky Catch. Getting this backwards would train a user to fly
            // into the rocks, and the staircase would faithfully find the
            // contrast at which they hit four in five.
            correctAnswer: 1,
            payload: TrialPayload(["contrastRatio": difficulty, "startX": x])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    func rock(for trial: Trial) -> GamePhysics.Body {
        GamePhysics.Body(
            position: CGPoint(x: trial.payload.value("startX"),
                              y: Self.rockDegrees / 2),
            velocity: CGPoint(x: 0, y: Self.fallSpeed(for: difficulty(for: trial))),
            size: Self.rockDegrees)
    }

    /// True when the rock reached the ship's line while the ship was under it.
    /// A hit — which is the FAILURE here.
    static func struckShip(previous: CGPoint, current: CGPoint,
                           shipCentreX: Double) -> Bool {
        let half = shipWidthDegrees / 2
        return GamePhysics.crossesBar(
            from: previous, to: current,
            radius: rockDegrees / 2,
            barY: shipY,
            barMinX: shipCentreX - half,
            barMaxX: shipCentreX + half)
    }

    static func passedSafely(_ body: GamePhysics.Body) -> Bool {
        body.position.y - body.radius > GameField.heightDegrees
    }
}
