//
//  GaborGenerator.swift
//
//  A Gabor patch: a sinusoidal grating multiplied by a Gaussian window.
//
//      L(x,y) = L0 * (1 + C * cos(2π f (x cosθ + y sinθ) + φ) * exp(-(x²+y²)/2σ²))
//
//  WHY A GABOR AND NOT A PICTURE OF STRIPES
//  A hard-edged grating patch has sharp borders, and a sharp border contains
//  every spatial frequency at once. The whole point of this exercise is to
//  measure sensitivity at ONE spatial frequency, so an unwindowed patch measures
//  something else - probably the edge. The Gaussian envelope is what makes the
//  stimulus frequency-specific, and it is why Gabors are the standard stimulus
//  in the perceptual-learning literature this exercise comes from.
//
//  WHY IT IS DRAWN, NOT BUNDLED
//  Every stimulus in this app is procedural. A bundled PNG is fixed in pixels,
//  so it is a different angular size on every device and at every distance,
//  which destroys the calibration work. It also cannot vary continuously with
//  the staircase. And it is why the reference app ships 81 MB while this one
//  will ship under 25.
//
//  RENDERING PATH
//  Drawn into a CGImage on a background actor and handed to SwiftUI as an Image.
//  Not a per-frame Canvas: a Gabor is static for its whole presentation, so
//  regenerating it every frame burns battery to produce identical pixels. The
//  image is cached by its parameters.
//
//  docs/04-ARCHITECTURE.md section 4, docs/03-EXERCISE-CATALOG.md M1.
//

import CoreGraphics
import Foundation

struct GaborParameters: Hashable, Sendable {

    /// Orientation in degrees, 0 = vertical stripes, increasing clockwise.
    var orientationDegrees: Double

    /// Spatial frequency in CYCLES PER DEGREE of visual angle - not per pixel.
    /// This is the number the calibration exists to make meaningful.
    var cyclesPerDegree: Double

    /// Michelson contrast, 0...1.
    var contrast: Double

    /// Gaussian envelope standard deviation, in DEGREES of visual angle.
    var sigmaDegrees: Double

    /// Phase offset in radians. Randomised per trial so the observer cannot
    /// learn the position of a bright bar instead of the orientation.
    var phase: Double

    /// Total patch size in points, from the calibration.
    var sizePoints: Double

    /// Points per degree, from the calibration. Everything angular is converted
    /// through this one number.
    var pointsPerDegree: Double

    init(
        orientationDegrees: Double,
        cyclesPerDegree: Double = 3.0,
        contrast: Double = 0.9,
        sigmaDegrees: Double = 0.5,
        phase: Double = 0,
        sizePoints: Double,
        pointsPerDegree: Double
    ) {
        self.orientationDegrees = orientationDegrees
        self.cyclesPerDegree = cyclesPerDegree
        self.contrast = min(max(contrast, 0), 1)
        self.sigmaDegrees = sigmaDegrees
        self.phase = phase
        self.sizePoints = sizePoints
        self.pointsPerDegree = pointsPerDegree
    }

    /// The finest grating this screen can actually show, in cycles per degree,
    /// at 2 pixels per cycle. Asking for more than this measures the display's
    /// sampling, not the observer - the grating aliases into a coarser pattern
    /// and the threshold that comes back is fiction.
    var nyquistCeiling: Double { pointsPerDegree / 2 }

    /// Frequency actually rendered, after the Nyquist clamp.
    var renderableCyclesPerDegree: Double { min(cyclesPerDegree, nyquistCeiling) }

    var isAboveNyquist: Bool { cyclesPerDegree > nyquistCeiling }
}

enum GaborGenerator {

    /// Renders a Gabor into a grayscale image on a mid-grey background.
    ///
    /// Mid-grey, not black: a Gabor modulates luminance symmetrically above and
    /// below the background. On a black background there is no room to go
    /// darker, the negative half of the sinusoid clips, and the stimulus is no
    /// longer the thing whose contrast you think you are measuring.
    static func makeImage(_ parameters: GaborParameters, scale: Double = 2.0) -> CGImage? {
        let side = Int((parameters.sizePoints * scale).rounded())
        guard side > 0, side <= 4096 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let buffer = context.data else { return nil }

        let pixels = buffer.bindMemory(to: UInt8.self, capacity: side * side)

        let pixelsPerDegree = parameters.pointsPerDegree * scale
        let frequency = parameters.renderableCyclesPerDegree / pixelsPerDegree  // cycles per pixel
        let sigmaPixels = parameters.sigmaDegrees * pixelsPerDegree
        let theta = parameters.orientationDegrees * .pi / 180
        let cosTheta = cos(theta), sinTheta = sin(theta)
        let centre = Double(side - 1) / 2
        let twoSigmaSquared = 2 * sigmaPixels * sigmaPixels

        for y in 0..<side {
            let dy = Double(y) - centre
            for x in 0..<side {
                let dx = Double(x) - centre

                // Rotate into the grating's frame; only the perpendicular
                // component modulates.
                let along = dx * cosTheta + dy * sinTheta
                let carrier = cos(2 * .pi * frequency * along + parameters.phase)
                let envelope = exp(-(dx * dx + dy * dy) / twoSigmaSquared)

                // 0.5 is mid-grey. Luminance swings symmetrically around it.
                let luminance = 0.5 + 0.5 * parameters.contrast * carrier * envelope
                pixels[y * side + x] = UInt8(min(max(luminance, 0), 1) * 255)
            }
        }
        return context.makeImage()
    }

    /// Peak-to-trough Michelson contrast actually achieved, given 8-bit output.
    /// Below roughly 0.008 the quantisation step is larger than the modulation
    /// and the patch is uniform grey - the observer is guessing and the
    /// staircase happily records it as a threshold. Exercises must not set their
    /// contrast floor below this.
    static let minimumRenderableContrast: Double = 2.0 / 255.0
}
