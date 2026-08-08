//
//  ScreenGeometry.swift
//
//  Maps this device to a physical points-per-centimetre figure, so the app can
//  render a stimulus of a known visual angle.
//
//  WHY THIS FILE EXISTS
//  iOS exposes no API for the physical size of the display. Without it, "a
//  1-degree Gabor at 3 cycles per degree" is a sentence with no meaning — you
//  are drawing an arbitrary number of pixels and calling the result a threshold.
//  Every competitor in this category has this bug. Fixing it is most of why our
//  numbers are worth charting.
//
//  DESIGN PRINCIPLE — must survive devices that do not exist yet.
//  A hardcoded identifier table goes stale the moment Apple ships new hardware,
//  and a user on an unrecognised iPhone must never get a broken app. So the
//  lookup is layered:
//
//     1. Exact match in the table below              (best)
//     2. Family heuristic from the identifier + scale (very good — see note)
//     3. Conservative default + prompt the card check (always correct-able)
//
//  The user-verified credit-card check overrides all three and is offered to
//  everyone. That is the real answer to future hardware.
//
//  ACCURACY NOTE
//  Across current iPhones the @3x panels are 458-476 ppi — a spread of under 4%.
//  All full-size iPads are 264 ppi and all iPad minis are 326 ppi; that 23% gap
//  is the only one large enough to matter, and it is handled explicitly. A 2%
//  error in assumed screen size shifts a threshold by far less than the
//  between-session noise of the staircase itself, so heuristic fallbacks are
//  safe. A 23% error is not, which is why the mini is never guessed.
//
//  docs/04-ARCHITECTURE.md section 4, docs/DECISIONS.md section 6 rule 4.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ScreenGeometry {

    /// Physical pixels per inch, and how confident we are about it.
    struct Density: Equatable, Sendable {
        let pixelsPerInch: Double
        let confidence: Confidence

        enum Confidence: String, Sendable {
            /// Exact match in the device table.
            case exact
            /// Inferred from the device family. Within ~4% for iPhones, exact for iPads.
            case inferred
            /// Unknown device. Usable, but the user should run the card check.
            case fallback
            /// The user physically verified it. Always wins.
            case userVerified
        }

        /// Points per centimetre, given the display scale.
        func pointsPerCM(scale: Double) -> Double {
            (pixelsPerInch / scale) / 2.54
        }
    }

    // MARK: - Public API
    //
    // CONCURRENCY NOTE: everything that touches UIScreen or UIDevice is
    // @MainActor, because those are main-actor-isolated in Swift 6. The pure
    // maths below (the device table, points-per-cm conversion, the card check)
    // is deliberately NOT isolated, so it stays unit-testable without a main
    // actor hop — which is most of what the tests exercise.

    /// Best available density for the current device.
    @MainActor
    static func currentDensity() -> Density {
        let id = deviceIdentifier()
        if let ppi = exactTable[id] {
            return Density(pixelsPerInch: ppi, confidence: .exact)
        }
        if let ppi = inferred(from: id) {
            return Density(pixelsPerInch: ppi, confidence: .inferred)
        }
        return Density(pixelsPerInch: fallbackPPI(), confidence: .fallback)
    }

    /// Points per centimetre for the current device, ready to store in a
    /// `CalibrationProfile`.
    @MainActor
    static func currentPointsPerCM() -> Double {
        currentDensity().pointsPerCM(scale: displayScale())
    }

    /// True when we are guessing and should nudge the user to verify.
    @MainActor
    static var shouldPromptCardCheck: Bool {
        switch currentDensity().confidence {
        case .exact: false
        case .inferred, .fallback: true
        case .userVerified: false
        }
    }

    // MARK: - Credit-card verification
    //
    // ISO/IEC 7810 ID-1 — the size of every bank card, driving licence and
    // insurance card on Earth. Universally available, and accurate to a
    // fraction of a millimetre.

    /// Width of an ID-1 card in centimetres (85.60 mm).
    static let referenceCardWidthCM: Double = 8.56
    /// Height of an ID-1 card in centimetres (53.98 mm).
    static let referenceCardHeightCM: Double = 5.398

    /// Convert the user's on-screen card width to points per centimetre.
    /// The user drags a rectangle until it matches a real card held to the glass.
    static func pointsPerCM(fromCardWidthInPoints points: Double) -> Double {
        guard points > 0 else { return 0 }
        return points / referenceCardWidthCM
    }

    /// Sanity bounds for a user-entered value. Anything outside this is a
    /// mis-drag, not a real screen, and should be rejected rather than stored —
    /// a bad calibration silently corrupts every threshold that follows.
    static let plausiblePointsPerCM: ClosedRange<Double> = 35...80

    static func isPlausible(_ pointsPerCM: Double) -> Bool {
        plausiblePointsPerCM.contains(pointsPerCM)
    }

    // MARK: - Diagonal fallback
    //
    // THE CARD CHECK DOES NOT FIT ON EVERY DEVICE, and that is not a bug in the
    // UI - it is arithmetic. An ID-1 card is 8.56 x 5.398 cm. An iPhone SE
    // display is 4.98 x 8.85 cm. The card's SHORT edge is wider than the screen,
    // so at true size it cannot be shown in either orientation. Same for the
    // iPhone 13 mini and anything smaller.
    //
    // So the card check is offered only where it physically fits, and this is the
    // universal fallback: the user reads the screen diagonal off the spec sheet
    // (everyone can find "6.1-inch display") and we combine it with the point
    // resolution the OS reports, which is exact.
    //
    //     ppcm = sqrt(w² + h²) / (diagonal_inches × 2.54)

    /// Screen size in POINTS, long side first. Orientation-independent.
    @MainActor
    static func pointResolution() -> (long: Double, short: Double) {
        #if canImport(UIKit)
        let bounds = UIScreen.main.bounds.size
        let w = Double(bounds.width), h = Double(bounds.height)
        return (max(w, h), min(w, h))
        #else
        return (0, 0)
        #endif
    }

    /// Points per centimetre implied by a stated diagonal in inches.
    @MainActor
    static func pointsPerCM(fromDiagonalInches inches: Double) -> Double {
        guard inches > 0 else { return 0 }
        let (long, short) = pointResolution()
        let diagonalPoints = (long * long + short * short).squareRoot()
        return diagonalPoints / (inches * 2.54)
    }

    /// Diagonal in inches implied by a points-per-cm value. Used to seed the
    /// fallback picker from whatever we already detected, so the user is nudging
    /// a close number rather than starting from nothing.
    @MainActor
    static func diagonalInches(forPointsPerCM ppcm: Double) -> Double {
        guard ppcm > 0 else { return 0 }
        let (long, short) = pointResolution()
        let diagonalPoints = (long * long + short * short).squareRoot()
        return diagonalPoints / ppcm / 2.54
    }

    /// Every shipping iPhone and iPad diagonal, plus headroom either side.
    static let plausibleDiagonalInches: ClosedRange<Double> = 3.5...14.0

    /// Longest card edge, in points, that could be drawn at true size on a
    /// display of this density. Compared against the available space to decide
    /// whether to offer the card check at all.
    static func cardLongEdgePoints(atPointsPerCM ppcm: Double) -> Double {
        ppcm * referenceCardWidthCM
    }

    static func cardShortEdgePoints(atPointsPerCM ppcm: Double) -> Double {
        cardLongEdgePoints(atPointsPerCM: ppcm)
            * (referenceCardHeightCM / referenceCardWidthCM)
    }

    /// Breathing room so the outline is never flush to the bezel, where the user
    /// cannot see its edge against a real card.
    static let cardCheckMarginPoints: Double = 24

    /// THE SINGLE DEFINITION OF WHETHER THE CARD CHECK IS POSSIBLE.
    ///
    /// This used to be written out inline in the calibration view AND
    /// re-derived by hand in the test, and the two disagreed - the test asserted
    /// the card's long edge exceeded the screen's long axis, which is false on an
    /// iPhone SE (549 pt of card against 568 pt of screen). The card genuinely
    /// does not fit there, but because of the SHORT edge and the margin, not the
    /// long one. One function, used by both, so they cannot drift again.
    static func cardCheckFits(longAxisPoints: Double,
                              shortAxisPoints: Double,
                              atPointsPerCM ppcm: Double) -> Bool {
        guard ppcm > 0 else { return false }
        let long = cardLongEdgePoints(atPointsPerCM: ppcm) + cardCheckMarginPoints
        let short = cardShortEdgePoints(atPointsPerCM: ppcm) + cardCheckMarginPoints
        return long <= longAxisPoints && short <= shortAxisPoints
    }

    // MARK: - Device identifier

    /// e.g. "iPad13,4". On the simulator, the identifier of the simulated device.
    static func deviceIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        #endif
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier += String(UnicodeScalar(UInt8(value)))
        }
    }

    @MainActor
    static func displayScale() -> Double {
        #if canImport(UIKit)
        let scale = UIScreen.main.scale
        return scale > 0 ? Double(scale) : 2.0
        #else
        return 2.0
        #endif
    }

    // MARK: - Family inference
    //
    // Covers every device Apple has not shipped yet, which is the important case.

    @MainActor
    private static func inferred(from identifier: String) -> Double? {
        if identifier.hasPrefix("iPad") {
            // Every iPad mini is 326 ppi; every other iPad is 264 ppi. This has
            // held for every model since the Retina era. The mini must be
            // identified correctly — a 23% error would matter.
            return isIPadMini(identifier) ? 326 : 264
        }

        if identifier.hasPrefix("iPhone") {
            // @2x iPhones are the 326 ppi "Liquid Retina" LCD and SE bodies.
            // @3x iPhones are OLED at 458-476 ppi; 460 is within 4% of all of them.
            return displayScale() >= 2.9 ? 460 : 326
        }

        return nil
    }

    /// iPad mini generations, by identifier family.
    /// mini 5 = iPad11,1-2 · mini 6 = iPad14,1-2 · mini 7 (A17 Pro) = iPad16,1-2
    @MainActor
    private static func isIPadMini(_ identifier: String) -> Bool {
        if knownMiniIdentifiers.contains(identifier) { return true }
        // Future minis: fall back to physical pixel count. Every mini to date is
        // 1488×2266 or 1536×2048; no full-size iPad shares those.
        #if canImport(UIKit)
        let native = UIScreen.main.nativeBounds.size
        let shortSide = min(native.width, native.height)
        let longSide = max(native.width, native.height)
        let isMiniSized = (shortSide <= 1536 && longSide <= 2266)
        return isMiniSized
        #else
        return false
        #endif
    }

    private static let knownMiniIdentifiers: Set<String> = [
        "iPad11,1", "iPad11,2",     // mini 5
        "iPad14,1", "iPad14,2",     // mini 6
        "iPad16,1", "iPad16,2"      // mini 7
    ]

    /// Last resort. 264 ppi (iPad) or 460 ppi (iPhone) is closer to right than
    /// anything else we could pick, and the card check corrects it.
    @MainActor
    private static func fallbackPPI() -> Double {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? 264 : 460
        #else
        return 264
        #endif
    }

    // MARK: - Exact table
    //
    // Covers every device that can run iOS/iPadOS 17. Values are physical pixels
    // per inch of the panel — NOT points. Points per cm is derived by dividing
    // by the display scale.
    //
    // Adding a new device is a one-line change; omitting one is harmless because
    // the family heuristic above handles it.

    static let exactTable: [String: Double] = {
        var table: [String: Double] = [:]

        // ---- iPhone, @2x LCD / 326 ppi ----------------------------------
        for id in ["iPhone11,8",              // XR
                   "iPhone12,1",              // 11
                   "iPhone12,8",              // SE 2nd gen
                   "iPhone14,6"] {            // SE 3rd gen
            table[id] = 326
        }

        // ---- iPhone, @3x OLED / 458 ppi ---------------------------------
        for id in ["iPhone11,2",              // XS
                   "iPhone11,4", "iPhone11,6",// XS Max
                   "iPhone12,3",              // 11 Pro
                   "iPhone12,5",              // 11 Pro Max
                   "iPhone13,4",              // 12 Pro Max
                   "iPhone14,3",              // 13 Pro Max
                   "iPhone14,8"] {            // 14 Plus
            table[id] = 458
        }

        // ---- iPhone, @3x OLED / 460 ppi ---------------------------------
        for id in ["iPhone13,2", "iPhone13,3",            // 12, 12 Pro
                   "iPhone14,5", "iPhone14,2",            // 13, 13 Pro
                   "iPhone14,7",                          // 14
                   "iPhone15,2", "iPhone15,3",            // 14 Pro, 14 Pro Max
                   "iPhone15,4", "iPhone15,5",            // 15, 15 Plus
                   "iPhone16,1", "iPhone16,2",            // 15 Pro, 15 Pro Max
                   "iPhone17,1", "iPhone17,2",            // 16 Pro, 16 Pro Max
                   "iPhone17,3", "iPhone17,4",            // 16, 16 Plus
                   "iPhone17,5"] {                        // 16e
            table[id] = 460
        }

        // ---- iPhone mini, @3x / 476 ppi ---------------------------------
        for id in ["iPhone13,1",              // 12 mini
                   "iPhone14,4"] {            // 13 mini
            table[id] = 476
        }

        // ---- iPad mini, @2x / 326 ppi -----------------------------------
        for id in knownMiniIdentifiers { table[id] = 326 }

        // ---- All other iPads, @2x / 264 ppi -----------------------------
        for id in [
            // iPad (standard)
            "iPad6,11", "iPad6,12",                       // 6th gen — iOS 17 only
            "iPad7,5", "iPad7,6",                         // 7th gen
            "iPad11,6", "iPad11,7",                       // 8th gen
            "iPad12,1", "iPad12,2",                       // 9th gen
            "iPad13,18", "iPad13,19",                     // 10th gen
            "iPad15,7", "iPad15,8",                       // 11th gen (A16)
            // iPad Air
            "iPad11,3", "iPad11,4",                       // Air 3
            "iPad13,1", "iPad13,2",                       // Air 4
            "iPad13,16", "iPad13,17",                     // Air 5 (M1)
            "iPad14,8", "iPad14,9",                       // Air 11" M2
            "iPad14,10", "iPad14,11",                     // Air 13" M2
            "iPad15,3", "iPad15,4",                       // Air 11" M3
            "iPad15,5", "iPad15,6",                       // Air 13" M3
            // iPad Pro
            "iPad7,1", "iPad7,2",                         // Pro 12.9" 2nd — iOS 17 only
            "iPad7,3", "iPad7,4",                         // Pro 10.5" — iOS 17 only
            "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4",   // Pro 11" 1st
            "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8",   // Pro 12.9" 3rd
            "iPad8,9", "iPad8,10",                        // Pro 11" 2nd
            "iPad8,11", "iPad8,12",                       // Pro 12.9" 4th
            "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7",     // Pro 11" 3rd (M1)
            "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11",   // Pro 12.9" 5th (M1)
            "iPad14,3", "iPad14,4",                       // Pro 11" 4th (M2)
            "iPad14,5", "iPad14,6",                       // Pro 12.9" 6th (M2)
            "iPad16,3", "iPad16,4",                       // Pro 11" M4
            "iPad16,5", "iPad16,6"                        // Pro 13" M4
        ] {
            table[id] = 264
        }

        return table
    }()
}

// MARK: - Recommended viewing distance
//
// Not a calibration value, but it belongs with the geometry. The reference app
// says "1 or 2 feet from the screen, depending on screen size", which is vague
// and, at 1 foot, uncomfortably close for sustained near work.

extension ScreenGeometry {

    /// A sensible starting distance for this device. The user can adjust it, and
    /// whatever they choose is what the maths uses — this is only the default.
    @MainActor
    static func suggestedViewingDistanceCM() -> Double {
        #if canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return 50      // held or propped, comfortable near-work distance
        case .phone: return 35
        default: return 50
        }
        #else
        return 50
        #endif
    }

    /// Below this, sustained near work is uncomfortable and accommodation demand
    /// is high; above it, small stimuli fall below the display's resolution.
    static let plausibleViewingDistanceCM: ClosedRange<Double> = 25...100
}
