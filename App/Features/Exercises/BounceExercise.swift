//
//  BounceExercise.swift
//
//  D4 Bounce. Breakout, split between the eyes: the BALL goes to the amblyopic
//  eye, the paddle and bricks to the fellow eye.
//
//  WHY THAT ASSIGNMENT AND NOT THE REVERSE
//  The ball is the thing you must not lose sight of. Putting it in the amblyopic
//  eye means the game is unplayable while that eye is suppressed — which is the
//  forcing function, and the entire reason this is therapy rather than a game
//  with a red-cyan filter over it. Reversed, a suppressing user would track the
//  ball comfortably with their good eye and the session would train nothing.
//
//  A SCORE, NOT AN ACCURACY
//  Every other exercise here answers "was that trial right?". This one cannot:
//  play is continuous, and a miss at high speed is not the same evidence as a
//  miss at low speed. So a TRIAL here is one ball — served, played, and ended by
//  a hit or a miss — and the staircase reads hits and misses exactly as it reads
//  correct and incorrect answers elsewhere. That keeps one staircase
//  implementation for the whole app rather than a second one for games, and the
//  3-down/1-up rule means the ratio settles where the user catches about four
//  balls in five.
//
//  WHAT THE THRESHOLD MEANS
//  The same thing D5's does: the interocular contrast ratio at which the two eyes
//  contribute about equally. It is deliberately reported on D5's bands, because
//  two numbers on different scales both called "balance" would be worse than one.
//
//  docs/03-EXERCISE-CATALOG.md D4.
//

import CoreGraphics
import Foundation

struct BounceExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.breakout",
        title: "Bounce",
        track: .dichoptic,
        evidenceTier: .a,
        summary: "Keep the ball in play. One eye sees the ball, the other sees the paddle — so you need both.",
        targets: "Both eyes working together while you concentrate on something else",
        defaultDurationSeconds: 300,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            // Same range and polarity as D5, so the two exercises report a
            // number on one scale. Low ratio = faint paddle = easy.
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            // A ball is caught or missed. Two outcomes, so chance is 50% and the
            // staircase's guess correction is the same as any 2AFC exercise.
            alternatives: 2
        ),
        safety: SafetyEnvelope(
            // Smooth translation. Nothing oscillates in luminance, and the ball
            // never flashes — the brick flash on a hit is a one-off transition,
            // not a repeating rate.
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.20
        ),
        isFreeTier: false,
        // Needs sustained attention and a steady hand. Under-fives get the kids
        // games instead, which are the same mechanic with a lower floor.
        minimumAgeGroup: .fiveToTwelve
    )

    // MARK: Geometry, in degrees

    /// 1.2° — large enough for an amblyopic eye to track, small enough that
    /// losing it is a real possibility rather than a formality.
    static let ballDegrees: Double = 1.2
    /// 2.4° wide, 0.6° thick. The thickness matters: see `crossesBar`.
    static let paddleWidthDegrees: Double = 2.4
    static let paddleThicknessDegrees: Double = 0.6
    /// Paddle sits this far above the bottom edge.
    static let paddleInsetDegrees: Double = 0.9

    static var paddleY: Double {
        GameField.heightDegrees - paddleInsetDegrees
    }

    /// Serve angle range, measured from straight down. Never near-vertical
    /// (trivial: the paddle barely moves) and never near-horizontal (the ball
    /// crawls down and the trial takes forever).
    static let minimumServeAngleDegrees: Double = 25
    static let maximumServeAngleDegrees: Double = 55

    // MARK: Trials

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        // Serve from a random x in the middle half of the field, angled left or
        // right at random. Serving from centre every time lets a user pre-place
        // the paddle and stop tracking.
        let spread = GameField.widthDegrees / 2
        let x = GameField.widthDegrees / 4
            + Double(generator.next() % 1_000) / 1_000.0 * spread
        let angleSpan = Self.maximumServeAngleDegrees - Self.minimumServeAngleDegrees
        let angle = Self.minimumServeAngleDegrees
            + Double(generator.next() % 1_000) / 1_000.0 * angleSpan
        let goingRight = generator.next() % 2 == 0

        return Trial(
            difficulty: difficulty,
            // "Caught" is answer 1, "missed" is 0. The runner scores a response
            // against this, so a caught ball must be reported as 1.
            correctAnswer: 1,
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "serveX": x,
                "serveAngle": angle,
                "serveRight": goingRight ? 1 : 0
            ])
        )
    }

    /// The ball's opening state for a trial.
    func serve(for trial: Trial) -> GamePhysics.Body {
        let difficulty = GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
        let speed = difficulty.speedDegreesPerSecond
        let angle = trial.payload.value("serveAngle") * .pi / 180
        let goingRight = trial.payload.value("serveRight") > 0.5

        return GamePhysics.Body(
            position: CGPoint(x: trial.payload.value("serveX"), y: Self.ballDegrees),
            velocity: CGPoint(x: (goingRight ? 1 : -1) * speed * sin(angle),
                              y: speed * cos(angle)),
            size: Self.ballDegrees)
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    /// Did this ball reach the paddle, given where the paddle was?
    ///
    /// Takes BOTH the previous and current position rather than only the current
    /// one, so contact is judged at the x the ball HAD when it reached the
    /// paddle's plane. At 15 deg/s it travels about 12 points between frames on
    /// an iPad; on a diagonal, that is enough to be over the paddle at contact
    /// and past its edge by the time the frame lands. Judging by the later
    /// position tells a user who saw a clean hit that they missed.
    static func caught(previous: CGPoint, current: CGPoint,
                       paddleCentreX: Double) -> Bool {
        let half = paddleWidthDegrees / 2
        return GamePhysics.crossesBar(
            from: previous, to: current,
            radius: ballDegrees / 2,
            barY: paddleY,
            barMinX: paddleCentreX - half,
            barMaxX: paddleCentreX + half)
    }

    /// True once the ball is past the paddle and gone.
    static func missed(_ body: GamePhysics.Body) -> Bool {
        body.position.y - body.radius > GameField.heightDegrees
    }
}
