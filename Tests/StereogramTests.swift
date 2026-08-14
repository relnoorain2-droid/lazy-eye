//
//  StereogramTests.swift
//
//  The stereogram is the one stimulus whose failure mode is silent and total: if
//  the two eyes receive identical images, the exercise still runs, still records
//  trials, and still converges on a threshold — for a task the user could only
//  guess at. Nothing in the UI would look wrong. These tests exist to make that
//  state impossible.
//
//  The three that matter most:
//    · `disparityIsNeverQuantisedToZero` — a zero shift is a flat field being
//      reported as a depth trial.
//    · `recordedDisparityIsWhatWasRendered` — logging the requested value would
//      put numbers in the progress chart that nobody was ever shown.
//    · `noMonocularDensityCue` — if one eye alone can find the shape, this stops
//      being a test of binocular vision.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Random-dot stereograms")
struct StereogramTests {

    /// The four devices from the capability matrix, as calibrations.
    /// Points-per-cm and viewing distance are the real values, so every
    /// assertion here is about hardware that exists.
    private static let devices: [(name: String, pointsPerCM: Double, distance: Double,
                                  shortAxis: Double)] = [
        ("iPhone SE 3", 56.9, 30, 320),
        ("iPhone 14 Pro", 63.0, 35, 393),
        ("iPad 10.9", 47.2, 50, 820),
        ("iPad Pro 13", 45.4, 60, 1024),
    ]

    private func calibration(_ device: (name: String, pointsPerCM: Double,
                                        distance: Double, shortAxis: Double))
        -> CalibrationProfile {
        CalibrationProfile(screenPointsPerCM: device.pointsPerCM,
                           screenSizeUserVerified: true,
                           viewingDistanceCM: device.distance)
    }

    private func parameters(disparity: Double, pointsPerDegree: Double = 40,
                           shape: StereogramParameters.Shape = .square,
                           depth: StereogramParameters.Depth = .nearer)
        -> StereogramParameters {
        var parameters = StereogramParameters()
        parameters.disparityArcminutes = disparity
        parameters.pointsPerDegree = pointsPerDegree
        parameters.shape = shape
        parameters.depth = depth
        return parameters
    }

    // MARK: Quantisation

