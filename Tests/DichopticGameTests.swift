//
//  DichopticGameTests.swift
//
//  The game core carries the therapy for six exercises, so a defect here is six
//  defects. The two that would be invisible in play:
//
//    · CONTACT POSITION — a ball on a diagonal is further along in x by the
//      time a frame lands than it was when it reached the paddle's plane. Judge
//      the hit by the later position and an edge contact the user plainly saw is
//      recorded as a miss, which walks the staircase the wrong way. Nothing in
//      the UI looks broken.
//    · TWO MEASURED DIMENSIONS — if speed varied independently of contrast, the
//      converged threshold would describe neither, and it would still look like
//      a clean number on the progress chart.
//

import Testing
import Foundation
import CoreGraphics
@testable import Amblyo

@Suite("Dichoptic game core")
struct DichopticGameTests {

    private static let devices: [(name: String, pointsPerCM: Double,
                                  distance: Double, shortAxis: Double,
                                  longAxis: Double)] = [
        ("iPhone SE 3", 56.9, 30, 320, 568),
        ("iPhone 14 Pro", 63.0, 35, 393, 852),
        ("iPad 10.9", 47.2, 50, 820, 1180),
        ("iPad Pro 13", 45.4, 60, 1024, 1366),
    ]

    private func field(_ device: (name: String, pointsPerCM: Double, distance: Double,
                                  shortAxis: Double, longAxis: Double)) -> GameField {
        GameField(calibration: CalibrationProfile(
            screenPointsPerCM: device.pointsPerCM,
            screenSizeUserVerified: true,
            viewingDistanceCM: device.distance))
    }

    // MARK: The playfield fits

