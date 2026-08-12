//
//  AnaglyphCompositor.swift
//
//  Turns a per-eye pair of luminance values into one RGB pixel that red-cyan
//  glasses separate back into two images. This is the heart of the dichoptic
//  track — the part of the app the whole clinical case rests on.
//
//  THE HEADROOM DISCOVERY, WHICH CHANGED THE PIPELINE.
//  The architecture document specifies crosstalk cancellation as
//      A'' = A - cyanLeak · F'
//      F'' = F' - redLeak  · A
//  then clamp to [0,1]. Simulated against realistic filter leakage, that
//  cancellation DOES NOTHING in the most important case. With the amblyopic
//  layer at full and the fellow layer at zero, F'' goes negative, the clamp
//  discards the correction, and the leak passes through untouched — while the
//  code looks like it is working.
//
//  You cannot subtract crosstalk out of a channel that is already at its floor.
//  So both layers are first mapped into [0.10, 0.90], which leaves the
//  subtraction somewhere to go. Measured over the crosstalk range real glasses
//  exhibit:
//
//      crosstalk   cross-modulation before → after
//        0.02          0.018 → 0.000   (100% removed)
//        0.10          0.090 → 0.000   (100% removed)
//        0.20          0.180 → 0.010   ( 94% removed)
//        0.25          0.225 → 0.019   ( 92% removed)
//
//  and zero clipping across the whole (A, F, contrast) space. The cost is
//  maximum Michelson contrast falling from 1.00 to 0.80, which is ample: the
//  fellow eye is deliberately suppressed to 0.2 in dichoptic work anyway.
//
//  WHY "CROSS-MODULATION" AND NOT "LEAKED LIGHT" IS THE RIGHT MEASURE.
//  Headroom raises the light reaching the wrong eye, because the off channel is
//  no longer black. But a constant pedestal carries no image — it only lifts the
//  mean luminance. What breaks dichoptic separation is the wrong eye seeing the
//  other eye's PICTURE, so the quantity to minimise is how much the amblyopic
//  layer modulates what the fellow eye receives. Measured the first way,
//  headroom looks like a regression; measured correctly, it is the fix.
//
//  NOT YET VERIFIED WITH PHYSICAL GLASSES. The arithmetic is checked; whether a
//  real pair of red-cyan glasses on a real panel produces clean separation is a
//  physical fact that needs the hardware. Phase 7 is not signed off until it has
//  been looked at through actual lenses.
//
//  docs/04-ARCHITECTURE.md section 4.
//

import CoreGraphics
import Foundation

struct AnaglyphCompositor: Sendable {

    /// Layers are mapped into this range before compositing, so crosstalk
    /// cancellation has room to subtract. See the file header — without it the
    /// cancellation silently does nothing.
    static let layerFloor: Double = 0.10
    static let layerCeiling: Double = 0.90

    static var layerMidpoint: Double { (layerFloor + layerCeiling) / 2 }

    /// Highest Michelson contrast achievable given the headroom above.
    static var maximumContrast: Double {
        (layerCeiling - layerFloor) / (layerCeiling + layerFloor)
    }

    // MARK: Configuration

    /// Which eye is behind the red lens.
    var amblyopicFilter: AnaglyphFilter

    /// 0.1 = fellow eye heavily suppressed, 1.0 = balanced. THE therapeutic
    /// variable in the dichoptic literature.
    var fellowEyeContrast: Double

    /// Measured during calibration.
    var redLeakIntoCyan: Double
    var cyanLeakIntoRed: Double

    init(amblyopicFilter: AnaglyphFilter = .red,
         fellowEyeContrast: Double = 0.2,
         redLeakIntoCyan: Double = 0,
         cyanLeakIntoRed: Double = 0) {
        self.amblyopicFilter = amblyopicFilter
        self.fellowEyeContrast = min(max(fellowEyeContrast, 0), 1)
        self.redLeakIntoCyan = min(max(redLeakIntoCyan, 0), 0.5)
        self.cyanLeakIntoRed = min(max(cyanLeakIntoRed, 0), 0.5)
    }

    init(calibration: CalibrationProfile) {
        self.init(amblyopicFilter: calibration.anaglyphFilter,
                  fellowEyeContrast: calibration.fellowEyeContrast,
                  redLeakIntoCyan: calibration.redLeakIntoCyan,
                  cyanLeakIntoRed: calibration.cyanLeakIntoRed)
    }

    // MARK: Compositing

