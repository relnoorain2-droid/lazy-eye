//
//  AnaglyphTests.swift
//
//  The dichoptic engine's arithmetic.
//
//  THE KEY TEST IS `crosstalkIsActuallyCancelled`. The architecture document's
//  pipeline, implemented literally, does nothing in the case that matters — the
//  correction goes negative and the clamp throws it away, while the code reads as
//  if it is working. That test exists so nobody can "simplify" the headroom
//  mapping out of the compositor without the suite going red.
//
//  None of this proves the effect on real hardware. Whether a physical pair of
//  red-cyan glasses on a real panel separates cleanly is a fact about the world,
//  and Phase 7 is not signed off until someone has looked through actual lenses.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Anaglyph compositor")
struct AnaglyphCompositorTests {

    /// Crosstalk values spanning what real red-cyan glasses exhibit.
    private let realisticLeaks: [Double] = [0.02, 0.05, 0.10, 0.15, 0.20]

    // MARK: The headroom property

    @Test("Crosstalk is genuinely cancelled, not silently clamped away")
    func crosstalkIsActuallyCancelled() {
        for leak in realisticLeaks {
            let compositor = AnaglyphCompositor(
                amblyopicFilter: .red, fellowEyeContrast: 1.0,
                redLeakIntoCyan: leak, cyanLeakIntoRed: leak)

            let uncorrected = AnaglyphCompositor(
                amblyopicFilter: .red, fellowEyeContrast: 1.0,
                redLeakIntoCyan: 0, cyanLeakIntoRed: 0)

            let corrected = compositor.crossModulationIntoFellowEye()

            // Without cancellation the amblyopic image modulates the fellow eye
            // by roughly the leak fraction times the layer range.
            let expectedWithout = leak * (AnaglyphCompositor.layerCeiling
                                          - AnaglyphCompositor.layerFloor)

            #expect(corrected < expectedWithout * 0.25,
                    "leak \(leak): cross-modulation \(corrected) is not much better than \(expectedWithout)")
            #expect(uncorrected.crossModulationIntoFellowEye() < 1e-9,
                    "with zero leak there should be no cross-modulation at all")
        }
    }

    @Test("Output never leaves gamut, at any input or leak")
    func neverLeavesGamut() {
        // The original pipeline clamped, which silently discarded the whole
        // correction. The compositor now SCALES the correction to fit, so nothing
        // ever needs clamping — verified exhaustively rather than assumed.
        for leak in realisticLeaks + [0.25] {
            for amblyopicStep in 0...10 {
                for fellowStep in 0...10 {
                    for contrast in [0.1, 0.2, 0.5, 1.0] {
                        let compositor = AnaglyphCompositor(
                            amblyopicFilter: .red, fellowEyeContrast: contrast,
                            redLeakIntoCyan: leak, cyanLeakIntoRed: leak)
                        let pixel = compositor.composite(
                            amblyopic: Double(amblyopicStep) / 10,
                            fellow: Double(fellowStep) / 10)
                        for value in [pixel.red, pixel.green, pixel.blue] {
                            #expect(value >= 0 && value <= 1,
                                    "out of gamut at leak \(leak), A \(amblyopicStep), F \(fellowStep), contrast \(contrast)")
                        }
                    }
                }
            }
        }
    }

    @Test("The correction is applied in full wherever it fits")
    func correctionIsFullWhereItFits() {
        // Up to 0.10 crosstalk — which covers most real glasses — there is always
        // enough headroom, so the correction is never scaled back at all.
        for leak in [0.02, 0.05, 0.10] {
            for amblyopicStep in 0...10 {
                for fellowStep in 0...10 {
                    for contrast in [0.1, 0.2, 0.5, 1.0] {
                        let compositor = AnaglyphCompositor(
                            amblyopicFilter: .red, fellowEyeContrast: contrast,
                            redLeakIntoCyan: leak, cyanLeakIntoRed: leak)
                        let pixel = compositor.composite(
                            amblyopic: Double(amblyopicStep) / 10,
                            fellow: Double(fellowStep) / 10)
                        #expect(!pixel.didClip,
                                "correction scaled back at leak \(leak), which should have headroom")
                    }
                }
            }
        }
    }

    @Test("Headroom retains enough contrast to be worth using")
    func headroomKeepsUsableContrast() {
        // The trade for cancellation working is maximum contrast. 0.8 is ample:
        // dichoptic work suppresses the fellow eye to 0.2 by design.
        #expect(AnaglyphCompositor.maximumContrast > 0.75)
        #expect(AnaglyphCompositor.layerFloor > 0.05,
                "too little floor and the subtraction clamps again")
        #expect(AnaglyphCompositor.layerCeiling < 0.95)
    }

    // MARK: Separation

    @Test("Each eye's own image reaches it")
    func eachEyeSeesItsOwnLayer() {
        let compositor = AnaglyphCompositor(
            amblyopicFilter: .red, fellowEyeContrast: 1.0,
            redLeakIntoCyan: 0.05, cyanLeakIntoRed: 0.05)

        let dark = compositor.amblyopicEyeReceives(amblyopic: 0, fellow: 0.5)
        let bright = compositor.amblyopicEyeReceives(amblyopic: 1, fellow: 0.5)
        #expect(bright > dark, "the amblyopic eye must see its own layer vary")
        #expect(bright - dark > 0.4, "separation \(bright - dark) is too weak to be a stimulus")
    }

    @Test("Filter assignment swaps which channel carries which eye")
    func filterAssignmentSwapsChannels() {
        let red = AnaglyphCompositor(amblyopicFilter: .red, fellowEyeContrast: 1.0)
        let cyan = AnaglyphCompositor(amblyopicFilter: .cyan, fellowEyeContrast: 1.0)

        let a = red.composite(amblyopic: 1.0, fellow: 0.0)
        let b = cyan.composite(amblyopic: 1.0, fellow: 0.0)

        #expect(a.red > a.green, "red-lens amblyopic eye should ride the red channel")
        #expect(b.green > b.red, "cyan-lens amblyopic eye should ride green/blue")
        // And both still separate their eyes properly.
        #expect(red.crossModulationIntoFellowEye() < 0.01)
        #expect(cyan.crossModulationIntoFellowEye() < 0.01)
    }

    @Test("Green and blue always carry the same value")
    func greenAndBlueMatch() {
        // Cyan is green plus blue. Any difference between them would be a colour
        // fringe the glasses cannot separate.
        let compositor = AnaglyphCompositor(amblyopicFilter: .red,
                                            fellowEyeContrast: 0.4,
                                            redLeakIntoCyan: 0.08,
                                            cyanLeakIntoRed: 0.06)
        for step in 0...10 {
            let pixel = compositor.composite(amblyopic: Double(step) / 10,
                                             fellow: 1 - Double(step) / 10)
            #expect(abs(pixel.green - pixel.blue) < 1e-12)
        }
    }

    // MARK: Contrast rebalance

    @Test("Lower fellow contrast suppresses the fellow eye's image")
    func fellowContrastSuppresses() {
        func swing(at contrast: Double) -> Double {
            let c = AnaglyphCompositor(amblyopicFilter: .red,
                                       fellowEyeContrast: contrast)
            return abs(c.fellowEyeReceives(amblyopic: 0.5, fellow: 1)
                       - c.fellowEyeReceives(amblyopic: 0.5, fellow: 0))
        }
        #expect(swing(at: 0.2) < swing(at: 0.5))
        #expect(swing(at: 0.5) < swing(at: 1.0))
        #expect(swing(at: 0.1) > 0, "even heavy suppression must leave something visible")
    }

    @Test("The shared layer reaches both eyes")
    func sharedLayerIsVisibleToBoth() {
        // The fusion lock has to be seen by both eyes — that is its entire job.
        // It is added after cancellation for that reason.
        let compositor = AnaglyphCompositor(amblyopicFilter: .red,
                                            fellowEyeContrast: 0.3,
                                            redLeakIntoCyan: 0.1,
                                            cyanLeakIntoRed: 0.1)
        let without = compositor.composite(amblyopic: 0.2, fellow: 0.2)
        let with = compositor.composite(amblyopic: 0.2, fellow: 0.2, shared: 0.3)

        #expect(with.red > without.red)
        #expect(with.green > without.green)
        #expect(with.blue > without.blue)
    }

    @Test("Output stays in gamut for every input")
    func outputIsAlwaysInGamut() {
        let compositor = AnaglyphCompositor(amblyopicFilter: .cyan,
                                            fellowEyeContrast: 1.0,
                                            redLeakIntoCyan: 0.2,
                                            cyanLeakIntoRed: 0.2)
        for a in 0...10 {
            for f in 0...10 {
                for shared in [0.0, 0.5, 1.0] {
                    let pixel = compositor.composite(amblyopic: Double(a) / 10,
                                                     fellow: Double(f) / 10,
                                                     shared: shared)
                    for value in [pixel.red, pixel.green, pixel.blue] {
                        #expect(value >= 0 && value <= 1)
                    }
                }
            }
        }
    }
}

