//
//  Exercise.swift
//
//  The contract every one of the 32 exercises implements.
//
//  DESIGN DECISION: DESCRIPTOR AND RUNTIME ARE SEPARATE TYPES.
//  `ExerciseDescriptor` is a plain value - id, title, evidence tier, staircase
//  configuration, safety envelope. `Exercise` is the live thing that generates
//  trials and draws. Splitting them means the registry, the plan generator, the
//  Train library, the paywall gate and - crucially - `FlickerGuard` can all
//  reason about every exercise WITHOUT instantiating a renderer. The safety
//  tests iterate 32 descriptors in microseconds instead of standing up 32 views.
//
//  docs/04-ARCHITECTURE.md sections 4 and 6, docs/03-EXERCISE-CATALOG.md.
//

import Foundation

// MARK: - Descriptor

struct ExerciseDescriptor: Identifiable, Hashable, Sendable {

    /// Stable identifier, persisted in every TrialRecord. Never change one of
    /// these without a data migration - history is keyed on it.
    let id: String

    let title: String
    let track: Track
    let evidenceTier: EvidenceTier

    /// One sentence, user-facing, describing what the person actually does.
    let summary: String

    /// What the exercise trains, in plain words. Shown on the card.
    let targets: String

    /// Typical length when the plan schedules it.
    let defaultDurationSeconds: Int

    /// The dimension the staircase moves along, and its bounds.
    let staircase: StaircaseConfiguration

    /// Everything FlickerGuard checks. Declared, not inferred: an exercise must
    /// state its own worst case, and the guard verifies the declaration is
    /// within limits and that the renderer honours it.
    let safety: SafetyEnvelope

    /// False for exercises that are unusable without red-cyan glasses.
    var requiresAnaglyph: Bool { track == .dichoptic }

    /// Free tier gets exactly one full exercise before the paywall.
    /// docs/07-MONETIZATION-PAYWALL.md section 3.
    let isFreeTier: Bool

    /// Minimum age group this is appropriate for. Reading tasks are pointless
    /// for a four-year-old.
    let minimumAgeGroup: AgeGroup

    init(
        id: String,
        title: String,
        track: Track,
        evidenceTier: EvidenceTier,
        summary: String,
        targets: String,
        defaultDurationSeconds: Int = 300,
        staircase: StaircaseConfiguration,
        safety: SafetyEnvelope,
        isFreeTier: Bool = false,
        minimumAgeGroup: AgeGroup = .underFive
    ) {
        self.id = id
        self.title = title
        self.track = track
        self.evidenceTier = evidenceTier
        self.summary = summary
        self.targets = targets
        self.defaultDurationSeconds = defaultDurationSeconds
        self.staircase = staircase
        self.safety = safety
        self.isFreeTier = isFreeTier
        self.minimumAgeGroup = minimumAgeGroup
    }
}

// MARK: - Staircase configuration

struct StaircaseConfiguration: Hashable, Sendable {

    /// Human-readable name of the dimension, e.g. "orientation difference".
    let dimensionName: String
    /// Unit suffix for display, e.g. "°", "%", "arcmin". Empty for ratios.
    let unit: String

    let startValue: Double
    let hardestValue: Double
    let easiestValue: Double
    let polarity: Staircase.Polarity

    let initialStepSize: Double
    let minimumStepSize: Double

    /// Number of response alternatives. Sets the guess rate, which the simulated
    /// observer and the "is this above chance" check both need.
    let alternatives: Int

    init(
        dimensionName: String,
        unit: String = "",
        startValue: Double,
        hardestValue: Double,
        easiestValue: Double,
        polarity: Staircase.Polarity,
        alternatives: Int,
        initialStepSize: Double = 0.5,
        minimumStepSize: Double = 0.03
    ) {
        self.dimensionName = dimensionName
        self.unit = unit
        self.startValue = startValue
        self.hardestValue = hardestValue
        self.easiestValue = easiestValue
        self.polarity = polarity
        self.alternatives = alternatives
        self.initialStepSize = initialStepSize
        self.minimumStepSize = minimumStepSize
    }

    /// A fresh staircase, optionally started easier for younger users. Starting
    /// a six-year-old at the adult default is the fastest way to lose them in
    /// the first ninety seconds.
    func makeStaircase(ageGroup: AgeGroup = .thirteenPlus) -> Staircase {
        Staircase(
            start: startValue(for: ageGroup),
            hardestValue: hardestValue,
            easiestValue: easiestValue,
            polarity: polarity,
            initialStepSize: initialStepSize,
            minimumStepSize: minimumStepSize
        )
    }