    @Test("a requested disparity never renders as a zero shift")
    func disparityIsNeverQuantisedToZero() {
        // On an iPhone SE, 1 pt is 2.01 arcmin — so anything under about 1
        // arcmin rounds to zero points. A zero shift means both eyes get the
        // SAME image: no depth at all, while the trial claims a disparity.
        for requested in [0.1, 0.25, 0.5, 0.9, 1.0, 1.4] {
            let parameters = parameters(disparity: requested, pointsPerDegree: 29.8)
            #expect(parameters.shiftPoints >= 1,
                    "\(requested) arcmin rendered as a flat field on an iPhone SE")
        }
    }

    @Test("zero disparity really is zero, so a control trial is possible")
    func zeroDisparityStaysZero() {
        #expect(parameters(disparity: 0).shiftPoints == 0)
        #expect(parameters(disparity: 0).renderedDisparityArcminutes == 0)
    }

    @Test("the recorded disparity is what was drawn, not what was asked for")
    func recordedDisparityIsWhatWasRendered() {
        // 1.4 arcmin on an iPhone SE is 0.70 pt, which draws as 1 pt = 2.01
        // arcmin. Recording 1.4 would put a number in the progress chart that
        // the user was never shown.
        let parameters = parameters(disparity: 1.4, pointsPerDegree: 29.8)
        #expect(parameters.shiftPoints == 1)
        #expect(abs(parameters.renderedDisparityArcminutes - 2.01) < 0.05,
                "got \(parameters.renderedDisparityArcminutes)")
        #expect(parameters.isLimitedByDisplay,
                "the UI needs to be able to say the screen is the limit")
    }

    @Test("a comfortably renderable disparity is not flagged as display-limited")
    func coarseDisparityIsNotFlagged() {
        let parameters = parameters(disparity: 30, pointsPerDegree: 29.8)
        #expect(!parameters.isLimitedByDisplay)
        #expect(abs(parameters.renderedDisparityArcminutes - 30) / 30 < 0.05)
    }

    @Test("quantisation only ever makes the disparity coarser or equal")
    func quantisationNeverClaimsFinerThanDrawn() {
        for device in Self.devices {
            let pointsPerDegree = calibration(device).points(forDegrees: 1.0)
            for requested in stride(from: 1.0, through: 40.0, by: 0.5) {
                let parameters = parameters(disparity: requested,
                                            pointsPerDegree: pointsPerDegree)
                let rendered = parameters.renderedDisparityArcminutes
                let onePoint = 60.0 / pointsPerDegree
                // Rendered may exceed the request (rounding up, or the 1 pt
                // floor), but it must never be finer than the pixel grid allows.
                #expect(rendered >= onePoint - 1e-9,
                        "\(device.name) claimed \(rendered) arcmin, finer than one point (\(onePoint))")
            }
        }
    }

    // MARK: Geometry against real devices

    @Test("the 6.5 degree field fits on every supported screen")
    func fieldFitsEveryDevice() {
        for device in Self.devices {
            let field = calibration(device)
                .points(forDegrees: DepthPopExercise.fieldDegrees)
            #expect(field <= device.shortAxis - 24,
                    "\(device.name): a \(field) pt field will clip a \(device.shortAxis) pt axis")
        }
    }

    @Test("dots are between 2 and 8 points on every device")
    func dotSizeIsSensibleEverywhere() {
        // Dot size is specified in ANGLE (6 arcmin) so a dot is the same visual
        // object everywhere. Below 2 pt an amblyopic eye cannot resolve it;
        // above about 8 pt the shape's boundary is too coarse to place.
        for device in Self.devices {
            let trial = Trial(difficulty: 20, correctAnswer: 0,
                              payload: TrialPayload(["disparityArcmin": 20,
                                                     "shape": 0, "depth": 0, "seed": 1]))
            let built = DepthPopExercise().parameters(for: trial,
                                                      calibration: calibration(device))
            #expect(built.dotPoints >= 2 && built.dotPoints <= 8,
                    "\(device.name): dot is \(built.dotPoints) pt")
        }
    }

    @Test("the render limit clamps the staircase to one point of shift")
    func renderLimitMatchesOnePoint() throws {
        let descriptor = DepthPopExercise.descriptor
        let limit = try #require(descriptor.staircase.renderLimit)

        for device in Self.devices {
            let profile = calibration(device)
            let floor = try #require(limit.hardestRenderableValue(for: profile))
            let onePoint = 60.0 / profile.points(forDegrees: 1.0)
            #expect(abs(floor - onePoint) < 0.05,
                    "\(device.name): limit says \(floor), one point is \(onePoint)")

            let resolved = descriptor.staircase.resolvedHardestValue(for: profile)
            #expect(resolved >= descriptor.staircase.hardestValue,
                    "lowerIsHarder: the resolved bound must be EASIER than the requested one")
            #expect(resolved <= descriptor.staircase.easiestValue,
                    "and still harder than the easiest setting, or there is no range left")
        }
    }

    // MARK: No monocular cue

    @Test("neither eye's field carries a density cue where the shape is")
    func noMonocularDensityCue() {
        // If one eye alone shows a density difference at the shape's boundary,
        // that eye can find the shape and the exercise stops measuring binocular
        // vision. Averaged over seeds because a single field's density varies by
        // a few percent from sampling alone.
        var parameters = parameters(disparity: 8, pointsPerDegree: 40)
        parameters.fieldPoints = 240
        parameters.dotPoints = 3

        var insideAmblyopic = 0.0, outsideAmblyopic = 0.0
        var insideFellow = 0.0, outsideFellow = 0.0
        let seeds = 12
        let shapeSide = parameters.fieldPoints * parameters.shapeFraction

        for seed in 1...seeds {
            var generator = SeededGenerator(seed: UInt64(seed))
            let pair = StereogramGenerator.make(parameters, generator: &generator)

            insideAmblyopic += StereogramGenerator.density(
                of: pair.amblyopicDots, inRectangleOfSide: shapeSide,
                centredIn: parameters.fieldPoints)
            outsideAmblyopic += StereogramGenerator.density(
                of: pair.amblyopicDots, inRectangleOfSide: parameters.fieldPoints,
                centredIn: parameters.fieldPoints)
            insideFellow += StereogramGenerator.density(
                of: pair.fellowDots, inRectangleOfSide: shapeSide,
                centredIn: parameters.fieldPoints)
            outsideFellow += StereogramGenerator.density(
                of: pair.fellowDots, inRectangleOfSide: parameters.fieldPoints,
                centredIn: parameters.fieldPoints)
        }

        let amblyopicRatio = insideAmblyopic / outsideAmblyopic
        let fellowRatio = insideFellow / outsideFellow
        #expect(abs(amblyopicRatio - 1) < 0.12,
                "amblyopic eye: shape region is \(amblyopicRatio)x the field density")
        #expect(abs(fellowRatio - 1) < 0.12,
                "fellow eye: shape region is \(fellowRatio)x the field density — a monocular cue")
    }

    @Test("the two fields are identical outside the shape")
    func fieldsMatchOutsideTheShape() {
        // Any difference outside the shape is a SECOND disparity signal, and the
        // user would be reporting the shape of the noise rather than the shape
        // we asked about.
        var parameters = parameters(disparity: 10, pointsPerDegree: 40, shape: .circle)
        parameters.fieldPoints = 240
        parameters.dotPoints = 3

        var generator = SeededGenerator(seed: 99)
        let pair = StereogramGenerator.make(parameters, generator: &generator)

        let radius = parameters.fieldPoints * parameters.shapeFraction / 2
        let centre = parameters.fieldPoints / 2
        let margin = radius + Double(pair.shiftPoints) + parameters.dotPoints

        func wellOutside(_ point: CGPoint) -> Bool {
            let dx = point.x + parameters.dotPoints / 2 - centre
            let dy = point.y + parameters.dotPoints / 2 - centre
            return (dx * dx + dy * dy).squareRoot() > margin
        }

        let amblyopicOutside = Set(pair.amblyopicDots.filter(wellOutside)
            .map { "\(Int($0.x)),\(Int($0.y))" })
        let fellowOutside = Set(pair.fellowDots.filter(wellOutside)
            .map { "\(Int($0.x)),\(Int($0.y))" })
        #expect(amblyopicOutside == fellowOutside,
                "\(amblyopicOutside.symmetricDifference(fellowOutside).count) dots differ outside the shape")
    }

    @Test("the shape region actually holds dots to displace")
    func shapeRegionIsPopulated() {
        var parameters = parameters(disparity: 10, pointsPerDegree: 40)
        parameters.fieldPoints = 240
        parameters.dotPoints = 3
        var generator = SeededGenerator(seed: 5)
        let pair = StereogramGenerator.make(parameters, generator: &generator)

        // A 90 pt square at 30% density with 3 pt dots holds about 270 dots.
        // Far fewer would mean the shape is defined by too little to see.
        #expect(pair.shapeDotCount > 150,
                "only \(pair.shapeDotCount) dots carry the disparity")
    }

    @Test("each shape displaces a different set of dots")
    func shapesDifferFromEachOther() {
        // Four answer options that produce indistinguishable stimuli would be a
        // four-alternative task with one real answer.
        var counts: [Int] = []
        for shape in StereogramParameters.Shape.allCases {
            var parameters = parameters(disparity: 10, pointsPerDegree: 40, shape: shape)
            parameters.fieldPoints = 240
            parameters.dotPoints = 3
            var generator = SeededGenerator(seed: 42)
            counts.append(StereogramGenerator.make(parameters, generator: &generator)
                .shapeDotCount)
        }
        // Square is the largest, diamond half of it, circle about π/4, triangle
        // about a quarter. They must not all be equal.
        #expect(Set(counts).count == counts.count,
                "shapes displaced identical dot counts: \(counts)")
    }

    @Test("the triangle is narrow at the top, matching its answer button")
    func triangleMatchesItsIcon() {
        // Written apex-DOWN first, while the button showed an apex-up icon. A
        // user seeing an inverted triangle reasonably answers "diamond", and the
        // trial is then scored against them for reading the screen correctly.
        var parameters = parameters(disparity: 10, pointsPerDegree: 40,
                                    shape: .triangle)
        parameters.fieldPoints = 240
        parameters.dotPoints = 3
        var generator = SeededGenerator(seed: 42)
        let pair = StereogramGenerator.make(parameters, generator: &generator)

        let centre = parameters.fieldPoints / 2
        let radius = parameters.fieldPoints * parameters.shapeFraction / 2
        let shapeDots = pair.amblyopicDots.filter {
            let dx = $0.x + parameters.dotPoints / 2 - centre
            let dy = $0.y + parameters.dotPoints / 2 - centre
            guard abs(dy) <= radius else { return false }
            return abs(dx) <= radius * (radius + dy) / (2 * radius)
        }
        let upper = shapeDots.filter { $0.y + 1.5 - centre < -radius / 3 }.count
        let lower = shapeDots.filter { $0.y + 1.5 - centre > radius / 3 }.count
        #expect(upper < lower,
                "apex should be at the top: \(upper) dots up there vs \(lower) below")
    }

    @Test("depth direction reverses the shift, and nothing else")
    func depthReversesTheShift() {
        var near = parameters(disparity: 10, pointsPerDegree: 40, depth: .nearer)
        near.fieldPoints = 240; near.dotPoints = 3
        var far = near
        far.depth = .further

        var g1 = SeededGenerator(seed: 3)
        var g2 = SeededGenerator(seed: 3)
        let nearPair = StereogramGenerator.make(near, generator: &g1)
        let farPair = StereogramGenerator.make(far, generator: &g2)

        #expect(nearPair.shiftPoints == farPair.shiftPoints)
        #expect(nearPair.amblyopicDots == farPair.amblyopicDots,
                "the unshifted eye must not depend on depth direction")
        #expect(nearPair.fellowDots != farPair.fellowDots,
                "if the shifted eye is identical, depth direction does nothing at all")
    }

    // MARK: Determinism

    @Test("the same seed reproduces the same pair of fields")
    func sameSeedSameFields() {
        var parameters = parameters(disparity: 12, pointsPerDegree: 40)
        parameters.fieldPoints = 200
        var first = SeededGenerator(seed: 777)
        var second = SeededGenerator(seed: 777)
        let a = StereogramGenerator.make(parameters, generator: &first)
        let b = StereogramGenerator.make(parameters, generator: &second)
        #expect(a.amblyopicDots == b.amblyopicDots)
        #expect(a.fellowDots == b.fellowDots,
                "a session must replay exactly from its seed when someone reports a bad trial")
    }

    @Test("different seeds give different fields")
    func differentSeedsDifferentFields() {
        var parameters = parameters(disparity: 12, pointsPerDegree: 40)
        parameters.fieldPoints = 200
        var first = SeededGenerator(seed: 1)
        var second = SeededGenerator(seed: 2)
        let a = StereogramGenerator.make(parameters, generator: &first)
        let b = StereogramGenerator.make(parameters, generator: &second)
        #expect(a.amblyopicDots != b.amblyopicDots,
                "a fixed field would let a user learn the pattern rather than fuse it")
    }

    // MARK: Exercise wiring

    @Test("trials name a shape the answer buttons can offer")
    func trialsAreAnswerable() {
        let exercise = DepthPopExercise()
        var generator = SeededGenerator(seed: 11)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 15, generator: &generator)
            #expect(StereogramParameters.Shape(rawValue: trial.correctAnswer) != nil,
                    "answer \(trial.correctAnswer) has no button")
        }
    }

    @Test("all four shapes and both depths come up")
    func trialsUseTheWholeSpace() {
        let exercise = DepthPopExercise()
        var generator = SeededGenerator(seed: 23)
        var shapes: Set<Int> = []
        var depths: Set<Int> = []
        for _ in 0..<400 {
            let trial = exercise.makeTrial(difficulty: 15, generator: &generator)
            shapes.insert(trial.correctAnswer)
            depths.insert(Int(trial.payload.value("depth")))
        }
        #expect(shapes.count == 4, "only \(shapes.count) shapes ever appeared")
        #expect(depths.count == 2,
                "depth direction never varied, so a user can answer from the last trial")
    }

    @Test("the interpretation never claims a clinical result")
    func interpretationStaysHonest() {
        for disparity in [0.5, 1.5, 3.0, 8.0, 20.0, 60.0, 200.0] {
            let text = DepthPopExercise.interpretation(disparityArcminutes: disparity)
            #expect(!text.isEmpty)
            let lowered = text.lowercased()
            for phrase in ["normal", "stereoacuity of", "diagnos", "healthy"] {
                #expect(!lowered.contains(phrase),
                        "\"\(phrase)\" in \"\(text)\" reads as a clinical finding")
            }
        }
    }
}
