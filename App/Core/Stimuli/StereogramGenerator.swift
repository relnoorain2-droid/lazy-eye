//
//  StereogramGenerator.swift
//
//  Random-dot stereograms: the one stimulus in this app that is completely
//  invisible to either eye alone.
//
//  WHY THAT MATTERS
//  Every other dichoptic exercise here can be *partly* cheated — you can often
//  half-do a matching task with one eye and guess the rest. A random-dot
//  stereogram cannot. Each eye sees uniform noise; the shape exists only in the
//  disparity between the two. If a user reports the shape, their visual system
//  fused two images, and that is a fact about them rather than about the app.
//
//  THE DISPARITY IS A HORIZONTAL PIXEL SHIFT, AND THAT IS THE WHOLE CONSTRAINT
//  Depth here IS the shift. Verified against the real device table before any of
//  this was written:
//
//      device           1 pt of shift equals
//      iPhone SE 3      2.01 arcmin  (121 arcsec) at 30 cm
//      iPhone 14 Pro    1.56 arcmin  ( 94 arcsec) at 35 cm
//      iPad 10.9        1.46 arcmin  ( 87 arcsec) at 50 cm
//      iPad Pro 13      1.26 arcmin  ( 76 arcsec) at 60 cm
//
//  So a requested disparity of 1 arcmin rounds to ZERO points on an iPhone SE:
//  the two eyes would receive identical images, there would be no depth at all,
//  and the staircase would happily converge on a number while the observer was
//  guessing at flat noise. This is the same class of defect as M13's degrees /
//  arcminutes mix-up, and it is invisible in code review — the arithmetic is
//  right, the pixels are not there.
//
//  Two things follow, and both are load-bearing:
//    1. The exercise's `RenderLimit` is one point of shift, so the staircase is
//       never asked for a disparity this display cannot present.
//    2. `renderedDisparityArcminutes` reports what was ACTUALLY drawn after
//       quantisation, and that — not the requested value — is what gets recorded
//       as the trial's difficulty.
//
//  SUB-PIXEL SHIFTS ARE NOT A WAY AROUND IT
//  A 0.4 pt shift renders as antialiasing on both edges of a dot. That is a blur
//  cue, identical in both eyes, and blur is not disparity. Shifts are whole
//  points, always.
//
//  THE VACATED STRIP MUST BE REFILLED
//  Shifting a region's dots leaves a gap at its trailing edge. Left empty, that
//  gap is a hard-edged vertical band of background — roughly 6 dots' worth of
//  missing noise at 2 pt of shift — and it is plainly visible with one eye shut.
//  That single omission would turn a stereo test into a monocular one while
//  every number in the log stayed plausible. The strip is refilled with fresh
//  random dots, which is also why the generator needs its own RNG draw rather
//  than only permuting the base field.
//
//  docs/03-EXERCISE-CATALOG.md D6, docs/01-RESEARCH-BRIEF.md section 4.
//

import CoreGraphics
import Foundation

struct StereogramParameters: Sendable, Equatable {

    /// Which of the four quadrant shapes carries the disparity.
    enum Shape: Int, CaseIterable, Sendable {
        case square = 0, circle = 1, triangle = 2, diamond = 3

        var label: String {
            switch self {
            case .square: "Square"
            case .circle: "Circle"
            case .triangle: "Triangle"
            case .diamond: "Diamond"
            }
        }

        var systemImage: String {
            switch self {
            case .square: "square"
            case .circle: "circle"
            case .triangle: "triangle"
            case .diamond: "diamond"
            }
        }
    }

    /// Whether the shape sits in front of the background or behind it.
    /// Randomised per trial: a user who learns "it always pops forward" starts
    /// answering from memory of the last trial rather than from what they see.
    enum Depth: Int, Sendable { case nearer = 0, further = 1 }

    var shape: Shape = .square
    var depth: Depth = .nearer

    /// Requested disparity. What is actually rendered is
    /// `renderedDisparityArcminutes`, which may be coarser.
    var disparityArcminutes: Double = 20

    var pointsPerDegree: Double = 40

    /// Whole field, in points. Square.
    var fieldPoints: Double = 240

    /// Shape size as a fraction of the field. 0.375 puts a 3° shape in an 8°
    /// field, which is the classic proportion — big enough to identify, small
    /// enough that its edges are well inside the field.
    var shapeFraction: Double = 0.375

