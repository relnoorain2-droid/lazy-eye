//
//  BalloonPopExercise.swift
//
//  G1 Balloon Pop. The same dichoptic mechanic as D3 and D4, dressed as a game a
//  four-year-old will sit through: balloons drift up from the bottom and must be
//  tapped before they leave the top.
//
//  THE BALLOON IS THE AMBLYOPIC EYE'S, THE SKY IS THE FELLOW EYE'S
//  Identical logic to Bounce. The thing you must find and act on is the one the
//  weak eye carries, so a suppressing user cannot play. Dressing it up does not
//  change the therapy — which is why this is tier A in dichoptic mode and tier C
//  in the monocular fallback, and the badge says so.
//
//  THE BALLOON IS 1.6 DEGREES BECAUSE OF A FINGERTIP, NOT AN EYE
//  Apple's minimum touch target is 44 points. On an iPhone SE, 44 points is 1.48
//  degrees. A smaller balloon would be missed for MOTOR reasons — a four-year-old
//  stabbing at a small target — and the app would record that as a suppression
//  failure and make the next trial easier. 1.6 degrees clears the minimum on
//  every supported screen with a margin.
//
//  WHY UNDER-FIVES GET THIS AND NOT BOUNCE
//  Bounce needs sustained tracking with a dragged paddle. This needs one tap at
//  a large, slow target. Same measurement, lower motor floor.
//
//  docs/03-EXERCISE-CATALOG.md G1.
//

import CoreGraphics
import Foundation

struct BalloonPopExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "g.balloonPop",
        title: "Balloon Pop",
        track: .game,
        // Tier A as a dichoptic exercise: it is the contrast-rebalance mechanic
        // wearing a costume. The monocular fallback is tier C and labelled so.
        evidenceTier: .a,
        summary: "Pop the balloons before they float away. One eye sees the balloons, the other sees the sky.",
        targets: "Both eyes working together, for younger children",
        defaultDurationSeconds: 180,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.25,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            // Popped or missed.
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

    /// 1.6°: 48 pt on an iPhone SE, comfortably past Apple's 44 pt touch
    /// minimum. Below that, misses are about fingers rather than eyes.
    static let balloonDegrees: Double = 1.6

    /// Kids' games run slower than the adult ones. The shared ramp tops out at
    /// 15 deg/s; a balloon crossing the field in under a second is not a game a
    /// small child can play, and the failures would be motor again.
    static let maximumRiseSpeed: Double = 6.0

    static func riseSpeed(for difficulty: GameDifficulty) -> Double {
        min(difficulty.speedDegreesPerSecond, maximumRiseSpeed)
    }

    /// How long a balloon is on screen. The floor that keeps this playable.
    static func secondsOnScreen(for difficulty: GameDifficulty) -> Double {
        GameField.heightDegrees / riseSpeed(for: difficulty)
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        // Horizontal position anywhere the whole balloon fits.
        let margin = Self.balloonDegrees / 2
        let span = GameField.widthDegrees - 2 * margin
        let x = margin + Double(generator.next() % 1_000) / 1_000.0 * span
        // A gentle sideways drift so it is not a straight vertical line every
        // time — a fixed path lets a child pre-place their finger and wait.
        let drift = (Double(generator.next() % 1_000) / 1_000.0 - 0.5) * 2.0

        return Trial(
            difficulty: difficulty,
            // Popped is 1.
            correctAnswer: 1,
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "startX": x,
                "drift": drift
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    /// A balloon's opening state: bottom of the field, rising.
    func launch(for trial: Trial) -> GamePhysics.Body {
        let difficulty = difficulty(for: trial)
        return GamePhysics.Body(
            position: CGPoint(x: trial.payload.value("startX"),
                              y: GameField.heightDegrees - Self.balloonDegrees / 2),
            // Negative y is upward: the field's origin is its top-left.
            velocity: CGPoint(x: trial.payload.value("drift"),
                              y: -Self.riseSpeed(for: difficulty)),
            size: Self.balloonDegrees)
    }

    /// True once the balloon has left through the top and the trial is a miss.
    static func escaped(_ body: GamePhysics.Body) -> Bool {
        body.position.y + body.radius < 0
    }

    /// Did a tap at this point pop the balloon?
    ///
    /// Generous by a quarter of the balloon's size, deliberately. A child's tap
    /// lands near the target rather than on it, and this exercise is measuring
    /// whether they SAW the balloon, not how precisely they can point.
    static func popped(tapAt point: CGPoint, balloon: GamePhysics.Body) -> Bool {
        let dx = point.x - balloon.position.x
        let dy = point.y - balloon.position.y
        let reach = balloon.radius * 1.25
        return (dx * dx + dy * dy).squareRoot() <= reach
    }
}
