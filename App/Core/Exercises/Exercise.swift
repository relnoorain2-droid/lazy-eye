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

    /// The hardest value the exercise would LIKE to reach. The value actually
    /// used is `resolvedHardestValue(for:)`, which may be easier - see below.
    let hardestValue: Double

    let easiestValue: Double
    let polarity: Staircase.Polarity

    let initialStepSize: Double
    let minimumStepSize: Double

    /// Number of response alternatives. Sets the guess rate, which the simulated
    /// observer and the "is this above chance" check both need.
    let alternatives: Int

    /// How this dimension is bounded by what the display can physically show.
    let renderLimit: RenderLimit?

    init(
        dimensionName: String,
        unit: String = "",
        startValue: Double,
        hardestValue: Double,
        easiestValue: Double,
        polarity: Staircase.Polarity,
        alternatives: Int,
        initialStepSize: Double = 0.5,
        minimumStepSize: Double = 0.03,
        renderLimit: RenderLimit? = nil
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
        self.renderLimit = renderLimit
    }

    /// A fresh staircase, optionally started easier for younger users. Starting
    /// a six-year-old at the adult default is the fastest way to lose them in
    /// the first ninety seconds.
    ///
    /// Pass the profile's calibration wherever one exists: without it the
    /// staircase can descend to a difficulty this screen cannot actually draw.
    func makeStaircase(ageGroup: AgeGroup = .thirteenPlus,
                       calibration: CalibrationProfile? = nil) -> Staircase {
        let hardest = resolvedHardestValue(for: calibration)
        let easiest = resolvedEasiestValue(for: calibration)
        // Clamp the start into the RESOLVED range, not the declared one. A
        // descriptor whose start sits outside what this screen can draw is a bug
        // the registry-wide tests catch, but a user mid-session should get a
        // playable staircase rather than a start the renderer cannot honour.
        let start = Swift.min(Swift.max(startValue(for: ageGroup),
                                        Swift.min(hardest, easiest)),
                              Swift.max(hardest, easiest))
        return Staircase(
            start: start,
            hardestValue: hardest,
            easiestValue: easiest,
            polarity: polarity,
            initialStepSize: initialStepSize,
            minimumStepSize: minimumStepSize
        )
    }

    /// The hardest value this DISPLAY can honestly present, which is not always
    /// the hardest value the exercise would like.
    ///
    /// WHY THIS EXISTS - and it is the most important twenty lines in the file.
    /// Three of the four bounds originally written for Phase 6 were physically
    /// impossible, checked against the real device table at real viewing
    /// distances:
    ///
    ///   Contrast floor 0.005 - below 8-bit quantisation (2/255 = 0.0078). The
    ///     patch is uniform grey. The observer guesses. The staircase records a
    ///     threshold. The number is noise wearing a lab coat.
    ///   Vernier 20 arcsec - 0.2 pt on an iPhone 14 Pro at 35 cm.
    ///   Landolt -0.1 logMAR - a 0.49 pt gap.
    ///
    /// A staircase that descends past what the screen can draw does not stop
    /// measuring; it starts measuring the display, silently, and reports the
    /// answer with the same confidence as a real one. That is precisely the
    /// failure mode that makes competitor apps' numbers meaningless, and it is
    /// invisible unless you do this arithmetic.
    ///
    /// So the floor is derived at runtime from the user's own calibration rather
    /// than hard-coded, and `isLimitedByDisplay(for:)` lets the UI say so.
    ///
    /// THE DIRECTION OF THE CLAMP BELONGS TO THE LIMIT, NOT TO THE POLARITY.
    /// This method used to read `polarity == .lowerIsHarder ? max : min`, which
    /// is a different claim: that a display limit always bounds whichever end
    /// the exercise calls "hard". That holds for every `.lowerIsHarder`
    /// dimension and for spatial frequency, and it is FALSE for an angular
    /// dimension where bigger is harder.
    ///
    /// D8 Brock Digital measures bead depth in arcminutes, higher-is-harder,
    /// 8...120. Its one-point floor resolves to about 1.5 arcmin — a bound on
    /// the SMALLEST drawable disparity. Taking the minimum turned the hardest
    /// setting into 1.5, i.e. easier than the easiest, collapsing the range and
    /// putting the 25 arcmin start value outside its own staircase. D2 Vergence
    /// Jump had the identical shape. Both shipped through eleven green CI runs
    /// because nothing generated a trial at the resolved bound until the
    /// registry-wide range test did.
    ///
    /// So each limit now states whether its value is a floor or a ceiling, and
    /// both ends are clamped against it.
    func resolvedHardestValue(for calibration: CalibrationProfile?) -> Double {
        clampToRenderable(hardestValue, for: calibration)
    }

    /// The easiest value this display can honestly present. Usually the declared
    /// one — an easy trial is a big one — but an exercise whose easy end is
    /// still sub-pixel on a small screen needs raising too.
    func resolvedEasiestValue(for calibration: CalibrationProfile?) -> Double {
        clampToRenderable(easiestValue, for: calibration)
    }

    private func clampToRenderable(_ value: Double,
                                   for calibration: CalibrationProfile?) -> Double {
        guard let renderLimit,
              let bound = renderLimit.hardestRenderableValue(for: calibration) else {
            return value
        }
        return switch renderLimit.bound {
        case .minimum: Swift.max(value, bound)
        case .maximum: Swift.min(value, bound)
        }
    }

    /// True when the screen, not the exercise design, sets the ceiling on
    /// difficulty. Worth surfacing: it means "you have maxed this out on this
    /// device", not "you have maxed out your vision".
    func isLimitedByDisplay(for calibration: CalibrationProfile?) -> Bool {
        abs(resolvedHardestValue(for: calibration) - hardestValue) > 1e-9
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

// MARK: - Render limit

/// How a staircase dimension is bounded by the physics of the display.
///
/// Each case knows how to turn "the smallest feature I can trust on screen"
/// into a value in that dimension's own units.
enum RenderLimit: Hashable, Sendable {

    /// Dimension is an angle in ARCMINUTES, controlling a feature whose size in
    /// points is proportional to it.
    case arcminutes(minimumFeaturePoints: Double)

    /// Dimension is an angle in ARCSECONDS.
    case arcseconds(minimumFeaturePoints: Double)

    /// Dimension is logMAR. The feature subtends 10^logMAR arcminutes - that is
    /// the definition of the scale, so the conversion is a log, not a multiply.
    case logMAR(minimumFeaturePoints: Double)

    /// Michelson contrast, bounded by 8-bit output. `steps` is how many
    /// quantisation levels of separation are needed before the modulation is
    /// reliably visible rather than dithering noise.
    case contrast(minimumQuantisationSteps: Double)

    /// Spatial frequency in cycles per degree, bounded by Nyquist.
    case cyclesPerDegree(pointsPerCycle: Double)

    /// Which end of the dimension this limit bounds.
    ///
    /// Every angular and contrast limit answers "how small can a feature be
    /// before the screen stops drawing it", so it is a MINIMUM on the value.
    /// Spatial frequency is the odd one out: Nyquist says how FINE a grating can
    /// be, and a finer grating is a larger number, so it is a MAXIMUM.
    ///
    /// Getting this from the polarity instead was the D8/D2 range collapse.
    enum Bound { case minimum, maximum }

    var bound: Bound {
        switch self {
        case .cyclesPerDegree: .maximum
        case .arcminutes, .arcseconds, .logMAR, .contrast: .minimum
        }
    }

    /// The hardest value this calibration can honestly render, or nil if the
    /// limit does not apply (no calibration, or a dimension with no display
    /// dependence at all).
    func hardestRenderableValue(for calibration: CalibrationProfile?) -> Double? {
        // Contrast is set by the framebuffer, not by geometry, so it is the one
        // case that needs no calibration.
        if case .contrast(let steps) = self {
            return (steps / 255.0)
        }

        guard let calibration, calibration.isComplete else { return nil }
        let pointsPerDegree = calibration.points(forDegrees: 1.0)
        guard pointsPerDegree > 0 else { return nil }
        let pointsPerArcminute = pointsPerDegree / 60.0

        switch self {
        case .arcminutes(let minimumPoints):
            return minimumPoints / pointsPerArcminute

        case .arcseconds(let minimumPoints):
            return (minimumPoints / pointsPerArcminute) * 60.0

        case .logMAR(let minimumPoints):
            let arcminutes = minimumPoints / pointsPerArcminute
            return log10(Swift.max(arcminutes, 1e-6))

        case .cyclesPerDegree(let pointsPerCycle):
            return pointsPerDegree / pointsPerCycle

        case .contrast:
            return nil   // handled above
        }
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

    /// How many answers THIS trial offers.
    ///
    /// WHY THIS IS NOT `staircase.alternatives`.
    /// `alternatives` is the chance level the staircase reasons about, and for
    /// exercises whose option count grows with difficulty it is deliberately the
    /// count on the EASIEST trial — the best a guesser ever does. Three
    /// exercises then indexed their answer into the trial's ACTUAL count:
    /// D9 Dichoptic Search runs 4 to 12 items and declares 4, D3 Split Match
    /// runs 3 to 6 and declares 3, G5 Star Tracer declares 3. So a hard search
    /// trial could carry `correctAnswer: 10` against a declared 4, and any
    /// screen that drew `alternatives` buttons would not draw the right answer
    /// at all — an unanswerable trial that scores as wrong.
    ///
    /// Two honest numbers instead of one overloaded one.
    func optionCount(for trial: Trial) -> Int
}

extension Exercise {
    var descriptor: ExerciseDescriptor { Self.descriptor }

    /// Fixed-choice exercises — most of them — have one count for every trial.
    func optionCount(for trial: Trial) -> Int {
        Self.descriptor.staircase.alternatives
    }
}
