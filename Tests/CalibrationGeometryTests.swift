//
//  CalibrationGeometryTests.swift
//
//  The angular-size maths is the foundation of every threshold this app
//  reports. If it is wrong, every chart in the app is meaningless and no test
//  further up the stack will tell you.
//
//  Reference values computed independently from size = 2·d·tan(θ/2).
//
//  docs/04-ARCHITECTURE.md section 4.
//

import Testing
import Foundation
@testable import Amblyo

struct CalibrationGeometryTests {

    /// ~11" iPad: 264 ppi ÷ 2 (points per pixel) = 132 points/inch = 51.97 pt/cm.
    /// Using a rounder figure keeps the arithmetic checkable by hand.
    private func iPadCalibration(distanceCM: Double = 50) -> CalibrationProfile {
        CalibrationProfile(
            screenPointsPerCM: 52.0,
            viewingDistanceCM: distanceCM
        )
    }

    @Test("One degree at 50 cm subtends 0.8727 cm")
    func oneDegreeAtFiftyCentimetres() {
        let cal = iPadCalibration()
        // 2 · 50 · tan(0.5°) = 0.87269 cm  ->  × 52 pt/cm = 45.38 pt
        let points = cal.points(forDegrees: 1.0)
        #expect(abs(points - 45.38) < 0.05)
    }

    @Test("Angular size scales linearly with viewing distance")
    func scalesWithDistance() {
        let near = iPadCalibration(distanceCM: 40)
        let far = iPadCalibration(distanceCM: 80)
        // Double the distance, double the points for the same angle.
        let ratio = far.points(forDegrees: 2.0) / near.points(forDegrees: 2.0)
        #expect(abs(ratio - 2.0) < 0.001)
    }

    @Test("points(forDegrees:) and degrees(forPoints:) are inverses")
    func roundTrip() {
        let cal = iPadCalibration()
        for degrees in [0.25, 0.5, 1.0, 2.5, 5.0, 10.0] {
            let points = cal.points(forDegrees: degrees)
            let back = cal.degrees(forPoints: points)
            #expect(abs(back - degrees) < 0.0001, "round trip failed at \(degrees)°")
        }
    }

    @Test("Spatial frequency converts to points per cycle")
    func pointsPerCycle() {
        let cal = iPadCalibration()
        // 3 c/deg -> one cycle spans 1/3 degree.
        let expected = cal.points(forDegrees: 1.0 / 3.0)
        #expect(abs(cal.pointsPerCycle(cyclesPerDegree: 3.0) - expected) < 0.0001)
    }

    @Test("Max renderable spatial frequency respects Nyquist")
    func nyquistCeiling() {
        let cal = iPadCalibration()
        let maxCPD = cal.maxRenderableCyclesPerDegree
        // 45.38 points per degree / 2 points per cycle = 22.7 c/deg
        #expect(abs(maxCPD - 22.69) < 0.1)

        // A grating at the ceiling must be exactly 2 points per cycle.
        #expect(abs(cal.pointsPerCycle(cyclesPerDegree: maxCPD) - 2.0) < 0.01)
    }

    @Test("Sitting further away raises the renderable spatial frequency ceiling")
    func distanceRaisesCeiling() {
        #expect(iPadCalibration(distanceCM: 80).maxRenderableCyclesPerDegree
                > iPadCalibration(distanceCM: 40).maxRenderableCyclesPerDegree)
    }

    @Test("Incomplete calibration returns zero rather than a wrong number")
    func incompleteIsSafe() {
        let uncalibrated = CalibrationProfile(screenPointsPerCM: 0, viewingDistanceCM: 50)
        #expect(uncalibrated.isComplete == false)
        #expect(uncalibrated.points(forDegrees: 1.0) == 0)
        #expect(uncalibrated.maxRenderableCyclesPerDegree == 0)
    }

    @Test("Crosstalk above 25% is rejected")
    func crosstalkThreshold() {
        let cal = iPadCalibration()
        cal.redLeakIntoCyan = 0.08
        cal.cyanLeakIntoRed = 0.06
        #expect(cal.crosstalkIsAcceptable)

        cal.redLeakIntoCyan = 0.31
        #expect(cal.crosstalkIsAcceptable == false)
    }

    @Test("Dichoptic track requires calibration and normal colour vision")
    func dichopticGating() {
        let profile = Profile(name: "Test")
        #expect(profile.canUseDichopticTrack == false, "no calibration yet")

        let cal = iPadCalibration()
        cal.anaglyphCalibratedAt = .now
        cal.colorVisionOK = true
        profile.calibration = cal
        #expect(profile.canUseDichopticTrack)

        cal.colorVisionOK = false
        #expect(profile.canUseDichopticTrack == false,
                "colour-blind users must be routed to the monocular track")
    }
}
