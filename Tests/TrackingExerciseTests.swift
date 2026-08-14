//
//  TrackingExerciseTests.swift
//
//  M9, M10, M11, M13, M14 — the five interactive exercises.
//
//  Two of these tests exist because of bugs found while writing them, and both
//  were unit errors invisible to the type checker: M10 asked for an eccentricity
//  three times what an iPhone SE can display, and M13's staircase was in degrees
//  while its render limit returned arcminutes.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Tracking and reading exercises")
struct TrackingExerciseTests {

    private func calibration(ppi: Double, scale: Double, cm: Double) -> CalibrationProfile {
        CalibrationProfile(screenPointsPerCM: (ppi / scale) / 2.54, viewingDistanceCM: cm)
    }
    private var iPhoneSE: CalibrationProfile { calibration(ppi: 326, scale: 2, cm: 35) }
    private var iPadPro13: CalibrationProfile { calibration(ppi: 264, scale: 2, cm: 50) }

    /// The narrowest supported window, in points.
    private let narrowestWidth: Double = 320

    // MARK: M9 · Pursuit

    @Test("The pursuit path stays inside its canvas")
    func pursuitPathStaysInBounds() {
        for profile in [iPhoneSE, iPadPro13] {
            let path = PursuitPath(speedDegreesPerSecond: 8,
                                   pointsPerDegree: profile.points(forDegrees: 1))
            let margin = path.targetDiameterPoints / 2
            for step in 0..<500 {
                let position = path.position(at: Double(step) * 0.02)
                #expect(position.x >= margin - 1 && position.x <= path.canvasPoints - margin + 1)
                #expect(position.y >= margin - 1 && position.y <= path.canvasPoints - margin + 1)
            }
        }
    }

