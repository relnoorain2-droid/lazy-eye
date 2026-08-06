//
//  Enums.swift
//
//  Shared value types for the data layer. All raw values are Strings and are
//  PERSISTED — never rename a case's raw value without a migration.
//
//  docs/04-ARCHITECTURE.md section 3.
//

import Foundation

// MARK: - Eye

enum Eye: String, Codable, CaseIterable, Sendable, Hashable {
    case left, right, unknown

    var displayName: String {
        switch self {
        case .left: "Left eye"
        case .right: "Right eye"
        case .unknown: "Not set"
        }
    }

    /// The other eye. `unknown` has no fellow.
    var fellow: Eye {
        switch self {
        case .left: .right
        case .right: .left
        case .unknown: .unknown
        }
    }
}

// MARK: - Age group

/// Drives default session length, pack ordering and UI skin.
/// docs/03-EXERCISE-CATALOG.md, final section.
enum AgeGroup: String, Codable, CaseIterable, Sendable {
    case underFive = "under5"
    case fiveToTwelve = "5to12"
    case thirteenPlus = "13plus"

    var displayName: String {
        switch self {
        case .underFive: "Under 5"
        case .fiveToTwelve: "5 to 12"
        case .thirteenPlus: "13 and over"
        }
    }

    /// Default planned session length.
    var defaultSessionSeconds: Int {
        switch self {
        case .underFive: 10 * 60
        case .fiveToTwelve: 20 * 60
        case .thirteenPlus: 25 * 60
        }
    }

    /// Hard daily ceiling. Safety, not preference. docs/04-ARCHITECTURE.md section 6.
    var dailyCapSeconds: Int {
        switch self {
        case .underFive, .fiveToTwelve: 20 * 60
        case .thirteenPlus: 30 * 60
        }
    }

    /// Under-13 profiles get the parent gate and the kids skin by default.
    var requiresParentGate: Bool { self != .thirteenPlus }

    /// Pack order on the Train screen.
    var packOrder: [Track] {
        switch self {
        case .underFive, .fiveToTwelve: [.game, .dichoptic, .monocular]
        case .thirteenPlus: [.dichoptic, .monocular, .game]
        }
    }

    static func inferred(fromBirthYear year: Int, now: Date = .now) -> AgeGroup {
        let currentYear = Calendar.current.component(.year, from: now)
        let age = currentYear - year
        return switch age {
        case ..<5: .underFive
        case 5...12: .fiveToTwelve
        default: .thirteenPlus
        }
    }
}

// MARK: - Track

enum Track: String, Codable, CaseIterable, Sendable {
    case monocular, dichoptic, game, assessment

    var displayName: String {
        switch self {
        case .monocular: "Monocular"
        case .dichoptic: "Binocular"      // user-facing word; "dichoptic" is jargon
        case .game: "Games"
        case .assessment: "Check-in"
        }
    }

    var systemImage: String {
        switch self {
        case .monocular: "eye"
        case .dichoptic: "eyeglasses"
        case .game: "gamecontroller"
        case .assessment: "chart.line.uptrend.xyaxis"
        }
    }

    var requiresAnaglyph: Bool { self == .dichoptic }
}

// MARK: - Evidence tier

/// docs/01-RESEARCH-BRIEF.md section 2. Shown as a badge on every exercise.
/// There is deliberately no `.d` case — Tier D content does not ship.
enum EvidenceTier: String, Codable, CaseIterable, Sendable, Comparable {
    case a = "A"
    case b = "B"
    case c = "C"

    var headline: String {
        switch self {
        case .a: "Randomised trial evidence"
        case .b: "Perceptual learning research"
        case .c: "Standard practice"
        }
    }

    /// Plain-English body for the badge sheet. The boundary sentence at the end
    /// of tiers A and B is required — docs/08-COMPLIANCE-LEGAL.md section 3A.
    var explanation: String {
        switch self {
        case .a:
            """
            This type of exercise has been studied in randomised controlled \
            trials in people with amblyopia. Those trials tested purpose-built \
            devices, not this app. Amblyo was not studied.
            """
        case .b:
            """
            This type of exercise comes from perceptual learning research, \
            mostly in adults. Those studies tested laboratory tasks, not this \
            app. Amblyo was not studied.
            """
        case .c:
            """
            This is a standard exercise used in optometric practice. The \
            published evidence for it in amblyopia specifically is limited.
            """
        }
    }