// MARK: - Calibrator

@Suite("Anaglyph calibration")
struct AnaglyphCalibratorTests {

    @Test("The amblyopic eye gets the brighter lens")
    func amblyopicEyeGetsCyan() {
        // A red filter passes about 30% of a white screen; cyan about 70%.
        // Putting red over the weak eye would dim the eye that needs the most
        // signal, which is the opposite of the point.
        #expect(AnaglyphCalibrator.recommendedFilterForAmblyopicEye() == .cyan)
    }

    @Test("The leak probe nulls out when the estimate is right")
    func leakProbeNullsCorrectly() {
        // The user's task is "make it disappear", which is a null judgement and
        // far more reliable than "say when you can see it".
        for trueLeak in [0.05, 0.10, 0.20] {
            var probe = AnaglyphCalibrator.LeakProbe(channel: .red, leak: trueLeak)
            let patch = probe.patch()
            // At the correct setting the cancellation term matches the probe's
            // amplitude times the leak.
            let mid = AnaglyphCompositor.layerMidpoint
            #expect(abs((mid - patch.green) / 0.35 - trueLeak) < 1e-9)

            // Under- and over-shoot must move in opposite directions, or the
            // slider gives the user no gradient to follow.
            probe.leak = trueLeak * 0.5
            let under = probe.patch()
            probe.leak = trueLeak * 1.5
            let over = probe.patch()
            #expect(under.green > patch.green)
            #expect(over.green < patch.green)
        }
    }

