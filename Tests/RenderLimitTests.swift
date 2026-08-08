//
//  RenderLimitTests.swift
//
//  Guards the rule that a staircase may never descend below what the display can
//  physically draw.
//
//  WHY THIS MATTERS MORE THAN IT LOOKS
//  A staircase that runs past the display's limit does not stop working. It
//  keeps producing reversals, converges, and reports a threshold with exactly
//  the same confidence as a real one - except the observer was guessing at a
//  uniform grey rectangle, so the number describes the framebuffer. Every trend
//  line, every "no clear change yet", every plan decision downstream then rests
//  on it. It is invisible in code review and invisible in the UI. The only place
//  it shows up is arithmetic, so the arithmetic is a test.
//
//  The bounds below were caught exactly this way: three of the four values first
//  written for Phase 6 were impossible on real hardware.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Render limits")
struct RenderLimitTests {

    /// A calibration matching a real device at a real viewing distance.
    private func calibration(pointsPerInch: Double, scale: Double,
                             distanceCM: Double) -> CalibrationProfile {
        CalibrationProfile(screenPointsPerCM: (pointsPerInch / scale) / 2.54,
                           viewingDistanceCM: distanceCM)
    }

    /// Worst case in the supported range: a dense phone held close, which gives
    /// the fewest points per degree of any device we support.
    private var iPhone14Pro: CalibrationProfile { calibration(pointsPerInch: 460, scale: 3, distanceCM: 35) }
    private var iPadPro13: CalibrationProfile { calibration(pointsPerInch: 264, scale: 2, distanceCM: 50) }
    private var iPhoneSE: CalibrationProfile { calibration(pointsPerInch: 326, scale: 2, distanceCM: 35) }

    // MARK: Contrast

    @Test("Contrast floor sits above 8-bit quantisation")
    func contrastFloor() {
        // Below 2/255 the modulation is smaller than one output level: the patch
        // is a uniform grey and the observer is guessing.
        let limit = RenderLimit.contrast(minimumQuantisationSteps: 3)
        let floor = try? #require(limit.hardestRenderableValue(for: nil))
        #expect(floor != nil, "contrast is bounded by the framebuffer, not geometry — no calibration needed")
        #expect((floor ?? 0) > 2.0 / 255.0)
        #expect((floor ?? 0) < 0.05, "floor \(floor ?? 0) would be too coarse to measure anything useful")
    }

    // MARK: Geometry

