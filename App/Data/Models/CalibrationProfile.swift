//
//  CalibrationProfile.swift
//
//  Per-profile, per-device calibration. This is what makes our stimulus sizes
//  real degrees of visual angle instead of arbitrary pixels — the single biggest
//  technical quality gap between this app and every competitor.
//
//  docs/04-ARCHITECTURE.md section 4, docs/01-RESEARCH-BRIEF.md section 4.
//

import Foundation
import SwiftData

@Model
final class CalibrationProfile {

    var profile: Profile?

    // MARK: Screen geometry

    /// Points per centimetre for this device's display. Derived from a device
    /// model lookup, then optionally corrected by the user's card-drag check.
    /// Phase 3 builds `ScreenGeometry` and the lookup table.
    var screenPointsPerCM: Double

    /// True when the user verified the size with the credit-card check rather
    /// than accepting the table value. Needed for unknown/future models.
    var screenSizeUserVerified: Bool

    /// How far the user sits from the screen, in centimetres.
    var viewingDistanceCM: Double

    // MARK: Anaglyph

    var anaglyphFilterRaw: String

    /// Crosstalk coefficients measured during calibration, 0…1. Subtracted from
    /// every rendered frame to cancel ghosting.
    var redLeakIntoCyan: Double
    var cyanLeakIntoRed: Double

    /// Set false when the red/cyan discrimination check fails. The dichoptic
    /// track is then hidden and the user is routed to the monocular track
    /// without any "unsupported" framing.
    var colorVisionOK: Bool

    /// Current position on the contrast-rebalance ramp for the fellow eye.
    /// 0.1 = heavily suppressed fellow eye (easy fusion), 1.0 = fully balanced.
    /// This ramp IS the therapeutic variable. docs/06-AI-ENGINE-SPEC.md section 2.
    var fellowEyeContrast: Double

    // MARK: Bookkeeping

    var calibratedAt: Date
    var anaglyphCalibratedAt: Date?
    /// Device model identifier the calibration was taken on. If the profile is
    /// later opened on a different device the screen part is invalid and must be
    /// redone; the anaglyph part carries over.
    var deviceIdentifier: String

    init(
        profile: Profile? = nil,
        screenPointsPerCM: Double = 0,
        screenSizeUserVerified: Bool = false,
        viewingDistanceCM: Double = 50,
        anaglyphFilter: AnaglyphFilter = .red,
        redLeakIntoCyan: Double = 0,
        cyanLeakIntoRed: Double = 0,
        colorVisionOK: Bool = true,
        fellowEyeContrast: Double = 0.2,
        calibratedAt: Date = .now,
        anaglyphCalibratedAt: Date? = nil,
        deviceIdentifier: String = ""
    ) {
        self.profile = profile
        self.screenPointsPerCM = screenPointsPerCM
        self.screenSizeUserVerified = screenSizeUserVerified
        self.viewingDistanceCM = viewingDistanceCM
        self.anaglyphFilterRaw = anaglyphFilter.rawValue
        self.redLeakIntoCyan = redLeakIntoCyan
        self.cyanLeakIntoRed = cyanLeakIntoRed
        self.colorVisionOK = colorVisionOK
        self.fellowEyeContrast = fellowEyeContrast
        self.calibratedAt = calibratedAt
        self.anaglyphCalibratedAt = anaglyphCalibratedAt
        self.deviceIdentifier = deviceIdentifier
    }
}

// MARK: - Derived values

extension CalibrationProfile {

    var anaglyphFilter: AnaglyphFilter {
        get { AnaglyphFilter(rawValue: anaglyphFilterRaw) ?? .red }
        set { anaglyphFilterRaw = newValue.rawValue }
    }

    var isComplete: Bool { screenPointsPerCM > 0 && viewingDistanceCM > 0 }

    var isAnaglyphCalibrated: Bool { anaglyphCalibratedAt != nil }

    /// Ghosting above this level makes dichoptic stimuli unreliable — prompt a
    /// recalibration rather than silently producing bad data.
    var crosstalkIsAcceptable: Bool {
        max(redLeakIntoCyan, cyanLeakIntoRed) < 0.25
    }

    // MARK: Angular geometry
    //
    // The whole point of this model. See docs/04-ARCHITECTURE.md section 4.

    /// Convert a desired visual angle to points on this screen at this distance.
    ///
    ///     size = 2 · d · tan(θ/2)
    ///
    func points(forDegrees degrees: Double) -> Double {
        guard isComplete, degrees > 0 else { return 0 }
        let halfAngleRadians = (degrees / 2) * .pi / 180
        let sizeCM = 2 * viewingDistanceCM * tan(halfAngleRadians)
        return sizeCM * screenPointsPerCM
    }

    /// A documented stand-in for a profile that has not been calibrated yet.
    ///
    /// WHY THIS EXISTS, AND WHY `points(forDegrees:)` STILL RETURNS ZERO.
    ///
    /// Returning zero for an uncalibrated profile was a deliberate choice and a
    /// correct one: a measurement app must never quietly hand back a size it
    /// cannot justify. `CalibrationGeometryTests.incompleteIsSafe` pins it.
    ///
    /// The half that was missing is that NOTHING HANDLED THE ZERO. `GameField`
    /// clamped it with `max(pointsPerDegree, 1)`, so an uncalibrated user got a
    /// nine-by-twelve POINT play area — the whole game collapsed into a smudge
    /// smaller than a fingernail. Rhythm Tap, Maze Runner and Star Tracer all
    /// rendered as an empty grey rectangle on device, and Star Tracer's "0 of 4
    /// joined" was the only clue that anything had been drawn at all.
    ///
    /// So the zero stays where exactness matters, and callers that need to DRAW
    /// something ask for this instead. It is a typical modern iPhone held at
    /// 30 cm: 460 ppi at scale 3 is 60.4 points per centimetre.
    ///
    /// Anything drawn with it is approximate, the ready screen already says so
    /// in a caution banner, and the Progress screen's own rules stop an
    /// approximate session from ever becoming a claimed trend.
    static var approximate: CalibrationProfile {
        CalibrationProfile(screenPointsPerCM: 60.4, viewingDistanceCM: 30)
    }

    /// This profile if it is usable, otherwise the documented stand-in.
    ///
    /// Call this at the point of DRAWING, never at the point of measuring.
    var forDrawing: CalibrationProfile { isComplete ? self : .approximate }

    /// Inverse: what angle does this many points subtend?
    func degrees(forPoints points: Double) -> Double {
        guard isComplete, points > 0 else { return 0 }
        let sizeCM = points / screenPointsPerCM
        let halfAngleRadians = atan(sizeCM / (2 * viewingDistanceCM))
        return 2 * halfAngleRadians * 180 / .pi
    }

    /// Points per cycle for a grating of the given spatial frequency.
    func pointsPerCycle(cyclesPerDegree: Double) -> Double {
        guard cyclesPerDegree > 0 else { return 0 }
        return points(forDegrees: 1.0 / cyclesPerDegree)
    }

    /// The finest grating this screen can show at this distance, in cycles per
    /// degree, assuming 2 points per cycle (Nyquist). Exercises must clamp their
    /// spatial frequency to this or they are measuring the display, not the user.
    var maxRenderableCyclesPerDegree: Double {
        guard isComplete else { return 0 }
        let pointsPerDegree = points(forDegrees: 1.0)
        return pointsPerDegree / 2.0
    }
}
