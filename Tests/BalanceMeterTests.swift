//
//  BalanceMeterTests.swift
//
//  D5 Balance Meter — the app's headline metric, and the first dichoptic
//  exercise. Its polarity is the thing most worth guarding: low ratio means
//  faint noise means an EASY trial, so higher is harder. Inverted, the app would
//  report the exact opposite of the truth about someone's suppression, with full
//  confidence.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Balance Meter")
struct BalanceMeterTests {

    private func calibration(leak: Double = 0.06,
                             fellowContrast: Double = 0.2) -> CalibrationProfile {
        CalibrationProfile(screenPointsPerCM: (460.0 / 3) / 2.54,
                           viewingDistanceCM: 35,
                           anaglyphFilter: .cyan,
                           redLeakIntoCyan: leak,
                           cyanLeakIntoRed: leak,
                           colorVisionOK: true,
                           fellowEyeContrast: fellowContrast,
                           anaglyphCalibratedAt: .now)
    }

    // MARK: Polarity

    @Test("Higher ratio is harder, so the threshold IS the balance point")
    func polarityIsCorrect() {
        let config = BalanceMeterExercise.descriptor.staircase
        #expect(config.polarity == .higherIsHarder,
                "low ratio = faint noise = easy trial; inverting this reports the opposite of the truth")
        #expect(config.hardestValue > config.easiestValue)
    }

    @Test("Noise contrast rises with the ratio")
    func noiseScalesWithRatio() {
        let exercise = BalanceMeterExercise()
        var generator = SeededGenerator(seed: 5)
        let profile = calibration()

        let easy = exercise.noiseField(
            for: exercise.makeTrial(difficulty: 0.1, generator: &generator),
            calibration: profile)
        let hard = exercise.noiseField(
            for: exercise.makeTrial(difficulty: 1.5, generator: &generator),
            calibration: profile)

        #expect(hard.contrast > easy.contrast)
        #expect(easy.contrast > 0, "even the easiest trial needs visible noise")
    }

    @Test("Noise contrast never exceeds what the compositor can render")
    func noiseRespectsCompositorLimit() {
        // At high ratios the requested contrast would exceed the headroom the
        // crosstalk cancellation needs. Clamping here rather than in the shader
        // keeps the limit in one place.
        let exercise = BalanceMeterExercise()
        var generator = SeededGenerator(seed: 9)
        let field = exercise.noiseField(
            for: exercise.makeTrial(difficulty: 5.0, generator: &generator),
            calibration: calibration())
        #expect(field.contrast <= AnaglyphCompositor.maximumContrast + 1e-9)
    }

    // MARK: Field construction

    @Test("Signal carries direction and noise carries none")
    func signalAndNoiseDiffer() {
        let exercise = BalanceMeterExercise()
        var generator = SeededGenerator(seed: 11)
        let profile = calibration()

        for _ in 0..<50 {
            let trial = exercise.makeTrial(difficulty: 0.5, generator: &generator)
            let signal = exercise.signalField(for: trial, calibration: profile)
            let noise = exercise.noiseField(for: trial, calibration: profile)

            #expect(signal.coherence > 0.5, "the signal must actually have a direction")
            #expect(noise.coherence == 0,
                    "noise with coherence would carry a second direction and make the trial ambiguous")
            #expect(signal.direction.rawValue == trial.correctAnswer)
        }
    }

    @Test("Signal contrast is fixed so only the ratio varies")
    func signalContrastIsFixed() {
        // Letting both move would produce a threshold describing neither.
        let exercise = BalanceMeterExercise()
        var generator = SeededGenerator(seed: 3)
        let profile = calibration()
        let a = exercise.signalField(
            for: exercise.makeTrial(difficulty: 0.2, generator: &generator),
            calibration: profile).contrast
        let b = exercise.signalField(
            for: exercise.makeTrial(difficulty: 1.8, generator: &generator),
            calibration: profile).contrast
        #expect(a == b)
    }

    @Test("The two fields use independent seeds")
    func fieldsAreIndependent() {
        // A shared seed would correlate the noise with the signal, and correlated
        // noise is not noise — it would carry direction information.
        let exercise = BalanceMeterExercise()
        var generator = SeededGenerator(seed: 21)
        for _ in 0..<50 {
            let trial = exercise.makeTrial(difficulty: 0.5, generator: &generator)
            #expect(trial.payload.value("signalSeed") != trial.payload.value("noiseSeed"))
        }
    }

    @Test("All four directions are used evenly")
    func directionsAreBalanced() {
        let exercise = BalanceMeterExercise()
        var generator = SeededGenerator(seed: 77)
        var counts = [0, 0, 0, 0]
        for _ in 0..<2_000 {
            counts[exercise.makeTrial(difficulty: 0.5, generator: &generator).correctAnswer] += 1
        }
        for count in counts {
            #expect(count > 380 && count < 620, "direction counts \(counts) are not uniform")
        }
    }

    // MARK: Track gating

    @Test("It is hidden entirely without a working anaglyph setup")
    func hiddenWithoutGlasses() {
        // HIDDEN, not locked. A greyed-out row someone can never use reads as a
        // broken app, and for a user with colour vision deficiency it reads as
        // being told their eyes are wrong.
        let profile = Profile(name: "Test", ageGroup: .thirteenPlus, amblyopicEye: .left)

        let withoutGlasses = ExerciseRegistry.available(
            for: profile, isPro: true, canUseAnaglyph: false)
        #expect(!withoutGlasses.contains { $0.id == BalanceMeterExercise.descriptor.id })

        let withGlasses = ExerciseRegistry.available(
            for: profile, isPro: true, canUseAnaglyph: true)
        #expect(withGlasses.contains { $0.id == BalanceMeterExercise.descriptor.id })
    }

    @Test("The paywall list never advertises anaglyph content to someone who cannot use it")
    func paywallRespectsAnaglyphAvailability() {
        let profile = Profile(name: "Test", ageGroup: .thirteenPlus, amblyopicEye: .left)
        let locked = ExerciseRegistry.lockedByPaywall(for: profile, canUseAnaglyph: false)
        #expect(!locked.contains { $0.requiresAnaglyph },
                "offering to sell an exercise the user physically cannot use")
    }

    @Test("It is the only tier-A exercise so far, and weighted highest")
    func evidenceTierIsReflectedInPlanning() {
        let descriptor = BalanceMeterExercise.descriptor
        #expect(descriptor.evidenceTier == .a)
        #expect(descriptor.evidenceTier.planWeight
                > EvidenceTier.b.planWeight,
                "the plan generator should prefer it over tier B when both are due")
    }

    // MARK: Reporting

    @Test("Interpretation bands cover the whole range and read plainly")
    func interpretationBands() {
        // Banded rather than precise: a single session is +-20% at the 95th
        // percentile, so two decimal places would imply precision the
        // measurement does not have.
        let readings = [0.05, 0.2, 0.5, 0.9, 1.2, 2.0]
        var seen = Set<String>()
        for reading in readings {
            let text = BalanceMeterExercise.interpretation(balanceRatio: reading)
            #expect(!text.isEmpty)
            seen.insert(text)
        }
        #expect(seen.count >= 3, "bands collapse to \(seen.count) distinct messages")

        // And none of them may sound like a clinical finding.
        let banned = ["suppression", "diagnos", "amblyopia", "normal", "abnormal"]
        for reading in readings {
            let text = BalanceMeterExercise.interpretation(balanceRatio: reading).lowercased()
            for phrase in banned {
                #expect(!text.contains(phrase), "interpretation contains '\(phrase)'")
            }
        }
    }

    @Test("It still passes the photosensitivity audit")
    func isSafe() {
        #expect(FlickerGuard.audit(BalanceMeterExercise.descriptor).isEmpty)
    }
}