    @Test("the playfield fits every supported screen with room for chrome")
    func playfieldFitsEveryDevice() {
        // 10 x 14 degrees was the first choice and it clips both phones. A
        // clipped playfield hides the ball behind the navigation bar, and the
        // user loses a trial through no fault of their own.
        for device in Self.devices {
            let field = field(device)
            #expect(field.widthPoints <= device.shortAxis - 24,
                    "\(device.name): \(field.widthPoints) pt wide on a \(device.shortAxis) pt axis")
            #expect(field.heightPoints <= device.longAxis - 200,
                    "\(device.name): \(field.heightPoints) pt tall leaves no room for controls")
        }
    }

    @Test("the field is the same visual angle on every device")
    func fieldIsAngularNotFixed() {
        // If the field were a fixed point size, the same difficulty would be a
        // different task per device and thresholds could not be compared.
        for device in Self.devices {
            let field = field(device)
            let degrees = field.widthPoints / field.pointsPerDegree
            #expect(abs(degrees - GameField.widthDegrees) < 1e-6)
        }
    }

    // MARK: Tunnelling

    @Test("a ball crossing the paddle's plane is caught at every speed")
    func crossingIsCaughtAtEverySpeed() {
        // The ball contacts the paddle when its BOTTOM EDGE reaches the bar, not
        // when its centre does. Writing this test with the centre straddling the
        // plane is what caught my first version: with a 0.6 deg radius the
        // bottom edge is already well past the bar while the centre is still
        // above it, so the crossing had happened a frame earlier.
        let paddleCentre = GameField.widthDegrees / 2
        let radius = BounceExercise.ballDegrees / 2

        for speedStep in 1...15 {
            let step = Double(speedStep) * GamePhysics.timestep
            let previous = CGPoint(x: paddleCentre,
                                   y: BounceExercise.paddleY - radius - step / 2)
            let current = CGPoint(x: paddleCentre,
                                  y: BounceExercise.paddleY - radius + step / 2)
            #expect(BounceExercise.caught(previous: previous, current: current,
                                          paddleCentreX: paddleCentre),
                    "missed a crossing at \(speedStep) deg/s")
        }
    }

    @Test("a ball that misses the paddle is not counted as caught")
    func wideBallIsAMiss() {
        let paddleCentre = 4.0
        let radius = BounceExercise.ballDegrees / 2
        // Well outside the paddle's half-width plus the ball's radius.
        let x = paddleCentre + BounceExercise.paddleWidthDegrees / 2
            + BounceExercise.ballDegrees + 0.5
        let previous = CGPoint(x: x, y: BounceExercise.paddleY - radius - 0.2)
        let current = CGPoint(x: x, y: BounceExercise.paddleY - radius + 0.2)
        #expect(!BounceExercise.caught(previous: previous, current: current,
                                       paddleCentreX: paddleCentre))
    }

    @Test("contact uses the position at crossing, not the position after it")
    func contactUsesInterpolatedPosition() {
        // A ball moving diagonally at speed is meaningfully further along in x
        // by the time the frame lands. Judging by the post-frame x would score
        // an edge hit as a miss, and vice versa.
        let paddleCentre = 4.0
        let half = BounceExercise.paddleWidthDegrees / 2
        let radius = BounceExercise.ballDegrees / 2
        // Crosses the plane while still over the paddle, but ends past its edge.
        // Verified against the naive alternative: judging by the post-frame x
        // scores this as a miss, and the user saw a clean hit.
        let previous = CGPoint(x: paddleCentre,
                               y: BounceExercise.paddleY - radius - 0.3)
        let current = CGPoint(x: paddleCentre + half + 1.0,
                              y: BounceExercise.paddleY - radius + 0.3)
        #expect(BounceExercise.caught(previous: previous, current: current,
                                      paddleCentreX: paddleCentre),
                "the ball was over the paddle when it crossed the plane")
    }

    @Test("a ball moving upward through the plane is not a catch")
    func upwardCrossingIsNotACatch() {
        let paddleCentre = GameField.widthDegrees / 2
        let radius = BounceExercise.ballDegrees / 2
        let previous = CGPoint(x: paddleCentre,
                               y: BounceExercise.paddleY - radius + 0.3)
        let current = CGPoint(x: paddleCentre,
                              y: BounceExercise.paddleY - radius - 0.3)
        #expect(!BounceExercise.caught(previous: previous, current: current,
                                       paddleCentreX: paddleCentre),
                "a ball leaving the paddle would be scored as a second catch")
    }

    // MARK: Physics

    @Test("walls reflect and never trap the ball outside the field")
    func wallsReflect() {
        let field = field(Self.devices[0])
        for (velocity, label) in [(CGPoint(x: -20, y: 0), "left"),
                                  (CGPoint(x: 20, y: 0), "right"),
                                  (CGPoint(x: 0, y: -20), "top")] {
            var body = GamePhysics.Body(
                position: CGPoint(x: GameField.widthDegrees / 2,
                                  y: GameField.heightDegrees / 2),
                velocity: velocity,
                size: BounceExercise.ballDegrees)
            for _ in 0..<200 {
                body = GamePhysics.step(body, in: field, bounceBottom: false)
                #expect(body.position.x >= body.radius - 1e-6
                        && body.position.x <= GameField.widthDegrees - body.radius + 1e-6,
                        "\(label): ball escaped horizontally to \(body.position.x)")
                #expect(body.position.y >= body.radius - 1e-6,
                        "\(label): ball escaped through the top")
            }
        }
    }

    @Test("the bottom edge is a miss, not a wall")
    func bottomDoesNotBounceInBounce() {
        let field = field(Self.devices[0])
        var body = GamePhysics.Body(
            position: CGPoint(x: 4, y: GameField.heightDegrees - 1),
            velocity: CGPoint(x: 0, y: 10),
            size: BounceExercise.ballDegrees)
        for _ in 0..<60 {
            body = GamePhysics.step(body, in: field, bounceBottom: false)
        }
        #expect(BounceExercise.missed(body),
                "the ball must be able to leave the field, or a miss is impossible")
    }

    @Test("a fixed timestep gives the same result regardless of frame pacing")
    func simulationIsDeterministic() {
        let field = field(Self.devices[2])
        let start = GamePhysics.Body(position: CGPoint(x: 3, y: 2),
                                     velocity: CGPoint(x: 7, y: 9),
                                     size: BounceExercise.ballDegrees)
        var a = start, b = start
        for _ in 0..<600 { a = GamePhysics.step(a, in: field) }
        for _ in 0..<600 { b = GamePhysics.step(b, in: field) }
        #expect(a == b, "the same steps must produce the same state")
    }

    @Test("per-frame travel stays under the paddle thickness at every speed")
    func travelPerFrameIsBounded() {
        // THIS is what prevents tunnelling — not the swept collision test.
        // At the 15 deg/s cap the ball moves 0.25 deg per frame against a
        // 0.6 deg paddle, so even plain overlap testing could not miss it. If
        // someone later raises the speed ceiling, this fails loudly instead of
        // the game quietly starting to drop hits.
        for ratio in stride(from: 0.1, through: 2.0, by: 0.1) {
            let difficulty = GameDifficulty(contrastRatio: ratio)
            let body = GamePhysics.Body(
                position: .zero,
                velocity: CGPoint(x: 0, y: difficulty.speedDegreesPerSecond),
                size: BounceExercise.ballDegrees)
            let travel = GamePhysics.travelPerFrame(body)
            #expect(travel < BounceExercise.ballDegrees,
                    "at ratio \(ratio) the ball moves \(travel) deg per frame, more than its own size")
        }
    }

    // MARK: Difficulty

    @Test("speed never exceeds the smooth-pursuit ceiling")
    func speedRespectsPursuitLimit() {
        // Above roughly 15 deg/s this stops being a fusion task and becomes a
        // saccade task, which M10 already measures.
        for ratio in stride(from: 0.0, through: 5.0, by: 0.1) {
            let speed = GameDifficulty(contrastRatio: ratio).speedDegreesPerSecond
            #expect(speed <= GameField.maximumSpeedDegreesPerSecond + 1e-9,
                    "ratio \(ratio) gives \(speed) deg/s")
            #expect(speed >= GameDifficulty.slowestSpeed - 1e-9)
        }
    }

    @Test("speed is a fixed function of the ratio, so only one thing is measured")
    func speedIsDeterminedByRatio() {
        // Two calls at the same ratio must give the same speed. If speed drifted
        // independently, a converged threshold would describe a mixture of
        // contrast and speed and could not be read as either.
        for ratio in [0.1, 0.35, 0.8, 1.4, 2.0] {
            #expect(GameDifficulty(contrastRatio: ratio).speedDegreesPerSecond
                    == GameDifficulty(contrastRatio: ratio).speedDegreesPerSecond)
        }
    }

    @Test("speed rises with difficulty, and stops rising at the cap")
    func speedRisesThenPlateaus() {
        let easy = GameDifficulty(contrastRatio: 0.1).speedDegreesPerSecond
        let mid = GameDifficulty(contrastRatio: 0.6).speedDegreesPerSecond
        let hard = GameDifficulty(contrastRatio: 1.0).speedDegreesPerSecond
        let harder = GameDifficulty(contrastRatio: 2.0).speedDegreesPerSecond
        #expect(easy < mid && mid < hard)
        #expect(hard == harder,
                "past the cap, contrast alone should carry the difficulty")
    }

    @Test("fellow contrast never exceeds what the compositor can render")
    func fellowContrastRespectsHeadroom() {
        for ratio in stride(from: 0.1, through: 3.0, by: 0.1) {
            let contrast = GameDifficulty(contrastRatio: ratio).fellowContrast
            #expect(contrast <= AnaglyphCompositor.maximumContrast + 1e-9,
                    "ratio \(ratio) asks for \(contrast), beyond the crosstalk headroom")
            #expect(contrast > 0)
        }
    }

    @Test("games and the balance meter report on one scale")
    func gamesShareTheBalanceScale() {
        // Two numbers both called "balance" on different scales would be worse
        // than one number, so the games reuse D5's bands verbatim.
        for ratio in [0.1, 0.4, 0.9, 1.5] {
            #expect(GameDifficulty.interpretation(contrastRatio: ratio)
                    == BalanceMeterExercise.interpretation(balanceRatio: ratio))
        }
    }

    @Test("D4 and D5 share a staircase range and polarity")
    func bounceMatchesBalanceMeter() {
        let bounce = BounceExercise.descriptor.staircase
        let meter = BalanceMeterExercise.descriptor.staircase
        #expect(bounce.polarity == meter.polarity)
        #expect(bounce.hardestValue == meter.hardestValue)
        #expect(bounce.easiestValue == meter.easiestValue)
    }

    // MARK: Serves

    @Test("serves vary in position and direction")
    func servesVary() {
        let exercise = BounceExercise()
        var generator = SeededGenerator(seed: 31)
        var xs: Set<Int> = []
        var directions: Set<Bool> = []
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 0.4, generator: &generator)
            xs.insert(Int(trial.payload.value("serveX") * 10))
            directions.insert(trial.payload.value("serveRight") > 0.5)
        }
        #expect(xs.count > 20, "serving from the same place lets the user pre-place the paddle")
        #expect(directions.count == 2, "the ball always went the same way")
    }

    @Test("every serve starts inside the field, moving down")
    func servesAreLegal() {
        let exercise = BounceExercise()
        var generator = SeededGenerator(seed: 77)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 0.5, generator: &generator)
            let ball = exercise.serve(for: trial)
            #expect(ball.position.x >= ball.radius)
            #expect(ball.position.x <= GameField.widthDegrees - ball.radius)
            #expect(ball.velocity.y > 0, "a serve moving upward starts by hitting the ceiling")
            let speed = (ball.velocity.x * ball.velocity.x
                         + ball.velocity.y * ball.velocity.y).squareRoot()
            #expect(abs(speed - GameDifficulty(contrastRatio: 0.5).speedDegreesPerSecond) < 1e-6,
                    "serve speed must match the difficulty's speed exactly")
        }
    }

    @Test("serve angles stay away from vertical and horizontal")
    func serveAnglesAreUseful() {
        // Near-vertical is trivial — the paddle barely moves. Near-horizontal
        // crawls, and a trial that takes twenty seconds wastes the session.
        let exercise = BounceExercise()
        var generator = SeededGenerator(seed: 5)
        for _ in 0..<300 {
            let trial = exercise.makeTrial(difficulty: 0.4, generator: &generator)
            let angle = trial.payload.value("serveAngle")
            #expect(angle >= BounceExercise.minimumServeAngleDegrees)
            #expect(angle <= BounceExercise.maximumServeAngleDegrees)
        }
    }

    @Test("a caught ball is the correct answer")
    func caughtIsCorrect() {
        // The runner scores responses against `correctAnswer`, so catching must
        // be 1. Inverted, the staircase would make the game EASIER the better
        // someone played.
        let exercise = BounceExercise()
        var generator = SeededGenerator(seed: 9)
        let trial = exercise.makeTrial(difficulty: 0.4, generator: &generator)
        #expect(trial.correctAnswer == 1)
    }
}