    @Test("Implausible leak values are rejected")
    func leakBoundsEnforced() {
        #expect(AnaglyphCalibrator.isPlausible(0.0))
        #expect(AnaglyphCalibrator.isPlausible(0.12))
        #expect(!AnaglyphCalibrator.isPlausible(0.6),
                "0.6 means the glasses are not on")
        #expect(!AnaglyphCalibrator.isPlausible(-0.1))
    }

    @Test("The colour-vision screen is hard to pass by guessing")
    func discriminationFalsePassRate() {
        #expect(AnaglyphCalibrator.passed(correct: 6))
        #expect(AnaglyphCalibrator.passed(correct: 8))
        #expect(!AnaglyphCalibrator.passed(correct: 5))

        // 6 of 8 at a 50% guess rate. Low enough to screen, lenient enough not
        // to fail someone who blinked.
        #expect(AnaglyphCalibrator.falsePassRate < 0.20)
        #expect(AnaglyphCalibrator.falsePassRate > 0.05,
                "a stricter mark would start excluding people with normal vision")
    }

    @Test("Unusable calibrations are not stamped as complete")
    func failedCalibrationIsNotMarkedDone() {
        let calibration = CalibrationProfile(screenPointsPerCM: 60, viewingDistanceCM: 40)

        let bad = AnaglyphCalibrator.Result(redLeakIntoCyan: 0.30,
                                            cyanLeakIntoRed: 0.30,
                                            colorVisionOK: true)
        AnaglyphCalibrator.apply(bad, to: calibration)
        #expect(!bad.isUsable)
        #expect(calibration.anaglyphCalibratedAt == nil,
                "a failed calibration must not report as done")
        #expect(!calibration.isAnaglyphCalibrated)

        let good = AnaglyphCalibrator.Result(redLeakIntoCyan: 0.06,
                                            cyanLeakIntoRed: 0.05,
                                            colorVisionOK: true)
        AnaglyphCalibrator.apply(good, to: calibration)
        #expect(good.isUsable)
        #expect(calibration.isAnaglyphCalibrated)
    }

    @Test("Failing the colour check makes the calibration unusable")
    func colourBlindRoutesAway() {
        let result = AnaglyphCalibrator.Result(redLeakIntoCyan: 0.02,
                                              cyanLeakIntoRed: 0.02,
                                              colorVisionOK: false)
        #expect(!result.isUsable, "clean filters do not help if the eyes cannot separate them")
    }

    @Test("A usable calibration achieves low cross-modulation")
    func usableCalibrationSeparatesEyes() {
        let result = AnaglyphCalibrator.Result(redLeakIntoCyan: 0.10,
                                               cyanLeakIntoRed: 0.08,
                                               colorVisionOK: true)
        #expect(result.isUsable)
        let cross = result.crossModulation(amblyopicFilter: .cyan, fellowEyeContrast: 1.0)
        #expect(cross < 0.02,
                "cross-modulation \(cross) — the fellow eye would see the other image")
    }
}

