//
//  StarTracerAndViewingExercises.swift
//
//  G5 Star Tracer and D1 Balanced Viewing — the last two of Phase 8.
//
//  D1 IS THE FLAGSHIP, AND IT IS ALSO THE ONE MOST EASILY BUILT DISHONESTLY
//  The catalogue describes it as any user-chosen video rendered with contrast
//  rebalanced between the eyes: the closest legal analogue to the
//  contrast-rebalanced-movie trials. Two ways to build that, and the choice
//  matters beyond engineering:
//
//    Photos library — needs `NSPhotoLibraryUsageDescription`, an App Review
//        explanation of why an eye-training app reads your photos, and a
//        video pipeline that composites per frame. Real work, real review risk,
//        and a permission prompt in front of a therapeutic feature.
//    A procedural scene — no permission, no assets, ships today, and delivers
//        the actual mechanism (sustained viewing with the fellow eye's contrast
//        reduced) without any of that.
//
//  This is the procedural version. The mechanism the research describes is the
//  CONTRAST REBALANCE during sustained binocular viewing, not the presence of a
//  film, so a generated scene is not a lesser version of the therapy — it is the
//  same therapy with less to go wrong. The Photos route stays open as an
//  addition rather than a prerequisite.
//
//  AND IT STILL HAS TO BE FALSIFIABLE
//  Pure passive viewing cannot be measured: someone who puts the phone face-down
//  produces the same data as someone watching intently. So the scene pauses
//  periodically for a CHECK-IN — a symbol drawn only to the amblyopic eye, named
//  by the user. Those check-ins are the trials; the viewing between them is the
//  exercise. A user not looking fails them.
//
//  docs/03-EXERCISE-CATALOG.md D1, G5.
//

import CoreGraphics
import Foundation

// MARK: - D1 Balanced Viewing

struct BalancedViewingExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.balancedViewing",
        title: "Balanced Viewing",
        track: .dichoptic,
        evidenceTier: .a,
        summary: "A calm moving scene, dimmed for your stronger eye. Watch it, and name the shape when one appears.",
        targets: "Getting both eyes used to working together for longer stretches",
        // The longest session in the app: this one is meant to be restful.
        defaultDurationSeconds: 600,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.2,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            alternatives: 4
        ),
        safety: SafetyEnvelope(
            // Shapes drift slowly and continuously. Nothing oscillates.
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            // 0.20, and the first draft said 0.40 — above FlickerGuard's 0.35
            // photosensitivity cap, which is why the audit rejected it.
            //
            // The declaration should be measured, not guessed. 14 elements of
            // 1.2 deg across a 9x12 deg field is 14 * pi * 0.6^2 = 15.8 deg^2
            // out of 108, so 0.15 with the check-in symbol on top. 0.20 leaves
            // headroom without claiming coverage the scene never reaches: a
            // declaration is a promise the renderer is tested against, so
            // padding it is not free caution.
            maxHighContrastAreaFraction: 0.20
        ),
        isFreeTier: false,
        minimumAgeGroup: .underFive
    )

    typealias Answer = StereogramParameters.Shape

    /// Seconds of viewing between check-ins. Long enough to be restful, short
    /// enough that a user who stops looking is caught within half a minute.
    static let secondsBetweenCheckIns: Double = 25

    /// How long the check-in symbol stays up.
    static let checkInSeconds: Double = 4

    /// Drifting background elements, drawn to BOTH eyes at the rebalanced
    /// contrast. They are the scene; the check-in symbol is the measurement.
    static let sceneElementCount: Int = 14
    static let sceneElementDegrees: Double = 1.2
    static let sceneDriftDegreesPerSecond: Double = 1.5

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let shape = Answer.allCases.randomElement(using: &generator) ?? .square
        return Trial(
            difficulty: difficulty,
            correctAnswer: shape.rawValue,
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "shape": Double(shape.rawValue),
                "sceneSeed": Double(generator.next() % 1_000_000)
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    func shape(for trial: Trial) -> Answer {
        Answer(rawValue: Int(trial.payload.value("shape"))) ?? .square
    }

    /// Starting positions and velocities for the drifting scene.
    func sceneElements(for trial: Trial) -> [GamePhysics.Body] {
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("sceneSeed")))
        let margin = Self.sceneElementDegrees / 2
        return (0..<Self.sceneElementCount).map { _ in
            let x = margin + Double(generator.next() % 1_000) / 1_000.0
                * (GameField.widthDegrees - 2 * margin)
            let y = margin + Double(generator.next() % 1_000) / 1_000.0
                * (GameField.heightDegrees - 2 * margin)
            let angle = Double(generator.next() % 1_000) / 1_000.0 * 2 * .pi
            return GamePhysics.Body(
                position: CGPoint(x: x, y: y),
                velocity: CGPoint(x: cos(angle) * Self.sceneDriftDegreesPerSecond,
                                  y: sin(angle) * Self.sceneDriftDegreesPerSecond),
                size: Self.sceneElementDegrees)
        }
    }
}

