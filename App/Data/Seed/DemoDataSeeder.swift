//
//  DemoDataSeeder.swift
//
//  Generates a realistic 12-week training history.
//
//  This exists for three reasons and all three matter:
//    1. Every App Store screenshot needs charts with believable data
//       (docs/11-SCREENSHOTS-SPEC.md section 3 — empty charts kill conversion).
//    2. ProgressAnalyzer in Phase 9 needs a fixture to develop against.
//    3. App Review needs to see the app populated, not empty.
//
//  DESIGN RULES:
//    - Deterministic. Same seed, same data, byte for byte. Screenshots must be
//      reproducible across CI runs or every regeneration produces a diff.
//    - Honest. The curve shows diminishing returns and a real plateau at the
//      end, not a straight line to perfection. We are not going to ship a
//      screenshot implying results we can't support
//      (docs/08-COMPLIANCE-LEGAL.md section 3).
//    - Imperfect adherence. A gap in weeks 5-6, a few short sessions, one
//      fatigue stop. Real users look like this, and the app must render it well.
//
//  ONLY runs behind -uitest-seed-demo-data. Never in a shipping user session.
//

import Foundation
import SwiftData
import os

enum DemoDataSeeder {

    private static let log = Logger(subsystem: "com.amblyo.app", category: "seed")

    /// Fixed so screenshot regeneration is diff-free across CI runs.
    static let defaultSeed: UInt64 = 20_260_806

    // MARK: Entry point

    @MainActor
    static func seed(into context: ModelContext, seed: UInt64 = defaultSeed, now: Date = .now) {
        do {
            // Never double-seed.
            let existing = try context.fetchCount(FetchDescriptor<Profile>())
            guard existing == 0 else {
                log.info("Demo data skipped — \(existing) profile(s) already present.")
                return
            }
            var rng = SeededGenerator(seed: seed)
            try build(context: context, rng: &rng, now: now)
            try context.save()
            log.info("Demo data seeded.")
        } catch {
            log.error("Demo seeding failed: \(error.localizedDescription)")
        }
    }

    // MARK: Construction