// MARK: - Rebalance ramp

@Suite("Contrast rebalance ramp")
struct ContrastRebalanceRampTests {

    @Test("A comfortable session raises the fellow eye's contrast")
    func stepsUpOnSuccess() {
        let next = ContrastRebalanceRamp.next(from: 0.20, completionRatio: 0.95)
        #expect(next > 0.20)
        #expect(abs(next - 0.25) < 1e-9)
    }

    @Test("A struggled session drops it further than a good one raised it")
    func dropsFasterThanItRises() {
        // Asymmetric on purpose: losing fusion is worse than progressing slowly,
        // so the ramp settles just below the user's limit rather than oscillating
        // across it.
        let up = ContrastRebalanceRamp.next(from: 0.50, completionRatio: 0.9) - 0.50
        let down = 0.50 - ContrastRebalanceRamp.next(from: 0.50, completionRatio: 0.3)
        #expect(down > up)
    }

    @Test("A middling session leaves it alone")
    func holdsInTheMiddle() {
        #expect(ContrastRebalanceRamp.next(from: 0.40, completionRatio: 0.65) == 0.40)
    }

    @Test("The ramp stays within bounds")
    func staysInBounds() {
        var value = 0.20
        for _ in 0..<100 { value = ContrastRebalanceRamp.next(from: value, completionRatio: 1.0) }
        #expect(value <= ContrastRebalanceRamp.maximum)
        #expect(ContrastRebalanceRamp.hasReachedParity(value))

        for _ in 0..<100 { value = ContrastRebalanceRamp.next(from: value, completionRatio: 0.0) }
        #expect(value >= ContrastRebalanceRamp.minimum)
    }

    @Test("Reaching parity takes a realistic number of sessions")
    func rampTakesSensibleTime() {
        // From heavy suppression to parity at 0.05 a session is 16 sessions of
        // near-perfect completion — a few weeks of daily practice. Faster would
        // outrun the adaptation the ramp exists to drive.
        var value = ContrastRebalanceRamp.minimum
        var sessions = 0
        while !ContrastRebalanceRamp.hasReachedParity(value) && sessions < 200 {
            value = ContrastRebalanceRamp.next(from: value, completionRatio: 1.0)
            sessions += 1
        }
        #expect(sessions >= 15 && sessions <= 25, "took \(sessions) sessions")
    }
}
