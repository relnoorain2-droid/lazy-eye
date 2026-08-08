//
//  HyperacuityStimuli.swift
//
//  Vernier offsets, Glass patterns, and crowded Gabor triplets — the stimuli for
//  M4, M8 and M3.
//
//  THE SUB-PIXEL POINT, WHICH IS NOT A TRICK.
//  Vernier acuity is a HYPERACUITY: people reliably detect misalignments of
//  5-10 arcseconds, which is finer than the spacing of their own photoreceptors
//  and, on a phone, finer than one pixel. That is not a paradox — the visual
//  system reads the luminance CENTROID of a feature, and an antialiased line
//  shifts its centroid continuously as the geometry moves by a fraction of a
//  pixel. So sub-pixel offsets are genuinely perceptible, and CoreGraphics
//  antialiasing is doing real work rather than papering over a rounding error.
//
//  The limit is how finely the 8-bit framebuffer can express that centroid
//  shift, which is why M4's render limit is 0.35 pt rather than 1 pt: below
//  about a third of a pixel the centroid step stops being monotonic and the
//  staircase would be measuring quantisation.
//
//  docs/03-EXERCISE-CATALOG.md M3, M4, M8.
//

import CoreGraphics
import Foundation

// MARK: - M4 · Vernier

struct VernierParameters: Hashable, Sendable {

    /// Horizontal offset of the upper segment, in arcseconds. Positive = right.
    var offsetArcseconds: Double

    var pointsPerDegree: Double

    /// Length of each segment in degrees. Long enough to give the visual system
    /// a clear axis to judge against, short enough to stay in central vision.
    var segmentDegrees: Double = 0.5

    /// Gap between the two segments in degrees. A gap is required: with the
    /// segments touching, the task becomes detecting a kink in a single line,
    /// which is an easier and different judgement.
    var gapDegrees: Double = 0.15

    var lineWidthPoints: Double = 2

    var contrast: Double = 0.9

    var offsetPoints: Double {
        (offsetArcseconds / 3600.0) * pointsPerDegree
    }

    var segmentPoints: Double { segmentDegrees * pointsPerDegree }
    var gapPoints: Double { gapDegrees * pointsPerDegree }

    var canvasWidth: Double { max(segmentPoints, 40) }
    var canvasHeight: Double { segmentPoints * 2 + gapPoints }
}

enum VernierGenerator {

    /// Two vertical segments, the upper one offset horizontally.
    ///
    /// Antialiasing is explicitly ON. It is the mechanism, not a cosmetic
    /// preference — with it off, every offset below one point rounds to zero and
    /// the staircase measures nothing while appearing to work perfectly.
    static func makeImage(_ p: VernierParameters, scale: Double = 2.0) -> CGImage? {
        let width = Int((p.canvasWidth * scale).rounded())
        let height = Int((p.canvasHeight * scale).rounded())
        guard width > 4, height > 4, width <= 4096, height <= 4096 else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        let lineGray = 0.5 - 0.5 * p.contrast
        context.setStrokeColor(gray: lineGray, alpha: 1)
        context.setLineWidth(p.lineWidthPoints * scale)
        context.setLineCap(.butt)

        let centreX = Double(width) / 2
        let segment = p.segmentPoints * scale
        let gap = p.gapPoints * scale
        let offset = p.offsetPoints * scale

        // Lower segment: reference, always centred.
        context.move(to: CGPoint(x: centreX, y: 0))
        context.addLine(to: CGPoint(x: centreX, y: segment))
        // Upper segment: displaced by the amount under test.
        context.move(to: CGPoint(x: centreX + offset, y: segment + gap))
        context.addLine(to: CGPoint(x: centreX + offset, y: segment * 2 + gap))
        context.strokePath()

        return context.makeImage()
    }

    /// Smallest offset whose centroid shift is still monotonic in 8-bit output.
    /// Below this the rendered result stops changing with the geometry.
    static let minimumTrustworthyOffsetPoints: Double = 0.35
}

// MARK: - M8 · Glass pattern

struct GlassPatternParameters: Hashable, Sendable {

    enum Form: Int, CaseIterable, Sendable {
        case concentric = 0
        case radial = 1
    }

    var form: Form

    /// Fraction of dots belonging to correlated pairs, 0...1. The rest are
    /// positioned independently and act as noise. This is the staircase axis.
    var signalFraction: Double

    /// Total dot pairs drawn.
    var pairCount: Int = 300

    /// Separation within a correlated pair, in degrees.
    var pairSeparationDegrees: Double = 0.15

    var dotDiameterPoints: Double = 3

    /// 6.5 degrees, not 8.
    ///
    /// SIZED FOR THE NARROWEST SUPPORTED WINDOW, DELIBERATELY.
    /// An 8-degree field is 314 pt on an iPhone SE, which does not fit a 320 pt
    /// portrait screen — the field would be clipped, and a clipped Glass pattern
    /// has its outer ring cut off, which is exactly where the concentric form is
    /// most readable. The angular size is then held CONSTANT across devices
    /// rather than fitted per-device: a stimulus that is 8 degrees on an iPad and
    /// 6 on a phone is not the same exercise, and the whole point of calibrating
    /// is that a threshold means the same thing everywhere.
    var fieldDegrees: Double = 6.5

    var pointsPerDegree: Double

    var contrast: Double = 0.9

    var fieldPoints: Double { fieldDegrees * pointsPerDegree }
}

enum GlassPatternGenerator {