    @MainActor
    private static func build(context: ModelContext, rng: inout SeededGenerator, now: Date) throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(Plan.totalDays - 1), to: today)!

        // --- Profile -------------------------------------------------------

        let profile = Profile(
            name: "Maya",
            birthYear: calendar.component(.year, from: now) - 9,
            ageGroup: .fiveToTwelve,
            amblyopicEye: .left,
            wearsCorrection: true,
            isKidsMode: true,
            isActive: true,
            createdAt: start,
            preferences: PreferencesBlob(
                reminderEnabled: true,
                reminderHour: 17,
                reminderMinute: 30,
                hasAcknowledgedDisclaimer: true,
                hasSeenOcclusionWarning: true
            )
        )
        context.insert(profile)

        let calibration = CalibrationProfile(
            profile: profile,
            screenPointsPerCM: 26.5,          // ~11" iPad, replaced by real lookup in Phase 3
            screenSizeUserVerified: true,
            viewingDistanceCM: 50,
            anaglyphFilter: .red,
            redLeakIntoCyan: 0.07,
            cyanLeakIntoRed: 0.05,
            colorVisionOK: true,
            fellowEyeContrast: Plan.fellowContrast(dayIndex: Plan.totalDays - 1),
            calibratedAt: start,
            anaglyphCalibratedAt: calendar.date(byAdding: .day, value: 1, to: start),
            deviceIdentifier: "iPad13,4"
        )
        context.insert(calibration)
        profile.calibration = calibration

        // --- Sessions ------------------------------------------------------

        for dayIndex in 0..<Plan.totalDays {
            guard Plan.trained(dayIndex: dayIndex, rng: &rng) else { continue }
            let day = calendar.date(byAdding: .day, value: dayIndex, to: start)!

            for track in Plan.tracks(dayIndex: dayIndex) {
                try makeSession(
                    context: context,
                    profile: profile,
                    track: track,
                    day: day,
                    dayIndex: dayIndex,
                    rng: &rng
                )
            }
        }

        // --- Weekly assessments -------------------------------------------

        for week in 0..<Plan.weeks {
            let dayIndex = week * 7 + 6
            guard dayIndex < Plan.totalDays else { continue }
            let day = calendar.date(byAdding: .day, value: dayIndex, to: start)!
            let result = makeAssessment(week: week, dayIndex: dayIndex, day: day, rng: &rng)
            result.profile = profile
            result.blockIndex = dayIndex / 28
            context.insert(result)
        }

        // --- Metadata ------------------------------------------------------

        let meta = AppMetadata(firstLaunchedAt: start, lastOpenedAt: now, demoDataSeeded: true)
        context.insert(meta)
    }

    // MARK: Sessions

    @MainActor
    private static func makeSession(
        context: ModelContext,
        profile: Profile,
        track: Track,
        day: Date,
        dayIndex: Int,
        rng: inout SeededGenerator
    ) throws {
        let calendar = Calendar.current
        let hour = track == .dichoptic ? 17 : 18
        let minute = Int.random(in: 0...45, using: &rng)
        let startedAt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!

        let planned = profile.ageGroup.defaultSessionSeconds
        let (actual, reason) = Plan.outcome(dayIndex: dayIndex, planned: planned, rng: &rng)

        let session = SessionRecord(
            profile: profile,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(TimeInterval(actual)),
            plannedSeconds: planned,
            actualSeconds: actual,
            track: track,
            endedReason: reason,
            fellowEyeContrast: track == .dichoptic ? Plan.fellowContrast(dayIndex: dayIndex) : nil,
            breakCount: actual > 20 * 60 ? 1 : 0
        )
        context.insert(session)

        guard reason.producesValidData else { return }

        for exerciseID in Plan.exercises(for: track) {
            let trialCount = Int.random(in: 28...44, using: &rng)
            var difficulty = Plan.startingDifficulty(exerciseID: exerciseID, dayIndex: dayIndex)

            for trialIndex in 0..<trialCount {
                // A 3-down/1-up staircase converges near 79% correct, so that is
                // roughly what the generated accuracy should look like.
                let correct = Double.random(in: 0...1, using: &rng) < 0.79
                let discarded = Double.random(in: 0...1, using: &rng) < 0.015

                let offset = Double(trialIndex) * (Double(actual) / Double(trialCount * max(1, Plan.exercises(for: track).count)))
                let trial = TrialRecord(
                    session: session,
                    exerciseID: exerciseID,
                    timestamp: startedAt.addingTimeInterval(offset),
                    correct: correct,
                    responseTimeMS: Int.random(in: 420...1650, using: &rng),
                    difficultyValue: difficulty,
                    targetEye: track == .monocular ? profile.amblyopicEye : .unknown,
                    discarded: discarded,
                    discardReason: discarded ? "droppedFrame" : nil
                )
                context.insert(trial)

                // Move the staircase: harder on success, easier on failure.
                difficulty *= correct ? 0.97 : 1.05
                difficulty = max(difficulty, Plan.floor(exerciseID: exerciseID))
            }
        }
    }

    // MARK: Assessments

    private static func makeAssessment(
        week: Int, dayIndex: Int, day: Date, rng: inout SeededGenerator
    ) -> AssessmentResult {
        // Draw every jitter up front. An inout parameter cannot be captured by a
        // closure in Swift, and interleaving draws inside `map` would make the
        // sequence order-dependent and therefore fragile.
        let jStereo = Double.random(in: -18...18, using: &rng)
        let jAcuityAmblyopic = Double.random(in: -0.015...0.015, using: &rng)
        let jAcuityFellow = Double.random(in: -0.012...0.012, using: &rng)
        let jBalance = Double.random(in: -0.012...0.012, using: &rng)
        var jContrast: [Double] = []
        for _ in 0..<4 { jContrast.append(Double.random(in: -0.04...0.04, using: &rng)) }
        let duration = Int.random(in: 320...420, using: &rng)

        // Stereo is absent early — common in real amblyopia, and it makes the
        // moment it appears meaningful rather than decorative.
        let stereo: Double? = week < 3
            ? nil
            : max(110, 460 * pow(0.87, Double(week - 3)) + jStereo)

        let thresholds = zip(Plan.contrastThresholds(week: week), jContrast)
            .map { $0 * (1 + $1) }

        return AssessmentResult(
            date: Calendar.current.date(bySettingHour: 19, minute: 5, second: 0, of: day)!,
            blockIndex: dayIndex / 28,
            acuityAmblyopic: Plan.acuity(week: week) + jAcuityAmblyopic,
            acuityFellow: 0.02 + jAcuityFellow,
            contrastThresholds: thresholds,
            binocularBalance: Plan.balance(week: week) + jBalance,
            stereoArcmin: stereo,
            stereoNotDetected: week < 3,
            durationSeconds: duration
        )
    }
}

// MARK: - The curve
//
// Isolated so the shape of the story is inspectable and testable in one place.

extension DemoDataSeeder {