    @Test("Angular floors scale with points per degree, not with pixels")
    func angularFloorsTrackCalibration() {
        let limit = RenderLimit.arcseconds(minimumFeaturePoints: 0.35)

        let dense = try? #require(limit.hardestRenderableValue(for: iPhone14Pro))
        let roomy = try? #require(limit.hardestRenderableValue(for: iPadPro13))

        // The iPad has MORE points per degree at its viewing distance, so it can
        // render a FINER offset - a smaller number of arcseconds.
        #expect((roomy ?? 0) < (dense ?? 0),
                "iPad \(roomy ?? 0) should resolve finer than iPhone \(dense ?? 0)")
    }

    @Test("Resolved floors land in the clinically useful range",
          arguments: ["iPhone 14 Pro", "iPhone SE", "iPad Pro 13"])
    func floorsAreUseful(device: String) {
        let profile = switch device {
        case "iPhone SE": iPhoneSE
        case "iPad Pro 13": iPadPro13
        default: iPhone14Pro
        }

        // Vernier: normal thresholds are 5-10 arcsec, amblyopic 30-200. The
        // floor has to sit below the amblyopic range or the exercise cannot
        // measure the people it is for.
        let vernier = RenderLimit.arcseconds(minimumFeaturePoints: 0.35)
            .hardestRenderableValue(for: profile) ?? .infinity
        #expect(vernier < 40, "\(device): vernier floor \(vernier) arcsec is above the amblyopic range")

        // Landolt: 20/20 is 0.0 logMAR; amblyopic acuity is commonly 0.3-1.0.
        let landolt = RenderLimit.logMAR(minimumFeaturePoints: 1.2)
            .hardestRenderableValue(for: profile) ?? .infinity
        #expect(landolt < 0.35, "\(device): acuity floor \(landolt) logMAR cannot reach the amblyopic range")
    }

    @Test("No calibration means no geometric claim")
    func withoutCalibrationGeometryIsUnbounded() {
        // Returning nil rather than guessing is deliberate: an uncalibrated
        // profile has no basis for an angular floor, and inventing one would be
        // worse than declining to.
        #expect(RenderLimit.arcminutes(minimumFeaturePoints: 1).hardestRenderableValue(for: nil) == nil)
        #expect(RenderLimit.logMAR(minimumFeaturePoints: 1).hardestRenderableValue(for: nil) == nil)

        let incomplete = CalibrationProfile(screenPointsPerCM: 0, viewingDistanceCM: 50)
        #expect(RenderLimit.arcminutes(minimumFeaturePoints: 1).hardestRenderableValue(for: incomplete) == nil)
    }

    // MARK: Integration with the staircase

    @Test("A staircase never receives a bound the screen cannot draw")
    func staircaseIsClamped() {
        // An exercise asking for 10 arcsec — genuinely impossible, it is under
        // a third of a point on every device we support.
        let config = StaircaseConfiguration(
            dimensionName: "offset", unit: "\"",
            startValue: 600, hardestValue: 10, easiestValue: 1200,
            polarity: .lowerIsHarder, alternatives: 2,
            renderLimit: .arcseconds(minimumFeaturePoints: 0.35)
        )

        let resolved = config.resolvedHardestValue(for: iPhone14Pro)
        #expect(resolved > 10, "the impossible 10 arcsec request must be raised")
        #expect(config.isLimitedByDisplay(for: iPhone14Pro))

        let staircase = config.makeStaircase(calibration: iPhone14Pro)
        var s = staircase
        for _ in 0..<400 { s.record(correct: true) }
        #expect(s.value >= resolved - 1e-9,
                "drove the staircase to its floor and it landed at \(s.value), below the renderable \(resolved)")
    }

    @Test("An achievable bound is left alone")
    func achievableBoundUntouched() {
        let config = StaircaseConfiguration(
            dimensionName: "offset", unit: "\"",
            startValue: 600, hardestValue: 300, easiestValue: 1200,
            polarity: .lowerIsHarder, alternatives: 2,
            renderLimit: .arcseconds(minimumFeaturePoints: 0.35)
        )
        #expect(config.resolvedHardestValue(for: iPhone14Pro) == 300)
        #expect(config.isLimitedByDisplay(for: iPhone14Pro) == false)
    }

    @Test("Clamping respects polarity")
    func polarityAware() {
        // On a higher-is-harder dimension the display limit is a CEILING, so the
        // clamp has to move the opposite way. Getting this backwards would widen
        // the range instead of narrowing it, which is the silent-failure version.
        let config = StaircaseConfiguration(
            dimensionName: "spatial frequency", unit: " cpd",
            startValue: 2, hardestValue: 60, easiestValue: 1,
            polarity: .higherIsHarder, alternatives: 2,
            renderLimit: .cyclesPerDegree(pointsPerCycle: 2)
        )
        let resolved = config.resolvedHardestValue(for: iPhone14Pro)
        #expect(resolved < 60, "60 cpd is far above Nyquist on any phone")
        #expect(resolved > 10, "but the clamp should not collapse the range")
    }

    // MARK: The shipped exercises

    @Test("Every registered exercise has a usable range on every supported device")
    func registryIsRenderableEverywhere() {
        for descriptor in ExerciseRegistry.all {
            for (name, profile) in [("iPhone 14 Pro", iPhone14Pro),
                                    ("iPhone SE", iPhoneSE),
                                    ("iPad Pro 13", iPadPro13)] {
                let config = descriptor.staircase
                let hardest = config.resolvedHardestValue(for: profile)
                let easiest = config.easiestValue

                // Whatever the polarity, the two ends must still be distinct and
                // the start value must sit between them.
                #expect(abs(hardest - easiest) > 1e-6,
                        "\(descriptor.id) on \(name): range collapsed to a point")

                let low = min(hardest, easiest), high = max(hardest, easiest)
                let start = config.startValue(for: .thirteenPlus)
                #expect(start >= low && start <= high,
                        "\(descriptor.id) on \(name): start \(start) outside \(low)...\(high)")
            }
        }
    }
}