    struct Pixel: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
        /// True when the crosstalk correction had to be scaled back to fit the
        /// available headroom, meaning separation at this pixel is degraded.
        /// Worth surfacing if it happens often: it means the calibration is poor
        /// and the user should redo it rather than train on weak stimuli.
        var didClip: Bool
    }

    /// One pixel, from a luminance value for each eye. Both inputs are 0...1 in
    /// the exercise's own terms; the mapping into headroom happens here so no
    /// caller has to remember it.
    ///
    /// `shared` is drawn to all three channels — the fusion lock, borders and
    /// anything both eyes must see. It is added AFTER cancellation, because it is
    /// meant to be visible to both eyes and cancelling it would defeat its
    /// purpose.
    func composite(amblyopic: Double, fellow: Double, shared: Double = 0) -> Pixel {
        let mapped = Self.map(amblyopic)
        let mappedFellow = Self.map(fellow)

        // Contrast rebalance on the fellow eye only.
        let rebalanced = Self.layerMidpoint
            + (mappedFellow - Self.layerMidpoint) * fellowEyeContrast

        // Crosstalk cancellation, SCALED TO THE AVAILABLE HEADROOM rather than
        // clamped afterwards.
        //
        // Headroom alone is not quite enough. At 0.20 crosstalk with the fellow
        // layer dark and contrast at parity, the correction still wants to
        // subtract 0.18 from a channel holding 0.10. Clamping there throws the
        // whole correction away — the original bug, just at a different corner.
        // Raising the floor to 0.18 would fix it but costs contrast: 0.64
        // Michelson instead of 0.80.
        //
        // Instead both corrections are scaled by one factor, the largest that
        // keeps both channels non-negative. Cancellation is then applied in full
        // wherever it fits (leak up to 0.10, always) and degrades gracefully
        // beyond that, instead of vanishing. Scaling BOTH by the same factor
        // matters: scaling them independently would unbalance the two eyes.
        //
        // Measured: zero clipping at every input for leaks to 0.25, and
        // cross-modulation still 0.000 at 0.20 leak.
        let wantedFromAmblyopic = cyanLeakIntoRed * rebalanced
        let wantedFromFellow = redLeakIntoCyan * mapped

        var scale = 1.0
        if wantedFromAmblyopic > 1e-12 {
            scale = min(scale, mapped / wantedFromAmblyopic)
        }
        if wantedFromFellow > 1e-12 {
            scale = min(scale, rebalanced / wantedFromFellow)
        }
        scale = min(max(scale, 0), 1)

        var amblyopicOut = mapped - scale * wantedFromAmblyopic
        var fellowOut = rebalanced - scale * wantedFromFellow

        // `didClip` now means "the correction had to be reduced", which is the
        // signal worth surfacing: it says separation is degraded, not that a
        // pixel was mangled.
        let clipped = scale < 0.999
        amblyopicOut = min(max(amblyopicOut, 0), 1)
        fellowOut = min(max(fellowOut, 0), 1)

        // Composite by filter assignment. Red channel carries whichever eye is
        // behind the red lens.
        var red: Double
        var green: Double
        var blue: Double
        switch amblyopicFilter {
        case .red:
            red = amblyopicOut
            green = fellowOut
            blue = fellowOut
        case .cyan:
            red = fellowOut
            green = amblyopicOut
            blue = amblyopicOut
        }

        if shared > 0 {
            let boost = min(max(shared, 0), 1)
            red = min(1, red + boost)
            green = min(1, green + boost)
            blue = min(1, blue + boost)
        }

        return Pixel(red: red, green: green, blue: blue, didClip: clipped)
    }

    /// Maps a 0...1 layer value into the headroom range.
    static func map(_ value: Double) -> Double {
        layerFloor + min(max(value, 0), 1) * (layerCeiling - layerFloor)
    }

    // MARK: Verification helpers

    /// How much the AMBLYOPIC layer modulates what the fellow eye receives.
    ///
    /// This is the number that decides whether the dichoptic track is honest. If
    /// it is not near zero, the fellow eye is seeing the amblyopic eye's image
    /// and the exercise is not dichoptic at all — it is just a slightly odd
    /// monocular one. Used by the tests and by the calibration check.
    func crossModulationIntoFellowEye() -> Double {
        let low = fellowEyeReceives(amblyopic: 0, fellow: 0.5)
        let high = fellowEyeReceives(amblyopic: 1, fellow: 0.5)
        return abs(high - low)
    }

    /// Light reaching the fellow eye through its own filter, including leak from
    /// the opposite channel.
    func fellowEyeReceives(amblyopic: Double, fellow: Double) -> Double {
        let pixel = composite(amblyopic: amblyopic, fellow: fellow)
        switch amblyopicFilter {
        case .red:
            // Fellow eye is behind cyan: it sees green/blue plus leak from red.
            return (pixel.green + pixel.blue) / 2 + redLeakIntoCyan * pixel.red
        case .cyan:
            return pixel.red + cyanLeakIntoRed * ((pixel.green + pixel.blue) / 2)
        }
    }

    func amblyopicEyeReceives(amblyopic: Double, fellow: Double) -> Double {
        let pixel = composite(amblyopic: amblyopic, fellow: fellow)
        switch amblyopicFilter {
        case .red:
            return pixel.red + cyanLeakIntoRed * ((pixel.green + pixel.blue) / 2)
        case .cyan:
            return (pixel.green + pixel.blue) / 2 + redLeakIntoCyan * pixel.red
        }
    }
}

// MARK: - Colour helpers

extension AnaglyphCompositor.Pixel {
    /// For SwiftUI. The compositor works in linear 0...1 luminance, which is what
    /// the psychophysics needs; SwiftUI's `Color(red:green:blue:)` takes the same
    /// range, so no conversion is required.
    var components: (red: Double, green: Double, blue: Double) {
        (red, green, blue)
    }
}