    @Test("The pursuit canvas fits the narrowest screen")
    func pursuitCanvasFits() {
        let path = PursuitPath(speedDegreesPerSecond: 4,
                               pointsPerDegree: iPhoneSE.points(forDegrees: 1))
        #expect(path.canvasPoints <= narrowestWidth - 24,
                "canvas \(path.canvasPoints) pt overflows")
    }

    @Test("The path does not repeat quickly")
    func pursuitPathIsNotPredictable() {
        // A circle would be learnable: after one lap the eye anticipates rather
        // than pursues, which is a different oculomotor behaviour.
        let path = PursuitPath(speedDegreesPerSecond: 6,
                               pointsPerDegree: iPhoneSE.points(forDegrees: 1))
        let first = path.position(at: 0)
        var closeReturns = 0
        for step in 1..<400 {
            let position = path.position(at: Double(step) * 0.05)
            let dx = position.x - first.x, dy = position.y - first.y
            if (dx * dx + dy * dy).squareRoot() < 4 { closeReturns += 1 }
        }
        #expect(closeReturns < 30, "path returns to its start \(closeReturns) times — too predictable")
    }

    @Test("Faster settings really are faster")
    func pursuitSpeedIsMonotonic() {
        let ppd = iPhoneSE.points(forDegrees: 1)
        func travelled(at speed: Double) -> Double {
            let path = PursuitPath(speedDegreesPerSecond: speed, pointsPerDegree: ppd)
            var total = 0.0
            var previous = path.position(at: 0)
            for step in 1...200 {
                let next = path.position(at: Double(step) * 0.01)
                total += ((next.x - previous.x) * (next.x - previous.x)
                          + (next.y - previous.y) * (next.y - previous.y)).squareRoot()
                previous = next
            }
            return total
        }
        #expect(travelled(at: 8) > travelled(at: 4))
        #expect(travelled(at: 16) > travelled(at: 8))
    }

    // MARK: M10 · Saccades

    @Test("Every target lands fully inside the field")
    func saccadeTargetsStayOnScreen() {
        // THE BUG THIS CAUGHT: the ceiling was 9 degrees, which is 353 pt on an
        // iPhone SE against a maximum radius of 108 pt. The target would clamp
        // silently and the staircase would climb toward a difficulty the screen
        // never showed.
        let ceiling = JumpTargetsExercise.descriptor.staircase.hardestValue

        for (profile, field) in [(iPhoneSE, 272.0), (iPadPro13, 900.0)] {
            var generator = SeededGenerator(seed: 5)
            for id in 0..<200 {
                let target = SaccadeGenerator.makeTarget(
                    eccentricityDegrees: ceiling,
                    pointsPerDegree: profile.points(forDegrees: 1),
                    fieldPoints: field, id: id, generator: &generator)
                let r = target.diameterPoints / 2
                #expect(target.x >= r - 1 && target.x <= field - r + 1)
                #expect(target.y >= r - 1 && target.y <= field - r + 1)
            }
        }
    }

    @Test("The hardest eccentricity is achievable on the smallest screen")
    func saccadeCeilingIsReachable() {
        let ceiling = JumpTargetsExercise.descriptor.staircase.hardestValue
        let ppd = iPhoneSE.points(forDegrees: 1)
        let field = 272.0
        let diameter = max(Layout.minTouchTarget, 1.2 * ppd)
        let maximumRadius = field / 2 - diameter / 2 - 4

        #expect(ceiling * ppd <= maximumRadius,
                "ceiling \(ceiling)° = \(ceiling * ppd) pt but only \(maximumRadius) pt is available")
    }

    @Test("Targets are at least a comfortable touch size")
    func saccadeTargetsAreTappable() {
        var generator = SeededGenerator(seed: 9)
        let target = SaccadeGenerator.makeTarget(
            eccentricityDegrees: 2, pointsPerDegree: iPhoneSE.points(forDegrees: 1),
            fieldPoints: 272, id: 0, generator: &generator)
        #expect(target.diameterPoints >= Layout.minTouchTarget)
    }

    // MARK: M11 · Hart chart

    @Test("The grid fits the narrowest screen at maximum density")
    func hartChartFits() {
        let exercise = HartChartExercise()
        var generator = SeededGenerator(seed: 3)
        let trial = exercise.makeTrial(
            difficulty: HartChartExercise.descriptor.staircase.hardestValue,
            generator: &generator)
        let chart = exercise.chart(for: trial, calibration: iPhoneSE, generator: &generator)

        #expect(chart.widthPoints <= narrowestWidth - 24,
                "grid is \(chart.widthPoints) pt wide")
        #expect(chart.cellPoints >= 24, "cells are too small to tap")
    }

    @Test("The call-out sequence is a contiguous row")
    func hartSequenceIsARow() {
        // A scattered sequence would make this a search task — that is M12.
        var generator = SeededGenerator(seed: 12)
        for _ in 0..<50 {
            let chart = HartChartGenerator.make(
                columns: 6, rows: 5, letterHeightPoints: 20,
                sequenceLength: 5, generator: &generator)
            let sequence = chart.sequence
            #expect(sequence.count == 5)
            for index in 1..<sequence.count {
                #expect(sequence[index] == sequence[index - 1] + 1,
                        "sequence \(sequence) is not contiguous")
            }
            // All on the same row.
            #expect(Set(sequence.map { $0 / chart.columns }).count == 1)
            #expect(sequence.allSatisfy { $0 >= 0 && $0 < chart.letters.count })
        }
    }

    // MARK: M13 · Path tracer

    @Test("Corridor width is in arcminutes and survives the render limit")
    func tracerUnitsAgree() {
        // THE BUG THIS CAUGHT: the dimension was in DEGREES while the render
        // limit returned ARCMINUTES, so the clamp produced 21.4 and the
        // staircase read it as 21.4 degrees — an 840 pt corridor, wider than the
        // screen. Nothing catches that but arithmetic: both sides are Double.
        let config = PathTracerExercise.descriptor.staircase

        for profile in [iPhoneSE, iPadPro13] {
            let floorArcminutes = config.resolvedHardestValue(for: profile)
            let pointsPerArcminute = profile.points(forDegrees: 1) / 60
            let widthPoints = floorArcminutes * pointsPerArcminute

            #expect(widthPoints >= 13,
                    "corridor \(widthPoints) pt is narrower than a fingertip")
            #expect(widthPoints <= 60,
                    "corridor \(widthPoints) pt is implausibly wide — check the units")
        }
    }

    @Test("The traced path stays inside its canvas")
    func tracePathStaysInBounds() {
        var generator = SeededGenerator(seed: 8)
        let path = TracePathGenerator.make(canvasPoints: 280, corridorWidthPoints: 24,
                                           curviness: 0.9, generator: &generator)
        let margin = path.corridorWidthPoints / 2
        for point in path.points {
            #expect(point.x >= 0 && point.x <= 280)
            #expect(point.y >= margin - 1 && point.y <= 280 - margin + 1)
        }
        #expect(path.points.count > 20)
    }

    @Test("Distance-to-path is zero on the path and grows away from it")
    func distanceToPathIsSane() {
        var generator = SeededGenerator(seed: 4)
        let path = TracePathGenerator.make(canvasPoints: 300, corridorWidthPoints: 30,
                                           curviness: 0.6, generator: &generator)
        guard let onPath = path.points.dropFirst(10).first else {
            Issue.record("path too short"); return
        }
        #expect(path.distance(to: onPath) < 1.0)

        // MEASURED FROM OUTSIDE THE PATH'S ENTIRE Y-RANGE, not just offset from
        // one point. The path WINDS, so a point 60 pt below one pass of the
        // curve can sit close to the next pass — I first asserted that and it
        // failed, correctly: the finger really would be inside the corridor
        // there. Only a point beyond the whole figure is unambiguously outside.
        let lowest = path.points.map(\.y).max() ?? 0
        let clearlyOutside = CGPoint(x: onPath.x, y: lowest + 80)
        #expect(path.distance(to: clearlyOutside) > 40,
                "a point 80 pt beyond the path's lowest extent should be far from it")
    }

    // MARK: M14 · Reading

    @Test("Every passage has a workable question")
    func passagesAreWellFormed() {
        for passage in ReadingPassages.all {
            #expect(passage.options.count == 4)
            #expect(passage.correctOption >= 0 && passage.correctOption < 4)
            #expect(Set(passage.options).count == 4, "duplicate option in \(passage.options)")
            #expect(!passage.text.isEmpty && !passage.question.isEmpty)
            // Long enough to be a reading task rather than a glance.
            #expect(passage.text.count > 100)
        }
    }

    @Test("The correct answer is not always in the same position")
    func answerPositionsVary() {
        let positions = Set(ReadingPassages.all.map(\.correctOption))
        #expect(positions.count >= 3,
                "correct answers sit in only \(positions.count) distinct positions — learnable")
    }

    @Test("The trial's correct answer matches its passage")
    func readingAnswerMatchesPassage() {
        let exercise = ReadingLadderExercise()
        var generator = SeededGenerator(seed: 17)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 0.8, generator: &generator)
            #expect(trial.correctAnswer == exercise.passage(for: trial).correctOption)
        }
    }

    @Test("Print size shrinks with logMAR and stays readable at the floor")
    func readingFontSizes() {
        let exercise = ReadingLadderExercise()
        let config = ReadingLadderExercise.descriptor.staircase
        var generator = SeededGenerator(seed: 2)

        for profile in [iPhoneSE, iPadPro13] {
            let big = exercise.fontPointSize(
                for: exercise.makeTrial(difficulty: 1.2, generator: &generator),
                calibration: profile)
            let small = exercise.fontPointSize(
                for: exercise.makeTrial(difficulty: config.resolvedHardestValue(for: profile),
                                        generator: &generator),
                calibration: profile)

            #expect(small < big, "print did not shrink")
            // The earlier 2.5 pt minimum put the floor at 25 pt, which is larger
            // than ordinary body text — the ladder never reached small print.
            #expect(small >= 10 && small <= 20,
                    "smallest print is \(small) pt, which is not a useful floor")
        }
    }

    // MARK: All fourteen

    @Test("Every registered exercise is constructible and produces valid trials")
    func registryIsComplete() {
        // Counts the MONOCULAR pack specifically, not the whole registry.
        //
        // This was `all.count == 14` and broke the moment the first dichoptic
        // exercise was added — a test that fails on correct work is worse than
        // no test. Phase 6 delivering all 14 monocular exercises is the fact
        // worth pinning; the total grows through Phase 8 by design.
        #expect(ExerciseRegistry.available(track: .monocular).count == 14,
                "the monocular pack should be complete at 14")

        for descriptor in ExerciseRegistry.all {
            guard let exercise = ExerciseRegistry.make(descriptor.id) else {
                Issue.record("\(descriptor.id) has no implementation")
                continue
            }
            var generator = SeededGenerator(seed: 1_234)
            let config = descriptor.staircase
            for difficulty in [config.easiestValue,
                               config.resolvedHardestValue(for: iPhoneSE)] {
                let trial = exercise.makeTrial(difficulty: difficulty, generator: &generator)
                #expect(trial.correctAnswer >= 0)
                #expect(trial.correctAnswer < config.alternatives,
                        "\(descriptor.id): answer \(trial.correctAnswer) outside 0..<\(config.alternatives)")
                #expect(trial.difficulty == difficulty)
            }
        }
    }

    @Test("Every exercise still passes the photosensitivity audit")
    func allFourteenAreSafe() {
        let violations = FlickerGuard.audit(ExerciseRegistry.all)
        // Wrapped in an interpolated literal: `#expect`'s message parameter is
        // `Comment?`, which is ExpressibleByStringInterpolation but will not
        // accept a plain computed `String`.
        #expect(violations.isEmpty,
                "\(violations.map(\.description).joined(separator: "; "))")
    }
}