    /// Dot edge length in points. Verified to land near 6 arcmin on every
    /// supported device: 3 pt on an iPhone SE, 5 pt on an iPad Pro. Smaller dots
    /// stop being resolvable by an amblyopic eye, larger ones make the shape's
    /// boundary too coarse to place.
    var dotPoints: Double = 3

    /// Fraction of cells carrying a dot. 0.30 is dense enough to define a
    /// boundary and sparse enough that dots do not merge into texture.
    var dotDensity: Double = 0.30

    var contrast: Double = 0.9

    /// Horizontal shift in points, before quantisation.
    var rawShiftPoints: Double {
        let radians = (disparityArcminutes / 60.0) * .pi / 180.0
        // Small-angle: shift = θ · pointsPerRadian. Using the exact
        // 2·d·tan(θ/2) form and then converting to points gives the same value
        // to within 1e-6 at these angles, and this form does not need the
        // viewing distance twice.
        return radians * (pointsPerDegree * 180.0 / .pi)
    }

    /// The shift actually drawn: whole points, and never zero when a disparity
    /// was asked for, because a zero shift is a flat field being reported as a
    /// depth trial.
    var shiftPoints: Int {
        let rounded = Int(rawShiftPoints.rounded())
        return disparityArcminutes > 0 ? max(1, rounded) : 0
    }

    /// The disparity the user was actually shown. This is what gets recorded.
    var renderedDisparityArcminutes: Double {
        guard pointsPerDegree > 0 else { return 0 }
        return Double(shiftPoints) / pointsPerDegree * 60.0
    }

    /// True when quantisation moved the disparity by more than a tenth of what
    /// was asked. The UI can then say "this screen is the limit, not your eyes".
    var isLimitedByDisplay: Bool {
        guard disparityArcminutes > 0 else { return false }
        return abs(renderedDisparityArcminutes - disparityArcminutes)
            / disparityArcminutes > 0.1
    }
}

/// One eye's dot field, plus the disparity that produced it.
struct StereogramPair: Sendable {
    /// Dot origins in points, for the eye that sees the unshifted field.
    let amblyopicDots: [CGPoint]
    /// Dot origins for the eye whose in-shape dots are displaced.
    let fellowDots: [CGPoint]
    let dotPoints: Double
    let fieldPoints: Double
    let renderedDisparityArcminutes: Double
    let shiftPoints: Int

    /// Dots in the shape region of the unshifted field. Used only by tests and
    /// the no-glasses preview — never to draw a boundary, which would hand the
    /// answer to one eye.
    let shapeDotCount: Int
}

enum StereogramGenerator {

