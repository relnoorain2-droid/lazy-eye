//
//  MotionSearchExerciseTests.swift
//
//  M7 Motion Field, M6 Crowded Letters, M12 Find It.
//
//  M12 gets the most attention here because it is the first HIGHER-IS-HARDER
//  exercise and the first whose difficulty depends on the renderer succeeding:
//  if the sampler cannot place the requested number of items, the staircase is
//  measuring a difficulty that was never presented.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Motion and search exercises")
struct MotionSearchExerciseTests {

    private func calibration(ppi: Double, scale: Double, cm: Double) -> CalibrationProfile {
        CalibrationProfile(screenPointsPerCM: (ppi / scale) / 2.54, viewingDistanceCM: cm)
    }
    private var iPhoneSE: CalibrationProfile { calibration(ppi: 326, scale: 2, cm: 35) }
    private var iPadPro13: CalibrationProfile { calibration(ppi: 264, scale: 2, cm: 50) }

    // MARK: M7 · Motion

    @Test("Dots move exactly one step per frame, in the stated direction")
    func coherentDotsMoveCorrectly() {
        var parameters = KinematogramParameters(
            direction: .right, coherence: 1.0,
            pointsPerDegree: iPhoneSE.points(forDegrees: 1))
        parameters.dotCount = 50
        // Long lifetime so nothing is replaced during the check.
        parameters.dotLifetimeFrames = 10_000

        var generator = SeededGenerator(seed: 11)
        var dots = KinematogramGenerator.makeDots(parameters, generator: &generator)
        let before = dots.map(\.x)

        KinematogramGenerator.advance(&dots, parameters: parameters, generator: &generator)

        for (index, dot) in dots.enumerated() {
            // .right is angle 0, so x advances by exactly one step.
            let expected = before[index] + parameters.stepPoints
            let wrapped = expected >= parameters.fieldPoints
            #expect(wrapped || abs(dot.x - expected) < 1e-9,
                    "dot \(index) moved to \(dot.x), expected \(expected)")
        }
    }

    @Test("At zero coherence no dot is a signal dot")
    func zeroCoherenceHasNoSignal() {
        var parameters = KinematogramParameters(
            direction: .up, coherence: 0,
            pointsPerDegree: iPhoneSE.points(forDegrees: 1))
        parameters.dotCount = 200

        var generator = SeededGenerator(seed: 3)
        let dots = KinematogramGenerator.makeDots(parameters, generator: &generator)
        #expect(dots.allSatisfy { !$0.isSignal })
    }

    @Test("Coherence sets roughly the right fraction of signal dots")
    func coherenceFractionIsHonoured() {
        var parameters = KinematogramParameters(
            direction: .up, coherence: 0.5,
            pointsPerDegree: iPhoneSE.points(forDegrees: 1))
        parameters.dotCount = 2_000

        var generator = SeededGenerator(seed: 5)
        let dots = KinematogramGenerator.makeDots(parameters, generator: &generator)
        let fraction = Double(dots.filter(\.isSignal).count) / Double(dots.count)
        #expect(abs(fraction - 0.5) < 0.05, "got \(fraction), expected about 0.5")
    }

    @Test("Dots stay inside the field, wrapping rather than piling at the edges")
    func dotsWrapWithinField() {
        // Clamping instead of wrapping would build a density gradient at one
        // edge, and that gradient is itself a direction cue — the observer could
        // answer without perceiving motion at all.
        var parameters = KinematogramParameters(
            direction: .right, coherence: 1.0,
            pointsPerDegree: iPhoneSE.points(forDegrees: 1))
        parameters.dotCount = 100
        parameters.dotLifetimeFrames = 10_000

        var generator = SeededGenerator(seed: 7)
        var dots = KinematogramGenerator.makeDots(parameters, generator: &generator)

        for _ in 0..<600 {
            KinematogramGenerator.advance(&dots, parameters: parameters, generator: &generator)
        }
        for dot in dots {
            #expect(dot.x >= 0 && dot.x < parameters.fieldPoints)
            #expect(dot.y >= 0 && dot.y < parameters.fieldPoints)
        }

        // And they should still be spread out, not bunched.
        let rightHalf = dots.filter { $0.x > parameters.fieldPoints / 2 }.count
        #expect(rightHalf > 20 && rightHalf < 80,
                "\(rightHalf)/100 dots in the right half — the field has bunched")
    }

    // MARK: M6 · Letters

    @Test("Four distinct Sloan letters are offered each trial")
    func lettersAreDistinct() {
        let exercise = CrowdedLettersExercise()
        var generator = SeededGenerator(seed: 21)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 2.0, generator: &generator)
            let choices = exercise.choices(for: trial)
            #expect(choices.count == 4)
            #expect(Set(choices).count == 4, "repeated letter in \(choices)")
            #expect(choices.allSatisfy { SloanLetters.all.contains($0) },
                    "non-Sloan letter in \(choices)")
        }
    }

    @Test("The correct button always holds the letter that was drawn in the middle")
    func targetMatchesTheDrawnLetter() {
        let exercise = CrowdedLettersExercise()
        var generator = SeededGenerator(seed: 33)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 2.0, generator: &generator)
            let parameters = exercise.parameters(for: trial, calibration: iPhoneSE)
            let choices = exercise.choices(for: trial)
            #expect(parameters.target == choices[trial.correctAnswer],
                    "drew \(parameters.target) but the correct button says \(choices[trial.correctAnswer])")
            // Flankers must not be the target, or the task is unanswerable.
            #expect(!parameters.flankers.contains(parameters.target))
        }
    }

    @Test("The correct answer is spread across all four positions")
    func answerPositionIsBalanced() {
        let exercise = CrowdedLettersExercise()
        var generator = SeededGenerator(seed: 44)
        var counts = [0, 0, 0, 0]
        for _ in 0..<2_000 {
            counts[exercise.makeTrial(difficulty: 2.0, generator: &generator).correctAnswer] += 1
        }
        for count in counts {
            #expect(count > 380 && count < 620,
                    "answer positions \(counts) are not uniform — a position habit would be learnable")
        }
    }

    @Test("Letter size stays fixed while spacing varies")
    func onlySpacingVaries() {
        // The exercise measures crowding. If size moved too, the threshold would
        // describe neither size nor spacing.
        let exercise = CrowdedLettersExercise()
        var generator = SeededGenerator(seed: 6)
        let easy = exercise.parameters(
            for: exercise.makeTrial(difficulty: 3.5, generator: &generator),
            calibration: iPhoneSE)
        let hard = exercise.parameters(
            for: exercise.makeTrial(difficulty: 1.0, generator: &generator),
            calibration: iPhoneSE)

        #expect(easy.letterHeightPoints == hard.letterHeightPoints)
        #expect(hard.spacingPoints < easy.spacingPoints)
    }

    // MARK: M12 · Search

    @Test("The sampler places every requested item at the hardest setting")
    func samplerPlacesAllItemsAtTheCeiling() {
        // THE TEST THAT CAUGHT THE ORIGINAL BUG.
        // At 0.8 degree items and a ceiling of 40, the field could only hold
        // about 27 — so the sampler quietly returned fewer than asked for and
        // difficulty stopped rising while the staircase kept climbing.
        let ceiling = Int(FindItExercise.descriptor.staircase.hardestValue)

        for profile in [iPhoneSE, iPadPro13] {
            let parameters = SearchFieldParameters(
                itemCount: ceiling,
                pointsPerDegree: profile.points(forDegrees: 1))
            var generator = SeededGenerator(seed: 99)
            let items = SearchFieldGenerator.makeItems(parameters, generator: &generator)
            #expect(items.count == ceiling,
                    "asked for \(ceiling), placed \(items.count) — difficulty would stop rising here")
        }
    }

    @Test("Exactly one item is the target")
    func exactlyOneTarget() {
        var generator = SeededGenerator(seed: 12)
        for count in [4, 8, 14, 20] {
            let parameters = SearchFieldParameters(
                itemCount: count, pointsPerDegree: iPhoneSE.points(forDegrees: 1))
            let items = SearchFieldGenerator.makeItems(parameters, generator: &generator)
            #expect(items.filter(\.isTarget).count == 1,
                    "\(items.filter(\.isTarget).count) targets among \(items.count) items")
        }
    }

    @Test("Items never overlap")
    func itemsDoNotOverlap() {
        let parameters = SearchFieldParameters(
            itemCount: 20, pointsPerDegree: iPhoneSE.points(forDegrees: 1))
        var generator = SeededGenerator(seed: 55)
        let items = SearchFieldGenerator.makeItems(parameters, generator: &generator)

        let minimum = parameters.itemPoints * 1.3
        for a in items {
            for b in items where b.id > a.id {
                let distance = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
                #expect(distance >= minimum - 1e-6,
                        "items \(a.id) and \(b.id) are \(distance) apart, minimum is \(minimum)")
            }
        }
    }

    @Test("Every item is inside the field")
    func itemsStayInsideTheField() {
        let parameters = SearchFieldParameters(
            itemCount: 20, pointsPerDegree: iPhoneSE.points(forDegrees: 1))
        var generator = SeededGenerator(seed: 66)
        let items = SearchFieldGenerator.makeItems(parameters, generator: &generator)

        let margin = parameters.itemPoints / 2
        for item in items {
            #expect(item.x >= margin - 1e-6 && item.x <= parameters.fieldPoints - margin + 1e-6)
            #expect(item.y >= margin - 1e-6 && item.y <= parameters.fieldPoints - margin + 1e-6)
        }
    }

    @Test("The target's orientation differs from every distractor")
    func targetIsDistinguishable() {
        let parameters = SearchFieldParameters(
            itemCount: 20, pointsPerDegree: iPhoneSE.points(forDegrees: 1))
        var generator = SeededGenerator(seed: 77)
        let items = SearchFieldGenerator.makeItems(parameters, generator: &generator)

        guard let target = items.first(where: \.isTarget) else {
            Issue.record("no target placed")
            return
        }
        for other in items where !other.isTarget {
            #expect(abs(other.rotationDegrees - target.rotationDegrees) > 1,
                    "a distractor points the same way as the target — the trial is unanswerable")
        }
    }

    @Test("Find It is higher-is-harder, unlike everything else")
    func findItPolarity() {
        let config = FindItExercise.descriptor.staircase
        #expect(config.polarity == .higherIsHarder)
        #expect(config.hardestValue > config.easiestValue)

        // And its steps must be coarse enough to change an INTEGER item count.
        // A 3% step on 8 items rounds to 8, and the staircase would stall.
        var staircase = config.makeStaircase()
        let start = staircase.value.rounded()
        for _ in 0..<9 { staircase.record(correct: true) }
        #expect(staircase.value.rounded() != start,
                "three correct answers did not change the item count")
    }
}
