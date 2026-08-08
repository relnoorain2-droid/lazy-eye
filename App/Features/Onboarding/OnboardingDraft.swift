//
//  OnboardingDraft.swift
//
//  Everything the user enters during onboarding, held in memory until the very
//  last step, then committed to SwiftData in ONE transaction.
//
//  WHY A DRAFT AND NOT INCREMENTAL WRITES
//  Writing a Profile at step 2 and its CalibrationProfile at step 5 means an
//  abandoned onboarding leaves a half-built profile in the store: named, but with
//  no eye assigned and no calibration. The next launch then has to decide whether
//  that is a returning user or a corpse. It never guesses right. A draft makes
//  abandonment free - the app is exactly as it was.
//
//  The validation here is also the single source of truth for which steps are
//  reachable, so the flow view never has to re-derive it.
//
//  docs/02-PRD.md section 4, docs/04-ARCHITECTURE.md section 3.
//

import Foundation

struct OnboardingDraft: Equatable, Sendable {

    // MARK: Who

    var name: String = ""
    var birthYear: Int?

    /// Set directly when the user skips the birth-year question.
    var explicitAgeGroup: AgeGroup?

    var amblyopicEye: Eye = .unknown
    var wearsCorrection: Bool = false

    // MARK: Consent

    /// Must be an explicit tap. Scrolling to the bottom is not consent, and
    /// guideline 1.4.1 review has rejected apps that treated it as such.
    var hasAcknowledgedDisclaimer: Bool = false

    // MARK: Sound

    var musicEnabled: Bool = false
    var soundEffectsEnabled: Bool = false
    var voiceGuidanceEnabled: Bool = false

    // MARK: Calibration

    var screenPointsPerCM: Double = 0
    var screenSizeUserVerified: Bool = false
    var viewingDistanceCM: Double = 50
    var deviceIdentifier: String = ""

    // MARK: - Derived

    /// Birth year wins when present; otherwise the explicit choice; otherwise
    /// the adult default, which has the most conservative session cap of the
    /// three and so is the safe fallback.
    var ageGroup: AgeGroup {
        if let birthYear { return AgeGroup.inferred(fromBirthYear: birthYear) }
        return explicitAgeGroup ?? .thirteenPlus
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name actually stored. An empty field is not an error - most people
    /// setting this up for themselves have no interest in typing their own name -
    /// so it falls back rather than blocking the step.
    var resolvedName: String {
        trimmedName.isEmpty ? "Me" : trimmedName
    }

    var isKidsMode: Bool { ageGroup.requiresParentGate }

    var preferences: PreferencesBlob {
        PreferencesBlob(hasAcknowledgedDisclaimer: hasAcknowledgedDisclaimer)
    }
}

// MARK: - Step validation

extension OnboardingDraft {

    /// Whether the user may leave each step. Deliberately permissive: the only
    /// hard gates are the medical disclaimer (legal) and a plausible screen
    /// calibration (every stimulus size depends on it).
    func canAdvance(from step: OnboardingStep) -> Bool {
        switch step {
        case .welcome:
            return true
        case .disclaimer:
            return hasAcknowledgedDisclaimer
        case .profile:
            // Eye may stay `.unknown`. Plenty of people genuinely do not know
            // which eye is weaker, and refusing to continue would strand them
            // at step 3 forever. The plan generator handles `.unknown` by
            // training both eyes and prompting them to ask their eye doctor.
            return true
        case .sound:
            return true
        case .calibration:
            return isCalibrationUsable
        case .ready:
            return true
        }
    }

    var isCalibrationUsable: Bool {
        ScreenGeometry.isPlausible(screenPointsPerCM)
            && ScreenGeometry.plausibleViewingDistanceCM.contains(viewingDistanceCM)
    }

    /// Reason the Continue button is disabled, for the inline hint. Nil when the
    /// step is satisfied.
    func blockingReason(for step: OnboardingStep) -> String? {
        guard !canAdvance(from: step) else { return nil }
        switch step {
        case .disclaimer:
            return "Please read and accept before continuing."
        case .calibration:
            return "Set your screen size and viewing distance to continue."
        default:
            return nil
        }
    }
}

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case disclaimer
    case profile
    case sound
    case calibration
    case ready

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .disclaimer: "Before you start"
        case .profile: "About you"
        case .sound: "Sound"
        case .calibration: "Calibration"
        case .ready: "You're set"
        }
    }

    /// Shown under the progress bar. Kept short - this is orientation, not copy.
    var subtitle: String {
        switch self {
        case .welcome: "What this app does"
        case .disclaimer: "What it is and isn't"
        case .profile: "So we can plan sessions"
        case .sound: "Off unless you want it"
        case .calibration: "So sizes are real sizes"
        case .ready: "First session ready"
        }
    }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// 0…1 for the progress bar. The welcome screen shows a sliver rather than
    /// zero so the bar reads as a track with a position on it.
    var progress: Double {
        Double(rawValue + 1) / Double(OnboardingStep.allCases.count)
    }

    var isLast: Bool { next == nil }
}
