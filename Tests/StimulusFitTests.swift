//
//  StimulusFitTests.swift
//
//  Every stimulus must fit the narrowest supported window, at every difficulty,
//  on every supported device.
//
//  WHY THIS IS A WHOLE SUITE
//  Two of the first six exercises overflowed an iPhone SE and neither would have
//  produced an error. A Glass pattern clipped at the edges loses its outer ring,
//  which is precisely where the concentric form is most readable. A crowded
//  triplet whose flankers fall off the screen stops being a crowding task and
//  becomes an easy uncrowded one. Both would have converged happily and reported
//  a threshold for a different task than the one named on the card.
//
//  The catalogue has eight more exercises to come and each has its own angular
//  geometry. Checking them one at a time by eye does not scale; this does.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Stimulus fit")
struct StimulusFitTests {

    /// The supported hardware envelope. iPhone SE portrait at 320 pt is the
    /// binding constraint and is why it leads the list.
    struct Device {
        let name: String
        let widthPoints: Double
        let heightPoints: Double
        let calibration: CalibrationProfile
    }

    private static func device(_ name: String, ppi: Double, scale: Double,
                               cm: Double, w: Double, h: Double) -> Device {
        Device(name: name, widthPoints: w, heightPoints: h,
               calibration: CalibrationProfile(screenPointsPerCM: (ppi / scale) / 2.54,
                                               viewingDistanceCM: cm))
    }

    static let devices: [Device] = [
        device("iPhone SE", ppi: 326, scale: 2, cm: 35, w: 320, h: 568),
        device("iPhone 14 Pro", ppi: 460, scale: 3, cm: 35, w: 393, h: 852),
        device("iPad mini", ppi: 326, scale: 2, cm: 45, w: 744, h: 1133),
        device("iPad Pro 13", ppi: 264, scale: 2, cm: 50, w: 1024, h: 1366)
    ]

    /// Margin left for bezel and layout padding.
    private static let margin: Double = 24

    // MARK: Per-exercise geometry

    @Test("Landolt rings fit at their easiest, and stay drawable at their hardest")
    func landoltFits() {
        for device in Self.devices {
            let config = LandoltRingsExercise.descriptor.staircase
            let ppd = device.calibration.points(forDegrees: 1)

            let easiest = LandoltParameters(gapDirectionDegrees: 0,
                                            logMAR: config.easiestValue,
                                            pointsPerDegree: ppd)
            #expect(easiest.canvasPoints <= device.widthPoints - Self.margin,
                    "\(device.name): easiest ring \(easiest.canvasPoints) pt overflows")

            let hardest = LandoltParameters(
                gapDirectionDegrees: 0,
                logMAR: config.resolvedHardestValue(for: device.calibration),
                pointsPerDegree: ppd)
            #expect(hardest.gapPoints >= 1.19,
                    "\(device.name): hardest gap \(hardest.gapPoints) pt reads as a closed ring")
        }
    }

    @Test("The Glass pattern field fits every screen")
    func glassPatternFits() {
        for device in Self.devices {
            let p = GlassPatternParameters(
                form: .concentric, signalFraction: 1,
                pointsPerDegree: device.calibration.points(forDegrees: 1))
            #expect(p.fieldPoints <= device.widthPoints - Self.margin,
                    "\(device.name): field \(p.fieldPoints) pt overflows a \(device.widthPoints) pt screen")

            // Pairs must be resolvable as pairs, or the correlation carrying the
            // whole signal is invisible.
            let separation = p.pairSeparationDegrees * p.pointsPerDegree
            #expect(separation > p.dotDiameterPoints,
                    "\(device.name): pair separation \(separation) pt is smaller than a dot")
        }
    }

    @Test("The crowded triplet fits at its widest separation")
    func crowdedGaborFits() {
        for device in Self.devices {
            let config = CrowdedGaborExercise.descriptor.staircase
            let widest = CrowdedGaborParameters(
                centreOrientationDegrees: 90,
                separationLambda: config.easiestValue,
                pointsPerDegree: device.calibration.points(forDegrees: 1))
            #expect(widest.canvasWidth <= device.widthPoints - Self.margin,
                    "\(device.name): triplet \(widest.canvasWidth) pt overflows — the flankers fall off and the crowding disappears")
        }
    }

    @Test("Vernier offsets stay above the sub-pixel floor")
    func vernierIsRenderable() {
        for device in Self.devices {
            let config = VernierExercise.descriptor.staircase
            let hardest = VernierParameters(
                offsetArcseconds: config.resolvedHardestValue(for: device.calibration),
                pointsPerDegree: device.calibration.points(forDegrees: 1))
            #expect(abs(hardest.offsetPoints) >= VernierGenerator.minimumTrustworthyOffsetPoints - 1e-6,
                    "\(device.name): offset \(hardest.offsetPoints) pt is below what antialiasing can express monotonically")
            #expect(hardest.canvasHeight <= device.heightPoints - 200,
                    "\(device.name): vernier canvas leaves no room for the answer buttons")
        }
    }

    @Test("Gabor patches stay below Nyquist")
    func gaborStaysBelowNyquist() {
        for device in Self.devices {
            let nyquist = device.calibration.maxRenderableCyclesPerDegree
            #expect(ContrastHuntExercise.cyclesPerDegree < nyquist,
                    "\(device.name): 3 c/deg aliases at \(nyquist)")
            // M1 and M3 use the same carrier frequency.
            #expect(3.0 < nyquist)
        }
    }

    // MARK: Registry-wide

    @Test("Every registered exercise has a difficulty range that survives calibration")
    func everyExerciseHasAUsableRange() {
        for descriptor in ExerciseRegistry.all {
            for device in Self.devices {
                let config = descriptor.staircase
                let hardest = config.resolvedHardestValue(for: device.calibration)
                let low = min(hardest, config.easiestValue)
                let high = max(hardest, config.easiestValue)

                #expect(high - low > 1e-6,
                        "\(descriptor.id) on \(device.name): range collapsed")

                for ageGroup in AgeGroup.allCases {
                    let start = config.startValue(for: ageGroup)
                    #expect(start >= low && start <= high,
                            "\(descriptor.id) on \(device.name), \(ageGroup): start \(start) outside \(low)...\(high)")
                }
            }
        }
    }

    @Test("Every exercise can produce a trial at both ends of its range")
    func trialsGenerateAcrossTheRange() {
        for descriptor in ExerciseRegistry.all {
            guard let exercise = ExerciseRegistry.make(descriptor.id) else {
                Issue.record("\(descriptor.id) is in the registry with no implementation")
                continue
            }
            var generator = SeededGenerator(seed: 4_242)
            let config = descriptor.staircase
            for difficulty in [config.easiestValue,
                               config.resolvedHardestValue(for: Self.devices[0].calibration)] {
                let trial = exercise.makeTrial(difficulty: difficulty, generator: &generator)
                #expect(trial.correctAnswer >= 0 && trial.correctAnswer < config.alternatives,
                        "\(descriptor.id): answer \(trial.correctAnswer) outside 0..<\(config.alternatives)")
                #expect(trial.difficulty == difficulty)
            }
        }
    }
}