// MARK: - G5 Star Tracer

/// Stars appear in a fixed order and must be tapped in that order.
///
/// THE STARS GO TO THE AMBLYOPIC EYE AND THE JOINING LINES TO THE FELLOW EYE
/// The stars are what must be found; the lines are context showing which have
/// been joined already. Reversed, the lines alone would give away where the next
/// star is and the weak eye would have nothing to do.
struct StarTracerExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "g.starTracer",
        title: "Star Tracer",
        track: .game,
        evidenceTier: .b,
        summary: "Join the stars in order. One eye sees the stars, the other sees the lines you have drawn.",
        targets: "Both eyes working together while following a path",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "balance",
            unit: "",
            startValue: 0.3,
            hardestValue: 2.0,
            easiestValue: 0.1,
            polarity: .higherIsHarder,
            // Chance is set by the number of stars on the EASIEST trial, as in
            // D9 and D2: fewest stars is the best a guesser ever does.
            alternatives: minimumStars
        ),
        safety: SafetyEnvelope(
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.20
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    /// 1.6°, the same touch floor as every other tapped target here.
    static let starDegrees: Double = 1.6
    static let minimumSeparationDegrees: Double = 2.2

    static let minimumStars: Int = 3
    static let maximumStars: Int = 7

    static func starCount(for difficulty: GameDifficulty) -> Int {
        let progress = min(max(difficulty.contrastRatio / 1.0, 0), 1)
        let span = Double(maximumStars - minimumStars)
        return minimumStars + Int((span * progress).rounded())
    }

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let level = GameDifficulty(contrastRatio: difficulty)
        return Trial(
            difficulty: difficulty,
            // COMPLETING the sequence is the correct answer, and it is reported
            // as the star COUNT — a value no individual star index can take.
            //
            // The first version used 0 for "completed", which is also the index
            // of the first star: tapping star 0 again after joining it would
            // have been scored as a success. A silent scoring bug of exactly the
            // kind this phase keeps turning up.
            correctAnswer: Self.starCount(for: level),
            payload: TrialPayload([
                "contrastRatio": difficulty,
                "starCount": Double(Self.starCount(for: level)),
                "layoutSeed": Double(generator.next() % 1_000_000)
            ])
        )
    }

    func difficulty(for trial: Trial) -> GameDifficulty {
        GameDifficulty(contrastRatio: trial.payload.value("contrastRatio"))
    }

    /// The star indices PLUS the completion value, which is why this is
    /// `count + 1` rather than `count`. The answer space here is 0..<count for
    /// the individual stars and `count` itself for "finished the sequence".
    func optionCount(for trial: Trial) -> Int {
        Int(trial.payload.value("starCount")) + 1
    }

    /// Star positions, in tap order.
    ///
    /// Same rejection sampling as Hidden Half, and the same guarantee: the full
    /// count is placed or the layout is wrong. A short layout would mean the
    /// difficulty stopped rising while the staircase kept climbing.
    func stars(for trial: Trial) -> [CGPoint] {
        let count = Int(trial.payload.value("starCount"))
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("layoutSeed")))
        let margin = Self.starDegrees / 2
        var placed: [CGPoint] = []
        var attempts = 0
        while placed.count < count, attempts < 4_000 {
            attempts += 1
            let x = margin + Double(generator.next() % 10_000) / 10_000.0
                * (GameField.widthDegrees - 2 * margin)
            let y = margin + Double(generator.next() % 10_000) / 10_000.0
                * (GameField.heightDegrees - 2 * margin)
            let candidate = CGPoint(x: x, y: y)
            let clear = placed.allSatisfy { existing in
                let dx = existing.x - candidate.x
                let dy = existing.y - candidate.y
                return (dx * dx + dy * dy).squareRoot() >= Self.minimumSeparationDegrees
            }
            if clear { placed.append(candidate) }
        }
        return placed
    }

    /// Which star a tap landed on, or nil.
    static func star(at point: CGPoint, in stars: [CGPoint]) -> Int? {
        let reach = starDegrees / 2 * 1.2
        for (index, star) in stars.enumerated() {
            let dx = point.x - star.x
            let dy = point.y - star.y
            if (dx * dx + dy * dy).squareRoot() <= reach { return index }
        }
        return nil
    }
}
