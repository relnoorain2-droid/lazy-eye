//
//  FlickerGuard.swift
//
//  Photosensitive-epilepsy protection. This is the highest-stakes code in the
//  app: everything else can be wrong and cost a refund; this being wrong can
//  cost someone a seizure.
//
//  THE RISK, STATED PRECISELY
//  Photosensitive seizures are provoked by high-contrast luminance oscillation.
//  Risk begins around 3 Hz, peaks near 15-20 Hz, and extends to about 60 Hz.
//  It rises with contrast, with the proportion of the visual field involved,
//  and is highest for full-field inversions and for red-saturated flashes -
//  which matters here, because this app renders red/cyan anaglyph by design.
//
//  THE POLICY
//  Stay entirely below the provocative band rather than near its edge. No
//  exercise may exceed 3.0 Hz, none may invert full-field luminance, and
//  high-contrast elements are bounded in area. Roughly 1 in 4,000 people is
//  photosensitive and most do not know it until it happens, so consent is not
//  available as a mitigation.
//
//  HOW IT IS ENFORCED - TWO LAYERS, BOTH REQUIRED
//  1. STATIC: every registered descriptor is audited by a unit test. An
//     exercise that declares an unsafe envelope fails CI. It cannot ship.
//  2. RUNTIME: `FlickerGuard.rate(_:)` clamps any animation rate a renderer
//     asks for. A renderer that ignores its own declared envelope - a refactor
//     accident, a bad interpolation - is caught in the running app, not in a
//     review of the code.
//
//  Layer 1 alone is not enough because it audits declarations, not behaviour.
//  Layer 2 alone is not enough because it silently fixes bugs instead of
//  failing the build. Together they are belt and braces on the one thing here
//  that can hurt someone.
//
//  docs/01-RESEARCH-BRIEF.md section 7, docs/04-ARCHITECTURE.md section 6.
//

import Foundation
import os

enum FlickerGuard {

    private static let log = Logger(subsystem: "com.amblyo.app", category: "safety")

    // MARK: Limits

    /// Absolute ceiling on any temporal rate anywhere in the app.
    static let maxTemporalRateHz: Double = SafetyLimits.maxTemporalRateHz   // 3.0

    /// A high-contrast element may not exceed this fraction of the screen.
    static let maxHighContrastAreaFraction: Double = 0.35

    /// Above this Michelson contrast an element counts as "high contrast" for
    /// the area rule.
    static let highContrastFloor: Double = 0.5

    // MARK: Runtime clamp

    /// Clamps a requested animation rate to the safe ceiling.
    ///
    /// Returns the clamped value rather than trapping, because a trap in a
    /// shipping build turns a rendering bug into a crash in a medical-adjacent
    /// app. In DEBUG it fires an assertion so the mistake is loud during
    /// development, and it always logs so the clamp is visible in the field.
    static func rate(_ requested: Double) -> Double {
        guard requested > maxTemporalRateHz else { return max(0, requested) }

        assertionFailure(
            "FlickerGuard: \(requested) Hz requested, ceiling is \(maxTemporalRateHz) Hz."
        )
        log.error("Clamped temporal rate \(requested, privacy: .public) Hz to \(maxTemporalRateHz, privacy: .public) Hz.")
        return maxTemporalRateHz
    }

    /// Clamps a period (seconds per cycle) - the form most animation code uses.
    static func period(_ requested: TimeInterval) -> TimeInterval {
        let minimumPeriod = 1.0 / maxTemporalRateHz
        return max(requested, minimumPeriod)
    }

    // MARK: Static audit

    enum Violation: Equatable, CustomStringConvertible {
        case rateTooHigh(exerciseID: String, declared: Double)
        case fullFieldInversion(exerciseID: String)
        case contrastOutOfRange(exerciseID: String, declared: Double)
        case highContrastAreaTooLarge(exerciseID: String, declared: Double)

        var description: String {
            switch self {
            case .rateTooHigh(let id, let declared):
                "\(id): declares \(declared) Hz; ceiling is \(FlickerGuard.maxTemporalRateHz) Hz"
            case .fullFieldInversion(let id):
                "\(id): declares full-field luminance inversion, which is never permitted"
            case .contrastOutOfRange(let id, let declared):
                "\(id): declares contrast \(declared); must be within 0...1"
            case .highContrastAreaTooLarge(let id, let declared):
                "\(id): high-contrast area \(declared) exceeds \(FlickerGuard.maxHighContrastAreaFraction)"
            }
        }
    }

    /// Audits one descriptor. Pure, so the test suite can run it over the whole
    /// registry without touching UIKit.
    static func audit(_ descriptor: ExerciseDescriptor) -> [Violation] {
        var violations: [Violation] = []
        let safety = descriptor.safety

        if safety.maxTemporalRateHz > maxTemporalRateHz {
            violations.append(.rateTooHigh(exerciseID: descriptor.id,
                                           declared: safety.maxTemporalRateHz))
        }
        if safety.invertsFullFieldLuminance {
            violations.append(.fullFieldInversion(exerciseID: descriptor.id))
        }
        if safety.maxContrast < 0 || safety.maxContrast > 1 {
            violations.append(.contrastOutOfRange(exerciseID: descriptor.id,
                                                  declared: safety.maxContrast))
        }
        if safety.maxContrast >= highContrastFloor,
           safety.maxHighContrastAreaFraction > maxHighContrastAreaFraction {
            violations.append(.highContrastAreaTooLarge(
                exerciseID: descriptor.id,
                declared: safety.maxHighContrastAreaFraction))
        }
        return violations
    }

    static func audit(_ descriptors: [ExerciseDescriptor]) -> [Violation] {
        descriptors.flatMap(audit)
    }
}