    /// A Glass pattern: dot pairs whose orientation follows a global geometric
    /// rule. Global form perception (the ventral stream) is what reads it, and
    /// no local region contains the answer — which is exactly why it probes
    /// something the acuity and contrast tasks do not.
    static func makeImage(_ p: GlassPatternParameters,
                          generator: inout SeededGenerator,
                          scale: Double = 2.0) -> CGImage? {
        let side = Int((p.fieldPoints * scale).rounded())
        guard side > 16, side <= 4096 else { return nil }

        guard let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setShouldAntialias(true)

        let dotGray = 0.5 - 0.5 * p.contrast
        context.setFillColor(gray: dotGray, alpha: 1)

        let centre = Double(side) / 2
        let radius = centre * 0.95
        let separation = p.pairSeparationDegrees * p.pointsPerDegree * scale
        let dot = p.dotDiameterPoints * scale

        for _ in 0..<p.pairCount {
            // Uniform over the disc: sqrt keeps density even, otherwise dots
            // crowd the centre and the pattern is readable from density alone.
            let angle = Double.random(in: 0..<(2 * .pi), using: &generator)
            let r = radius * Double.random(in: 0..<1, using: &generator).squareRoot()
            let x = centre + r * cos(angle)
            let y = centre + r * sin(angle)

            let isSignal = Double.random(in: 0..<1, using: &generator) < p.signalFraction

            let partnerAngle: Double
            if isSignal {
                // Concentric: partner lies tangentially. Radial: along the ray.
                partnerAngle = p.form == .concentric ? angle + .pi / 2 : angle
            } else {
                partnerAngle = Double.random(in: 0..<(2 * .pi), using: &generator)
            }

            let px = x + separation * cos(partnerAngle)
            let py = y + separation * sin(partnerAngle)

            for point in [CGPoint(x: x, y: y), CGPoint(x: px, y: py)] {
                context.fillEllipse(in: CGRect(x: point.x - dot / 2,
                                               y: point.y - dot / 2,
                                               width: dot, height: dot))
            }
        }
        return context.makeImage()
    }
}

// MARK: - M3 · Crowded Gabor

struct CrowdedGaborParameters: Hashable, Sendable {

    /// Orientation of the CENTRE patch — the one being judged.
    var centreOrientationDegrees: Double

    /// Centre-to-centre distance to each flanker, in wavelengths (λ) of the
    /// carrier. Wavelengths rather than degrees because the lateral-masking
    /// literature is parameterised that way, and the effect scales with λ.
    var separationLambda: Double

    var cyclesPerDegree: Double = 3
    var centreContrast: Double = 0.35
    var flankerContrast: Double = 0.9
    /// 1.5 degrees, paired with an 8-lambda maximum separation, so the widest
    /// triplet is 268 pt — inside a 320 pt portrait window. At 2 degrees and
    /// 12 lambda the triplet was 392 pt and the flankers fell off the screen,
    /// which silently turns a crowding task into an uncrowded one.
    var patchDegrees: Double = 1.5
    var pointsPerDegree: Double

    var phase: Double = 0
    var flankerPhase: Double = 0

    /// One wavelength in degrees is the reciprocal of spatial frequency.
    var lambdaDegrees: Double { 1.0 / cyclesPerDegree }

    var separationPoints: Double {
        separationLambda * lambdaDegrees * pointsPerDegree
    }

    var patchPoints: Double { patchDegrees * pointsPerDegree }

    /// Canvas has to hold the centre plus a flanker on each side.
    var canvasWidth: Double { separationPoints * 2 + patchPoints }
    var canvasHeight: Double { patchPoints }
}

enum CrowdedGaborGenerator {

    /// Centre Gabor with a high-contrast flanker either side.
    ///
    /// Crowding — the way a target becomes unidentifiable when flanked, even
    /// though it is perfectly visible alone — is disproportionately severe in
    /// amblyopia. That makes it a specific deficit rather than a general one,
    /// and it is why this exercise measures separation rather than size.
    static func makeImage(_ p: CrowdedGaborParameters, scale: Double = 2.0) -> CGImage? {
        let width = Int((p.canvasWidth * scale).rounded())
        let height = Int((p.canvasHeight * scale).rounded())
        guard width > 8, height > 8, width <= 4096, height <= 4096 else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let patchSide = p.patchPoints
        let centreX = Double(width) / (2 * scale)
        let centreY = Double(height) / (2 * scale)
        let separation = p.separationPoints

        func draw(orientation: Double, contrast: Double, phase: Double, atX x: Double) {
            let parameters = GaborParameters(
                orientationDegrees: orientation,
                cyclesPerDegree: p.cyclesPerDegree,
                contrast: contrast,
                sigmaDegrees: p.patchDegrees / 6,
                phase: phase,
                sizePoints: patchSide,
                pointsPerDegree: p.pointsPerDegree
            )
            guard let patch = GaborGenerator.makeImage(parameters, scale: scale) else { return }
            let rect = CGRect(x: (x - patchSide / 2) * scale,
                              y: (centreY - patchSide / 2) * scale,
                              width: patchSide * scale, height: patchSide * scale)
            context.draw(patch, in: rect)
        }

        // Flankers are vertical; the centre is tilted. A fixed flanker
        // orientation keeps the crowding effect constant across trials, so the
        // only thing varying is separation.
        draw(orientation: 90, contrast: p.flankerContrast,
             phase: p.flankerPhase, atX: centreX - separation)
        draw(orientation: 90, contrast: p.flankerContrast,
             phase: p.flankerPhase, atX: centreX + separation)
        draw(orientation: p.centreOrientationDegrees, contrast: p.centreContrast,
             phase: p.phase, atX: centreX)

        return context.makeImage()
    }
}
