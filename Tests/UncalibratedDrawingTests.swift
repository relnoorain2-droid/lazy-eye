//
//  UncalibratedDrawingTests.swift
//
//  An uncalibrated profile must still DRAW something.
//
//  WHAT WENT WRONG, BECAUSE THE TEST ONLY MAKES SENSE WITH IT.
//  `points(forDegrees:)` returns zero for an uncalibrated profile, deliberately
//  — a measurement app must not hand back a size it cannot justify, and
//  `CalibrationGeometryTests.incompleteIsSafe` has pinned that from the start.
//
//  Nothing handled the zero. `GameField` clamped it with `max(_, 1)`, so an
//  uncalibrated user got a 9x12 POINT play area: the entire game inside a
//  smudge smaller than a fingernail. On device, Rhythm Tap and Maze Runner were
//  blank grey rectangles and Star Tracer showed a few red specks over "0 of 4
//  joined". Three exercises that looked broken, from one unhandled return value
//  in a function that was behaving exactly as designed.
//
//  Both halves are now tested: the model still refuses to invent a measurement,
//  and the drawing path still produces a usable field.
//

import Testing
import Foundation
@testable import Amblyo

@MainActor
@Suite("Uncalibrated drawing")
struct UncalibratedDrawingTests {

    private var uncalibrated: CalibrationProfile {
        CalibrationProfile(screenPointsPerCM: 0, viewingDistanceCM: 50)
    }

    @Test("the model still refuses to invent a measurement")
    func measurementStillReturnsZero() {
        // The original principle, unchanged. If this ever starts returning a
        // number, every threshold in the app becomes unverifiable.
        #expect(uncalibrated.points(forDegrees: 1.0) == 0)
        #expect(uncalibrated.isComplete == false)
    }

    @Test("but the drawing profile gives a usable scale")
    func drawingProfileIsUsable() {
        let drawing = uncalibrated.forDrawing
        #expect(drawing.isComplete, "forDrawing must be usable, that is its job")

        // A degree should be tens of points, not one. The exact value is a
        // documented typical phone; what this pins is the ORDER OF MAGNITUDE,
        // because the bug was three orders out.
        let perDegree = drawing.points(forDegrees: 1.0)
        #expect(perDegree > 20 && perDegree < 80,
                "\(perDegree) points per degree is not a plausible phone")
    }

    @Test("a calibrated profile is never substituted")
    func realCalibrationIsLeftAlone() {
        // The substitution must be invisible to anyone who HAS measured. If
        // `forDrawing` ever replaced a real profile, every session after
        // calibration would silently be measured at the stand-in's geometry.
        let real = CalibrationProfile(screenPointsPerCM: 44.0, viewingDistanceCM: 42)
        #expect(real.forDrawing.screenPointsPerCM == 44.0)
        #expect(real.forDrawing.viewingDistanceCM == 42)
    }

    @Test("the game field is a real play area, not a smudge")
    func gameFieldIsUsableWhenUncalibrated() {
        // THE ACTUAL BUG. 9 degrees at 1 point per degree is 9 points wide.
        let broken = GameField(calibration: uncalibrated)
        #expect(broken.widthPoints < 20,
                "if this is now large, the model started inventing sizes")

        let fixed = GameField(calibration: uncalibrated.forDrawing)
        #expect(fixed.widthPoints > 200,
                "a 9-degree field came out \(fixed.widthPoints) points wide")
        #expect(fixed.heightPoints > 300)
    }

    @Test("every game's field is drawable on an uncalibrated profile")
    func everyGameHasAFieldToDrawIn() {
        // Iterates the registry rather than naming the three that were seen to
        // fail, because the three that were seen were only the three that were
        // opened.
        let drawing = uncalibrated.forDrawing
        let field = GameField(calibration: drawing)
        for descriptor in ExerciseRegistry.all where descriptor.track == .game {
            #expect(field.points(1.0) > 20,
                    "\(descriptor.id) would draw at \(field.points(1.0)) pt/deg")
        }
    }
}
