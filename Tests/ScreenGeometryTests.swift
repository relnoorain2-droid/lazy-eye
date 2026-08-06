//
//  ScreenGeometryTests.swift
//
//  The device table and its fallbacks. A wrong value here silently corrupts
//  every threshold the app ever reports, and nothing further up the stack would
//  reveal it — so the checks are deliberately paranoid.
//

import Testing
import Foundation
@testable import Amblyo

struct ScreenGeometryTests {

    // MARK: Table integrity

    @Test("Every table entry is a plausible panel density")
    func tableValuesArePlausible() {
        for (identifier, ppi) in ScreenGeometry.exactTable {
            #expect(ppi >= 260 && ppi <= 480, "\(identifier) has an implausible \(ppi) ppi")
        }
    }

    @Test("The table covers the oldest iOS 17 iPads — the hand-me-down devices")
    func coversOldestSupportedIPads() {
        // These three are exactly what iPadOS 18 dropped and why the deployment
        // target is 17. If they ever fall out of the table, the reason for the
        // lower target has been lost.
        for identifier in ["iPad6,11", "iPad6,12",   // iPad 6th gen (2018)
                           "iPad7,3", "iPad7,4",     // iPad Pro 10.5"
                           "iPad7,1", "iPad7,2"] {   // iPad Pro 12.9" 2nd gen
            #expect(ScreenGeometry.exactTable[identifier] == 264,
                    "\(identifier) missing — see docs/DECISIONS.md section 6")
        }
    }

    @Test("Every full-size iPad is 264 ppi and every mini is 326 ppi")
    func iPadDensitiesAreConsistent() {
        let minis: Set<String> = ["iPad11,1", "iPad11,2", "iPad14,1", "iPad14,2",
                                  "iPad16,1", "iPad16,2"]
        for (identifier, ppi) in ScreenGeometry.exactTable where identifier.hasPrefix("iPad") {
            if minis.contains(identifier) {
                #expect(ppi == 326, "\(identifier) is a mini and must be 326 ppi")
            } else {
                #expect(ppi == 264, "\(identifier) is a full-size iPad and must be 264 ppi")
            }
        }
    }

    @Test("No iPhone identifier is mistakenly in the iPad density band")
    func iPhonesAreNotIPadDensity() {
        for (identifier, ppi) in ScreenGeometry.exactTable where identifier.hasPrefix("iPhone") {
            #expect(ppi >= 326, "\(identifier) at \(ppi) ppi looks like an iPad value")
        }
    }

    // MARK: Points per centimetre

    @Test("iPad at 264 ppi @2x is 51.97 points per centimetre")
    func iPadPointsPerCM() {
        let density = ScreenGeometry.Density(pixelsPerInch: 264, confidence: .exact)
        // 264 / 2 = 132 points per inch; 132 / 2.54 = 51.97 per cm
        #expect(abs(density.pointsPerCM(scale: 2) - 51.97) < 0.01)
    }

    @Test("iPad mini at 326 ppi @2x is 64.17 points per centimetre")
    func iPadMiniPointsPerCM() {
        let density = ScreenGeometry.Density(pixelsPerInch: 326, confidence: .exact)
        #expect(abs(density.pointsPerCM(scale: 2) - 64.17) < 0.01)
    }

    @Test("A 460 ppi @3x iPhone is 60.37 points per centimetre")
    func iPhonePointsPerCM() {
        let density = ScreenGeometry.Density(pixelsPerInch: 460, confidence: .exact)
        // 460 / 3 = 153.33 per inch; / 2.54 = 60.37 per cm
        #expect(abs(density.pointsPerCM(scale: 3) - 60.37) < 0.01)
    }

    @Test("Every table entry yields a plausible points-per-cm figure")
    func allEntriesProducePlausiblePointsPerCM() {
        for (identifier, ppi) in ScreenGeometry.exactTable {
            let scale: Double = identifier.hasPrefix("iPad") ? 2 : (ppi > 400 ? 3 : 2)
            let pointsPerCM = ScreenGeometry.Density(pixelsPerInch: ppi, confidence: .exact)
                .pointsPerCM(scale: scale)
            #expect(ScreenGeometry.isPlausible(pointsPerCM),
                    "\(identifier) -> \(pointsPerCM) pt/cm is outside the sanity range")
        }
    }

    // MARK: Card verification

    @Test("Card width converts to points per centimetre")
    func cardCheck() {
        // A card measured as 445 points wide on an 11" iPad:
        // 445 / 8.56 cm = 51.99 pt/cm — matches the 264 ppi table value.
        let pointsPerCM = ScreenGeometry.pointsPerCM(fromCardWidthInPoints: 445)
        #expect(abs(pointsPerCM - 51.99) < 0.05)
    }

    @Test("The reference card is the ISO ID-1 standard size")
    func cardDimensions() {
        #expect(ScreenGeometry.referenceCardWidthCM == 8.56)
        #expect(ScreenGeometry.referenceCardHeightCM == 5.398)
    }

    @Test("Implausible card drags are rejected rather than stored")
    func rejectsBadCardDrags() {
        // A tiny drag: 100 points -> 11.7 pt/cm. Nonsense.
        #expect(ScreenGeometry.isPlausible(ScreenGeometry.pointsPerCM(fromCardWidthInPoints: 100)) == false)
        // A full-width drag on an iPad: 1000 points -> 116.8 pt/cm. Nonsense.
        #expect(ScreenGeometry.isPlausible(ScreenGeometry.pointsPerCM(fromCardWidthInPoints: 1000)) == false)
        // A correct drag.
        #expect(ScreenGeometry.isPlausible(ScreenGeometry.pointsPerCM(fromCardWidthInPoints: 445)))
        #expect(ScreenGeometry.pointsPerCM(fromCardWidthInPoints: 0) == 0)
    }

    // MARK: Viewing distance

    @Test("Viewing distance bounds are sane")
    func viewingDistanceBounds() {
        #expect(ScreenGeometry.plausibleViewingDistanceCM.contains(50))
        #expect(ScreenGeometry.plausibleViewingDistanceCM.contains(35))
        // The reference app suggests 1 foot (30 cm) at the near end — allowed,
        // but 20 cm is too close for sustained near work.
        #expect(ScreenGeometry.plausibleViewingDistanceCM.contains(20) == false)
        #expect(ScreenGeometry.plausibleViewingDistanceCM.contains(150) == false)
    }

    // MARK: End-to-end

    @Test("A known iPad produces a correct one-degree stimulus size")
    func endToEndAngularSize() {
        let ppi = try! #require(ScreenGeometry.exactTable["iPad13,4"])   // iPad Pro 11" M1
        let pointsPerCM = ScreenGeometry.Density(pixelsPerInch: ppi, confidence: .exact)
            .pointsPerCM(scale: 2)

        let calibration = CalibrationProfile(
            screenPointsPerCM: pointsPerCM,
            viewingDistanceCM: 50
        )

        // 2 · 50 · tan(0.5°) = 0.8727 cm; × 51.97 pt/cm = 45.36 points.
        #expect(abs(calibration.points(forDegrees: 1.0) - 45.36) < 0.1)

        // And that iPad can render gratings up to ~22.7 c/deg at 50 cm.
        #expect(abs(calibration.maxRenderableCyclesPerDegree - 22.68) < 0.15)
    }

    @Test("Sitting closer lowers the finest renderable grating")
    func closerIsWorseForFineGratings() {
        let ppcm = 51.97
        let near = CalibrationProfile(screenPointsPerCM: ppcm, viewingDistanceCM: 30)
        let far = CalibrationProfile(screenPointsPerCM: ppcm, viewingDistanceCM: 70)
        #expect(near.maxRenderableCyclesPerDegree < far.maxRenderableCyclesPerDegree)
    }
}