    enum Plan {
        static let weeks = 12
        static let totalDays = weeks * 7          // 84

        /// Overall adherence ~72%, with a visible slump in weeks 5-6. Real
        /// histories have gaps; a chart without them looks fake and teaches the
        /// analyzer nothing.
        static func trained(dayIndex: Int, rng: inout SeededGenerator) -> Bool {
            let week = dayIndex / 7
            let probability: Double = switch week {
            case 0...1: 0.86      // honeymoon
            case 2...3: 0.78
            case 4...5: 0.45      // the slump
            case 6...8: 0.79      // recovery
            default:    0.72
            }
            return Double.random(in: 0...1, using: &rng) < probability
        }

        static func tracks(dayIndex: Int) -> [Track] {
            // Anaglyph calibration lands on day 1, so no dichoptic before then.
            guard dayIndex >= 2 else { return [.monocular] }
            return dayIndex % 3 == 0 ? [.dichoptic, .game] : [.dichoptic, .monocular]
        }

        static func outcome(dayIndex: Int, planned: Int, rng: inout SeededGenerator) -> (Int, EndReason) {
            let roll = Double.random(in: 0...1, using: &rng)
            return switch roll {
            case ..<0.05: (Int(Double(planned) * Double.random(in: 0.25...0.5, using: &rng)), .fatigue)
            case ..<0.12: (Int(Double(planned) * Double.random(in: 0.45...0.75, using: &rng)), .userStopped)
            case ..<0.15: (Int(Double(planned) * Double.random(in: 0.1...0.3, using: &rng)), .interrupted)
            default:      (Int(Double(planned) * Double.random(in: 0.92...1.0, using: &rng)), .completed)
            }
        }

        /// Amblyopic-eye acuity, logMAR-style. 0.60 → ~0.38 with diminishing
        /// returns and a genuine plateau over the last three weeks.
        static func acuity(week: Int) -> Double {
            let plateauStart = 9
            let effective = min(week, plateauStart)
            return 0.60 - 0.22 * (1 - exp(-Double(effective) / 3.4))
        }

        /// Binocular balance, 0…1. The headline metric: 0.28 → ~0.47.
        static func balance(week: Int) -> Double {
            0.28 + 0.19 * (1 - exp(-Double(week) / 4.0))
        }

        /// Contrast thresholds at 1.5, 3, 6, 12 c/deg. Lower is better.
        static func contrastThresholds(week: Int) -> [Double] {
            let gain = 1 - 0.30 * (1 - exp(-Double(min(week, 9)) / 3.8))
            return [0.021, 0.028, 0.055, 0.130].map { $0 * gain }
        }

        /// The contrast-rebalance ramp: 0.20 → ~0.78 across the programme.
        /// This is the therapeutic variable (docs/01-RESEARCH-BRIEF.md section 4).
        static func fellowContrast(dayIndex: Int) -> Double {
            min(0.80, 0.20 + 0.60 * (Double(dayIndex) / Double(totalDays)))
        }

        static func exercises(for track: Track) -> [String] {
            switch track {
            case .monocular: ["m.gaborOrientation", "m.contrastDetection", "m.crowdedLetters"]
            case .dichoptic: ["d.fallingBlocks", "d.suppressionCheck", "d.randomDotStereo"]
            case .game: ["g.balloonPop", "g.skyCatch"]
            case .assessment: []
            }
        }

        static func startingDifficulty(exerciseID: String, dayIndex: Int) -> Double {
            let progress = Double(dayIndex) / Double(totalDays)
            return switch exerciseID {
            case "m.gaborOrientation": 20.0 * (1 - 0.6 * progress)      // degrees
            case "m.contrastDetection": 0.50 * (1 - 0.7 * progress)     // Michelson contrast
            case "m.crowdedLetters": 1.0 * (1 - 0.4 * progress)         // logMAR-ish
            case "d.randomDotStereo": 600.0 * (1 - 0.7 * progress)      // arc-seconds
            default: 1.0 - 0.5 * progress
            }
        }

        static func floor(exerciseID: String) -> Double {
            switch exerciseID {
            case "m.gaborOrientation": 1.0
            case "m.contrastDetection": 0.005
            case "m.crowdedLetters": 0.1
            case "d.randomDotStereo": 40.0
            default: 0.05
            }
        }
    }
}

// MARK: - Deterministic RNG
//
// SplitMix64. Small, fast, good enough for fixtures, and — critically —
// reproducible across platforms and Swift versions, which `SystemRandomNumberGenerator`
// is not. Screenshot regeneration must be diff-free.

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
