//
//  MonocularExerciseTests.swift
//
//  M5 Landolt Rings and M2 Contrast Hunt.
//
//  The interesting assertions here are not "does it produce a trial" but
//  "is the trial a valid psychophysical stimulus" — correct ISO proportions,
//  a guess rate that matches the button count, randomisation that actually
//  randomises, and a size that fits the smallest supported screen.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Monocular exercises")
struct MonocularExerciseTests {

    private func calibration(ppi: Double, scale: Double, cm: Double) -> CalibrationProfile {
        CalibrationProfile(screenPointsPerCM: (ppi / scale) / 2.54, viewingDistanceCM: cm)
    }
    private var iPhoneSE: CalibrationProfile { calibration(ppi: 326, scale: 2, cm: 35) }
    private var iPadPro13: CalibrationProfile { calibration(ppi: 264, scale: 2, cm: 50) }

    // MARK: Landolt

    @Test("Landolt rings follow the ISO 8596 proportions")
    func landoltProportions() {
        // 5:1:1 — outer diameter, stroke, gap. These are what make the number
        // comparable with a clinic's rather than merely internally consistent.
        let p = LandoltParameters(gapDirectionDegrees: 0, logMAR: 0.3,
                                  pointsPerDegree: 45)
        #expect(abs(p.outerDiameterPoints - p.gapPoints * 5) < 1e-9)
        #expect(abs(p.strokePoints - p.gapPoints) < 1e-9)
    }

    @Test("A gap of one arcminute is 0.0 logMAR, by definition")
    func logMARDefinition() {
        let p = LandoltParameters(gapDirectionDegrees: 0, logMAR: 0,
                                  pointsPerDegree: 60)
        #expect(abs(p.gapArcminutes - 1.0) < 1e-9)
        // 60 points per degree means 1 point per arcminute.
        #expect(abs(p.gapPoints - 1.0) < 1e-9)

        // Each 0.1 logMAR is one chart line — a factor of 10^0.1 in size.
        let oneLineWorse = LandoltParameters(gapDirectionDegrees: 0, logMAR: 0.1,
                                             pointsPerDegree: 60)
        #expect(abs(oneLineWorse.gapArcminutes / p.gapArcminutes - pow(10, 0.1)) < 1e-9)
    }

    @Test("The easiest ring still fits the narrowest supported screen")
    func easiestRingFits() {
        // iPhone SE portrait is 320 pt wide. A stimulus that overflows would be
        // clipped, and a clipped ring has no gap to find.
        for profile in [iPhoneSE, iPadPro13] {
            let p = LandoltParameters(
                gapDirectionDegrees: 0,
                logMAR: LandoltRingsExercise.descriptor.staircase.easiestValue,
                pointsPerDegree: profile.points(forDegrees: 1))
            #expect(p.canvasPoints <= 288,
                    "canvas \(p.canvasPoints) pt exceeds a 320 pt screen with margins")
        }
    }

    @Test("The hardest ring is still drawable")
    func hardestRingIsDrawable() {
        for profile in [iPhoneSE, iPadPro13] {
            let config = LandoltRingsExercise.descriptor.staircase
            let p = LandoltParameters(
                gapDirectionDegrees: 0,
                logMAR: config.resolvedHardestValue(for: profile),
                pointsPerDegree: profile.points(forDegrees: 1))
            #expect(p.gapPoints >= 1.19,
                    "gap \(p.gapPoints) pt is below the antialiasing limit — the ring reads as closed")
        }
    }

    @Test("Gap direction and the correct answer always agree")
    func landoltAnswerMatchesStimulus() {
        let exercise = LandoltRingsExercise()
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 0.5, generator: &generator)
            let answer = try? #require(LandoltRingsExercise.Answer(rawValue: trial.correctAnswer))
            #expect(answer != nil)
            #expect(abs(trial.payload.value("gapDegrees") - (answer?.degrees ?? -1)) < 1e-9,
                    "the drawn gap must be where the correct answer says it is")
        }
    }

    // MARK: Contrast Hunt

    @Test("Contrast Hunt stays below Nyquist on every supported device")
    func contrastPatchIsRenderable() {
        for profile in [iPhoneSE, iPadPro13] {
            let nyquist = profile.maxRenderableCyclesPerDegree
            #expect(ContrastHuntExercise.cyclesPerDegree < nyquist,
                    "3 c/deg aliases at \(nyquist) c/deg — the grating would become a coarser pattern")
        }
    }

    @Test("The contrast floor is above 8-bit quantisation")
    func contrastFloorIsVisible() {
        let config = ContrastHuntExercise.descriptor.staircase
        let floor = config.resolvedHardestValue(for: iPhoneSE)
        #expect(floor > 2.0 / 255.0,
                "floor \(floor) is below one output step — the patch would be uniform grey")
        #expect(config.isLimitedByDisplay(for: iPhoneSE),
                "the aspirational 0.002 must be raised by the render limit")
    }

    @Test("Quadrants are used evenly")
    func quadrantsAreBalanced() {
        // A biased generator would let the observer learn a position habit, and
        // the staircase would record the habit as sensitivity.
        let exercise = ContrastHuntExercise()
        var generator = SeededGenerator(seed: 99)
        var counts = [0, 0, 0, 0]
        for _ in 0..<2000 {
            let trial = exercise.makeTrial(difficulty: 0.2, generator: &generator)
            counts[trial.correctAnswer] += 1
        }
        for count in counts {
            #expect(count > 380 && count < 620,
                    "quadrant counts \(counts) are not close to uniform over 2000 trials")
        }
    }

    @Test("Orientation and phase are randomised per trial")
    func stimulusIsRandomisedPerTrial() {
        let exercise = ContrastHuntExercise()
        var generator = SeededGenerator(seed: 3)
        var orientations = Set<Double>()
        for _ in 0..<50 {
            let trial = exercise.makeTrial(difficulty: 0.2, generator: &generator)
            orientations.insert(trial.payload.value("orientation"))
        }
        #expect(orientations.count > 45,
                "orientation repeats — the observer could learn the pattern instead of detecting it")
    }

    // MARK: Both

    @Test("Guess rate matches the number of buttons")
    func guessRateMatchesAlternatives() {
        // If these disagree, the staircase converges on the wrong point and
        // every threshold is systematically wrong — silently.
        #expect(LandoltRingsExercise.descriptor.staircase.alternatives
                == LandoltRingsExercise.Answer.allCases.count)
        #expect(ContrastHuntExercise.descriptor.staircase.alternatives
                == ContrastHuntExercise.Answer.allCases.count)
        #expect(GaborOrientationExercise.descriptor.staircase.alternatives
                == GaborOrientationExercise.Answer.allCases.count)
    }

    @Test("Trial generation is reproducible from its seed")
    func seedReproducibility() {
        // A session must be replayable exactly when someone reports a bad trial.
        for exercise in ExerciseRegistry.all.compactMap({ ExerciseRegistry.make($0.id) }) {
            var a = SeededGenerator(seed: 12_345)
            var b = SeededGenerator(seed: 12_345)
            for _ in 0..<25 {
                let ta = exercise.makeTrial(difficulty: 0.4, generator: &a)
                let tb = exercise.makeTrial(difficulty: 0.4, generator: &b)
                #expect(ta.correctAnswer == tb.correctAnswer)
            }
        }
    }
}
