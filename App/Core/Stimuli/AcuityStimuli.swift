//
//  AcuityStimuli.swift
//
//  Landolt C rings and low-contrast patches: the stimuli for M5 and M2.
//
//  THE LANDOLT C IS A STANDARD, NOT A DRAWING.
//  ISO 8596 fixes the proportions exactly: outer diameter = 5 units, stroke
//  width = 1 unit, gap width = 1 unit. The "1 unit" IS the acuity being
//  measured - at 0.0 logMAR it subtends 1 arcminute, which is the definition of
//  20/20. Drawing a ring that merely looks like a C would make every number this
//  exercise produces incomparable with a clinic's, and the whole point of using
//  a Landolt C rather than a cartoon is that it is comparable.
//
//      gap_arcminutes = 10^logMAR
//      outer_diameter = 5 x gap
//
//  WHY A C AND NOT LETTERS
//  Letters differ in legibility - a Sloan E is not as hard as an S - so a letter
//  chart measures partly which letters you happened to get. A Landolt C is one
//  shape at four orientations, so every trial is the same difficulty, and the
//  guess rate is exactly 1/4 rather than "somewhere around 1/10, depending".
//
//  docs/03-EXERCISE-CATALOG.md M5 and M2.
//

import CoreGraphics
import Foundation

// MARK: - Landolt C

struct LandoltParameters: Hashable, Sendable {

    /// Gap direction in degrees, clockwise from up. Always a multiple of 90 for
    /// the 4-alternative version.
    var gapDirectionDegrees: Double

    /// Acuity being presented. The gap subtends 10^logMAR arcminutes.
    var logMAR: Double

    /// From the user's calibration. Everything angular routes through this.
    var pointsPerDegree: Double

    /// Michelson contrast of the ring against the background. Held high for an
    /// acuity task - we are measuring resolution, not contrast sensitivity, and
    /// letting contrast vary would confound the two.
    var contrast: Double = 0.9

    /// Gap width in arcminutes. This is the quantity being measured.
    var gapArcminutes: Double { pow(10, logMAR) }

    var gapPoints: Double { gapArcminutes * (pointsPerDegree / 60.0) }

    /// ISO 8596: outer diameter is five gap widths.
    var outerDiameterPoints: Double { gapPoints * 5 }

    /// Stroke is one gap width.
    var strokePoints: Double { gapPoints }

    /// The whole canvas, with room for the ring plus a margin.
    var canvasPoints: Double { outerDiameterPoints * 1.6 }
}

enum LandoltGenerator {

    /// Renders a Landolt C on mid-grey.
    ///
    /// Mid-grey rather than white for the same reason every other stimulus here
    /// uses it: a dark ring on white can only ever be negative contrast, so the
    /// exercise could not later be run in reverse polarity, and the background
    /// luminance would differ from every other exercise in the session. Constant
    /// adaptation state across a session is not a detail - a step change in
    /// background luminance costs the eye seconds of readaptation, during which
    /// the trials are measuring recovery rather than acuity.
    static func makeImage(_ parameters: LandoltParameters, scale: Double = 2.0) -> CGImage? {
        let side = Int((parameters.canvasPoints * scale).rounded())
        guard side > 8, side <= 4096 else { return nil }

        guard let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // Mid-grey field.
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        // Ring luminance: symmetric about mid-grey, so contrast means what it
        // says on the Michelson definition.
        let ringGray = 0.5 - 0.5 * parameters.contrast

        let centre = Double(side) / 2
        let outer = parameters.outerDiameterPoints * scale
        let stroke = parameters.strokePoints * scale
        let radius = (outer - stroke) / 2      // centreline of the stroke

        context.setStrokeColor(gray: ringGray, alpha: 1)
        context.setLineWidth(stroke)
        context.setLineCap(.butt)

        // The gap subtends one stroke width at the ring's centreline, which in
        // angle is gap / circumference of that centreline.
        let gapAngle = stroke / radius        // radians, small-angle exact enough here
        let start = parameters.gapDirectionDegrees * .pi / 180

        context.addArc(center: CGPoint(x: centre, y: centre),
                       radius: radius,
                       startAngle: start + gapAngle / 2,
                       endAngle: start - gapAngle / 2 + 2 * .pi,
                       clockwise: false)
        context.strokePath()

        return context.makeImage()
    }

    /// The four gap directions, in the order the answer buttons appear.
    /// Four rather than eight: eight alternatives halves the guess rate but the
    /// diagonal directions are genuinely harder to name than the cardinal ones,
    /// so an 8AFC Landolt measures naming as well as acuity, especially in
    /// children. 4AFC keeps the task purely visual.
    static let directions: [Double] = [0, 90, 180, 270]
}

// MARK: - Low-contrast patch (M2)

enum ContrastPatchGenerator {

    /// Renders a Gabor at a given contrast, for the contrast-detection task.
    /// Reuses the Gabor path because a windowed grating is frequency-specific,
    /// which a soft blob is not - the whole point of a contrast SENSITIVITY
    /// measure is that it is measured at a stated spatial frequency.
    static func makeImage(contrast: Double,
                          cyclesPerDegree: Double,
                          orientationDegrees: Double,
                          phase: Double,
                          pointsPerDegree: Double,
                          patchDegrees: Double = 3.0,
                          scale: Double = 2.0) -> CGImage? {
        let parameters = GaborParameters(
            orientationDegrees: orientationDegrees,
            cyclesPerDegree: cyclesPerDegree,
            contrast: contrast,
            sigmaDegrees: patchDegrees / 6,
            phase: phase,
            sizePoints: pointsPerDegree * patchDegrees,
            pointsPerDegree: pointsPerDegree
        )
        return GaborGenerator.makeImage(parameters, scale: scale)
    }

    /// The four screen positions a target can occupy, as unit offsets from
    /// centre. Corners rather than edge midpoints so eccentricity is equal for
    /// all four - unequal eccentricity would make some quadrants reliably easier
    /// and the staircase would average over a difficulty it cannot see.
    static let quadrantOffsets: [CGPoint] = [
        CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1),
        CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)
    ]
}