    func startValue(for ageGroup: AgeGroup) -> Double {
        // One easy step for 5-12, two for under-5, in the direction that is
        // easier for this polarity.
        let easySteps: Int = switch ageGroup {
        case .underFive: 2
        case .fiveToTwelve: 1
        case .thirteenPlus: 0
        }
        guard easySteps > 0 else { return startValue }

        var value = startValue
        for _ in 0..<easySteps {
            value = polarity == .lowerIsHarder
                ? value * (1 + initialStepSize)
                : value / (1 + initialStepSize)
        }
        let low = min(hardestValue, easiestValue)
        let high = max(hardestValue, easiestValue)
        return min(max(value, low), high)
    }

    /// Chance performance for this task.
    var guessRate: Double { 1.0 / Double(max(1, alternatives)) }

    func format(_ value: Double) -> String {
        let magnitude = abs(value)
        let decimals = magnitude >= 10 ? 0 : (magnitude >= 1 ? 1 : 3)
        return String(format: "%.\(decimals)f%@", value, unit)
    }
}

// MARK: - Safety envelope
//
// docs/01-RESEARCH-BRIEF.md section 7. These are not style settings.

struct SafetyEnvelope: Hashable, Sendable {

    /// Highest rate at which anything in this exercise changes state, in Hz.
    /// Photosensitive seizures are provoked by high-contrast oscillation in the
    /// 3-60 Hz band, with peak risk near 15-20 Hz. We stay entirely below the
    /// band rather than near its edge.
    let maxTemporalRateHz: Double

    /// True if the exercise ever inverts luminance across the whole screen.
    /// Must be false for everything we ship - a full-field inversion is the
    /// single most provocative pattern there is, and no exercise here needs one.
    let invertsFullFieldLuminance: Bool

    /// Highest Michelson contrast presented. 1.0 is a full black-white edge.
    let maxContrast: Double

    /// Fraction of the screen the highest-contrast element can occupy. Large
    /// area multiplies risk at any given rate.
    let maxHighContrastAreaFraction: Double

    static let still = SafetyEnvelope(
        maxTemporalRateHz: 0,
        invertsFullFieldLuminance: false,
        maxContrast: 1.0,
        maxHighContrastAreaFraction: 0.25
    )

    /// Standard envelope for exercises with gentle motion.
    static let gentleMotion = SafetyEnvelope(
        maxTemporalRateHz: 2.0,
        invertsFullFieldLuminance: false,
        maxContrast: 1.0,
        maxHighContrastAreaFraction: 0.30
    )
}

// MARK: - Runtime

/// One presentation: what to draw, and what counts as the right answer.
struct Trial: Identifiable, Sendable {
    let id: UUID
    /// Difficulty this trial was presented at - the staircase's current value.
    let difficulty: Double
    /// Index of the correct alternative, 0-based.
    let correctAnswer: Int
    /// Exercise-specific payload, e.g. the Gabor's actual orientations.
    let payload: TrialPayload

    init(id: UUID = UUID(), difficulty: Double, correctAnswer: Int, payload: TrialPayload) {
        self.id = id
        self.difficulty = difficulty
        self.correctAnswer = correctAnswer
        self.payload = payload
    }
}

/// Type-erased per-trial parameters. Concrete exercises define their own struct
/// and stash it here; only the exercise's own renderer reads it back.
struct TrialPayload: Sendable {
    private let storage: [String: Double]

    init(_ storage: [String: Double] = [:]) { self.storage = storage }

    subscript(key: String) -> Double? { storage[key] }

    func value(_ key: String, default fallback: Double = 0) -> Double {
        storage[key] ?? fallback
    }

    var encoded: Data? { try? JSONEncoder().encode(storage) }
}

/// The live exercise. Generates trials; the view renders them.
///
/// Deliberately NOT a View-producing protocol: keeping trial generation free of
/// SwiftUI means it is testable without a host application, which is the whole
/// reason the staircase tests can run in milliseconds.
protocol Exercise: Sendable {
    static var descriptor: ExerciseDescriptor { get }

    /// Produces the next trial at the given difficulty. Must be pure with
    /// respect to `generator` - no hidden global randomness, or a session stops
    /// being reproducible from its seed.
    ///
    /// TAKES THE CONCRETE `SeededGenerator`, NOT `some RandomNumberGenerator`.
    /// A generic requirement here would make every call site go through
    /// existential opening on `any Exercise`, which is the sort of thing that
    /// compiles on one toolchain and not the next. It also buys nothing: the
    /// whole app runs on `SeededGenerator` precisely so that any session can be
    /// replayed exactly from its seed when someone reports a bad trial.
    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial
}

extension Exercise {
    var descriptor: ExerciseDescriptor { Self.descriptor }
}
