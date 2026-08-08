//
//  ProgressAnalyzer.swift
//
//  Turns a user's own trial history into the handful of statements the app is
//  entitled to make. Pure statistics, on device, no model, no network.
//
//  THE ESCALATION RULE IS THE POINT OF THIS FILE.
//  Everything else here is reporting. `shouldEscalateToProfessional` is the one
//  output that exists to act against the app's own commercial interest: after
//  two consecutive four-week blocks with no measurable improvement, the app
//  tells the user to go back to their eye doctor, in a card they cannot dismiss.
//  Amblyopia is time-sensitive, especially in children, and an app that keeps a
//  non-responding user engaged for another three months has done them real harm
//  no matter how good its retention numbers look.
//
//  docs/06-AI-ENGINE-SPEC.md section 3, docs/04-ARCHITECTURE.md section 6.
//

import Foundation

struct ProgressAnalysis: Sendable {

    /// Sessions completed divided by sessions planned.
    let adherence7d: Double
    let adherence28d: Double
    let currentStreak: Int

    /// Per exercise, keyed by exercise id.
    let thresholdTrends: [String: Trend]

    /// The headline metric once the dichoptic track exists (Phase 7).
    let balanceTrend: Trend?
    let acuityTrend: Trend?

    let plateauDetected: Bool
    let blocksWithoutImprovement: Int

    /// Non-dismissible referral card. See the file header.
    let shouldEscalateToProfessional: Bool

    let totalSessions: Int
    let totalMinutes: Int

    /// True when there is not yet enough history to say anything at all. The UI
    /// must show this state rather than an empty chart with a confident zero.
    var isTooEarlyToTell: Bool {
        thresholdTrends.values.allSatisfy { $0.pointCount < Trend.minimumPointsForAClaim }
    }
}

struct ProgressAnalyzer: Sendable {

    /// A four-week block. The literature's dosing studies report change over
    /// this kind of window, not week to week, and week-to-week threshold noise
    /// is large enough to swamp a real effect.
    static let blockDays = 28

    /// Two consecutive flat blocks before escalating. One flat block is
    /// unremarkable — illness, school holidays, a bad fortnight.
    static let blocksBeforeEscalation = 2

    /// One session per day is what the plan assumes.
    static let plannedSessionsPerWeek = 7

    struct Observation: Sendable {
        let exerciseID: String
        let day: Date
        let threshold: Double
        let lowerIsBetter: Bool
    }

    let now: Date

    init(now: Date = .now) { self.now = now }

    // MARK: Analysis

    func analyse(observations: [Observation],
                 sessionDays: [Date],
                 totalMinutes: Int) -> ProgressAnalysis {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        // Trends, one per exercise.
        var trends: [String: Trend] = [:]
        for (exerciseID, group) in Dictionary(grouping: observations, by: \.exerciseID) {
            let sorted = group.sorted { $0.day < $1.day }
            guard let first = sorted.first else { continue }
            let days = sorted.map {
                Double(calendar.dateComponents([.day], from: first.day, to: $0.day).day ?? 0)
            }
            let values = sorted.map(\.threshold)
            if let trend = TrendFitter.fit(days: days, values: values,
                                           lowerIsBetter: first.lowerIsBetter,
                                           // Seeded per exercise so the reported
                                           // interval is stable between launches:
                                           // a confidence interval that visibly
                                           // wobbles on every app open destroys
                                           // trust in the number it qualifies.
                                           seed: Self.stableSeed(for: exerciseID)) {
                trends[exerciseID] = trend
            }
        }

        let activeDays = Set(sessionDays.map { calendar.startOfDay(for: $0) })

        let blocksFlat = countFlatBlocks(observations: observations, today: today)

        return ProgressAnalysis(
            adherence7d: adherence(activeDays: activeDays, days: 7, today: today),
            adherence28d: adherence(activeDays: activeDays, days: 28, today: today),
            currentStreak: streak(activeDays: activeDays, today: today),
            thresholdTrends: trends,
            balanceTrend: trends["d.suppressionCheck"],
            acuityTrend: trends["m.landoltC"],
            plateauDetected: trends.values.contains { $0.isPlateau },
            blocksWithoutImprovement: blocksFlat,
            shouldEscalateToProfessional: blocksFlat >= Self.blocksBeforeEscalation,
            totalSessions: activeDays.count,
            totalMinutes: totalMinutes
        )
    }

    // MARK: Adherence

    /// Days practised in the window, over days in the window. Capped at 1 so a
    /// keen user doing two sessions a day does not read as 200% adherent.
    func adherence(activeDays: Set<Date>, days: Int, today: Date) -> Double {
        guard days > 0 else { return 0 }
        let calendar = Calendar.current
        let window = (0..<days).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
        let hits = window.filter { activeDays.contains(calendar.startOfDay(for: $0)) }.count
        return min(1, Double(hits) / Double(days))
    }

    /// Consecutive days up to today. Today not yet practised does not break a
    /// streak — the day is not over, and punishing someone at 9am for not having
    /// trained yet is how streak mechanics turn into pressure.
    func streak(activeDays: Set<Date>, today: Date) -> Int {
        let calendar = Calendar.current
        var count = 0
        var cursor = today

        if !activeDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return 0
            }
            cursor = yesterday
        }
        while activeDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    // MARK: Escalation

    /// Counts consecutive recent four-week blocks in which no exercise showed a
    /// measurable improvement.
    ///
    /// Note it counts from the most recent block backwards and stops at the
    /// first block that DID improve: the rule is about a run of flat blocks
    /// ending now, not about a flat block six months ago.
    func countFlatBlocks(observations: [Observation], today: Date) -> Int {
        guard !observations.isEmpty else { return 0 }
        let calendar = Calendar.current
        var flat = 0

        for blockIndex in 0..<6 {
            guard
                let blockEnd = calendar.date(byAdding: .day,
                                             value: -blockIndex * Self.blockDays, to: today),
                let blockStart = calendar.date(byAdding: .day,
                                               value: -Self.blockDays, to: blockEnd)
            else { break }

            let inBlock = observations.filter { $0.day > blockStart && $0.day <= blockEnd }
            // A block with too little data is not evidence of a plateau — it is
            // an absence of evidence, and must not count toward escalation.
            guard inBlock.count >= Trend.minimumPointsForAClaim else { break }

            var improvedInThisBlock = false
            for (exerciseID, group) in Dictionary(grouping: inBlock, by: \.exerciseID) {
                let sorted = group.sorted { $0.day < $1.day }
                guard let first = sorted.first,
                      sorted.count >= Trend.minimumPointsForAClaim else { continue }
                let days = sorted.map {
                    Double(calendar.dateComponents([.day], from: first.day, to: $0.day).day ?? 0)
                }
                if let trend = TrendFitter.fit(days: days, values: sorted.map(\.threshold),
                                               lowerIsBetter: first.lowerIsBetter,
                                               seed: Self.stableSeed(for: exerciseID)),
                   trend.direction == .improving {
                    improvedInThisBlock = true
                    break
                }
            }

            if improvedInThisBlock { break }
            flat += 1
        }
        return flat
    }

    /// Deterministic per-exercise seed, so the bootstrap interval for a given
    /// history is identical on every launch.
    static func stableSeed(for exerciseID: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325       // FNV-1a offset basis
        for byte in exerciseID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}