    /// Builds both eyes' fields.
    ///
    /// The two fields are IDENTICAL outside the shape. That is not an
    /// optimisation — it is the requirement. Any difference outside the shape is
    /// a second disparity signal, and the user would be reporting the shape of
    /// the noise rather than the shape we asked about.
    static func make(_ parameters: StereogramParameters,
                     generator: inout SeededGenerator) -> StereogramPair {

        let field = max(parameters.fieldPoints, 1)
        let dot = max(parameters.dotPoints, 1)
        let columns = max(Int(field / dot), 1)
        let rows = columns
        let shift = parameters.shiftPoints

        // Signed shift: a nearer shape is displaced toward the nose (crossed
        // disparity), a further one away from it. Getting the SIGN wrong does not
        // break the task — the shape is still identifiable — but it inverts the
        // depth, so a user answering "in front" correctly would be marked wrong.
        let signedShift = parameters.depth == .nearer ? shift : -shift

        let radius = field * parameters.shapeFraction / 2
        let centre = CGPoint(x: field / 2, y: field / 2)

        func isInShape(_ x: Double, _ y: Double) -> Bool {
            let dx = x + dot / 2 - centre.x
            let dy = y + dot / 2 - centre.y
            switch parameters.shape {
            case .square:
                return abs(dx) <= radius && abs(dy) <= radius
            case .circle:
                return dx * dx + dy * dy <= radius * radius
            case .triangle:
                // Apex UP, which in screen coordinates means the narrow end is
                // at negative dy. Written the other way round first, which drew
                // an apex-down triangle while the answer button showed an
                // apex-up icon — a user seeing an inverted triangle reasonably
                // answers "diamond", and the trial is scored against them for
                // reading the screen correctly.
                guard dy >= -radius, dy <= radius else { return false }
                let halfWidth = radius * (radius + dy) / (2 * radius)
                return abs(dx) <= halfWidth
            case .diamond:
                return abs(dx) + abs(dy) <= radius
            }
        }

        var amblyopic: [CGPoint] = []
        var fellow: [CGPoint] = []
        var shapeCount = 0

        for row in 0..<rows {
            let y = Double(row) * dot

            // The shape's horizontal extent on THIS row, found by scanning
            // rather than solved per shape. Scanning costs nothing at these
            // sizes and means adding a fifth shape needs no second derivation
            // that could disagree with `isInShape`.
            var firstInShape: Int?
            var lastInShape: Int?
            for column in 0..<columns where isInShape(Double(column) * dot, y) {
                if firstInShape == nil { firstInShape = column }
                lastInShape = column
            }

            for column in 0..<columns {
                // One RNG draw per cell, occupied or not, so the field is a
                // deterministic function of the seed. Drawing only for occupied
                // cells would make each dot's position depend on how many came
                // before it, and the same seed would stop reproducing the same
                // field.
                let occupied = Double(generator.next() % 1_000) / 1_000.0
                    < parameters.dotDensity
                guard occupied else { continue }

                let x = Double(column) * dot
                amblyopic.append(CGPoint(x: x, y: y))

                if isInShape(x, y) {
                    shapeCount += 1
                    let moved = x + Double(signedShift)
                    // Dropped rather than clamped if it leaves the field.
                    // Clamping would pile dots against one edge — a monocular
                    // density cue exactly where the boundary is.
                    if moved >= 0, moved <= field - dot {
                        fellow.append(CGPoint(x: moved, y: y))
                    }
                } else {
                    fellow.append(CGPoint(x: x, y: y))
                }
            }

            // Refill the sliver the shift vacated at the shape's trailing edge.
            // Left empty it is a gap of exactly `shift` points running down one
            // side of the shape, visible with one eye shut — which would quietly
            // turn a stereo test into a monocular shape-spotting test. Refilling
            // needs its own RNG draws, which is why the generator is not simply
            // a permutation of the base field.
            if shift != 0, let first = firstInShape, let last = lastInShape {
                let stripStart = signedShift > 0
                    ? Double(first) * dot
                    : Double(last) * dot + dot + Double(signedShift)
                let stripEnd = stripStart + Double(abs(signedShift))

                // STEP BY THE DOT WIDTH, NOT BY ONE POINT, and scale the last
                // partial position by how much of it falls inside the strip.
                //
                // Stepping by one point was the first version and it was wrong
                // in the worst possible way: it made three draws per dot-width,
                // so the refilled strip came out at 3x the field's density at
                // every shift — a bright band running down the shape's edge,
                // plainly visible with one eye shut. The refill exists to remove
                // a monocular cue and instead introduced a louder one. Measured
                // before this was written: 45 dots where 15 belonged, at a 5 pt
                // shift.
                //
                // With this form the expected count is density x strip-width /
                // dot, which is exactly the field's density over the strip.
                var x = stripStart
                while x < stripEnd {
                    let overlap = Swift.min(1.0, (stripEnd - x) / dot)
                    let sample = Double(generator.next() % 1_000) / 1_000.0
                    if sample < parameters.dotDensity * overlap,
                       x >= 0, x <= field - dot {
                        fellow.append(CGPoint(x: x, y: y))
                    }
                    x += dot
                }
            }
        }

        return StereogramPair(
            amblyopicDots: amblyopic,
            fellowDots: fellow,
            dotPoints: dot,
            fieldPoints: field,
            renderedDisparityArcminutes: parameters.renderedDisparityArcminutes,
            shiftPoints: shift,
            shapeDotCount: shapeCount)
    }

    /// Density of dots inside a rectangle, per 1,000 square points. Used by the
    /// tests to assert that neither eye's field carries a monocular density cue
    /// where the shape is.
    static func density(of dots: [CGPoint], inRectangleOfSide side: Double,
                        centredIn field: Double) -> Double {
        let low = (field - side) / 2
        let high = (field + side) / 2
        let inside = dots.filter {
            $0.x >= low && $0.x < high && $0.y >= low && $0.y < high
        }.count
        guard side > 0 else { return 0 }
        return Double(inside) / (side * side) * 1_000
    }
}