    /// Weight used by the plan generator. docs/06-AI-ENGINE-SPEC.md section 3.
    var planWeight: Double {
        switch self {
        case .a: 1.4
        case .b: 1.0
        case .c: 0.6
        }
    }

    static func < (lhs: EvidenceTier, rhs: EvidenceTier) -> Bool {
        let order: [EvidenceTier] = [.c, .b, .a]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - Session end reason

enum EndReason: String, Codable, CaseIterable, Sendable {
    /// Ran to plan.
    case completed
    /// User tapped Finish.
    case userStopped
    /// User tapped "My eyes feel tired". docs/14-REVIEW-COMPLAINTS-MATRIX.md R4.
    case fatigue
    /// Daily cap reached.
    case cap
    /// App backgrounded, call, window lost key focus.
    case interrupted

    /// Whether trials from this session are statistically usable.
    /// Interrupted sessions produce unreliable timing and are excluded from trends.
    var producesValidData: Bool { self != .interrupted }
}

// MARK: - Anaglyph

enum AnaglyphFilter: String, Codable, CaseIterable, Sendable {
    /// The amblyopic eye is behind the red filter.
    case red
    /// The amblyopic eye is behind the cyan filter.
    case cyan

    var displayName: String {
        switch self {
        case .red: "Red lens"
        case .cyan: "Cyan lens"
        }
    }
}

// MARK: - Assessment sub-test

enum AssessmentTest: String, Codable, CaseIterable, Sendable {
    case acuity, contrast, balance, stereo

    var displayName: String {
        switch self {
        case .acuity: "Detail"
        case .contrast: "Contrast"
        case .balance: "Balance"
        case .stereo: "Depth"
        }
    }

    /// Every score surface must carry this. docs/08-COMPLIANCE-LEGAL.md section 2.
    static let scoreQualifier = "Training score — not a clinical measurement"

    /// Lower is better for threshold measures; higher is better for balance.
    var lowerIsBetter: Bool { self != .balance }

    /// Free tier gets one sub-test. docs/07-MONETIZATION-PAYWALL.md section 3.
    var isFreeTier: Bool { self == .balance }
}

// MARK: - Preferences blob
//
// Per-profile settings that don't deserve their own columns. Stored as a Codable
// struct so adding a field never needs a SwiftData migration — new fields decode
// to their default via the memberwise init below.

struct PreferencesBlob: Codable, Sendable, Equatable {
    var preferredSessionSeconds: Int?
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var hasAcknowledgedDisclaimer: Bool
    var hasSeenOcclusionWarning: Bool
    var lastOcclusionWarningWeek: Int?
    var anaglyphPreviewWithoutGlasses: Bool

    init(
        preferredSessionSeconds: Int? = nil,
        reminderEnabled: Bool = false,
        reminderHour: Int = 18,
        reminderMinute: Int = 30,
        hasAcknowledgedDisclaimer: Bool = false,
        hasSeenOcclusionWarning: Bool = false,
        lastOcclusionWarningWeek: Int? = nil,
        anaglyphPreviewWithoutGlasses: Bool = false
    ) {
        self.preferredSessionSeconds = preferredSessionSeconds
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.hasAcknowledgedDisclaimer = hasAcknowledgedDisclaimer
        self.hasSeenOcclusionWarning = hasSeenOcclusionWarning
        self.lastOcclusionWarningWeek = lastOcclusionWarningWeek
        self.anaglyphPreviewWithoutGlasses = anaglyphPreviewWithoutGlasses
    }

    // Tolerant decoding: any field missing from an older store takes its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preferredSessionSeconds = try c.decodeIfPresent(Int.self, forKey: .preferredSessionSeconds)
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 18
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 30
        hasAcknowledgedDisclaimer = try c.decodeIfPresent(Bool.self, forKey: .hasAcknowledgedDisclaimer) ?? false
        hasSeenOcclusionWarning = try c.decodeIfPresent(Bool.self, forKey: .hasSeenOcclusionWarning) ?? false
        lastOcclusionWarningWeek = try c.decodeIfPresent(Int.self, forKey: .lastOcclusionWarningWeek)
        anaglyphPreviewWithoutGlasses = try c.decodeIfPresent(Bool.self, forKey: .anaglyphPreviewWithoutGlasses) ?? false
    }
}
