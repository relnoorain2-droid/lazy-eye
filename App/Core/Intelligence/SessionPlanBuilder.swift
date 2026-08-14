//
//  SessionPlanBuilder.swift
//
//  Turns stored history into the `ExerciseState` values `PlanGenerator` scores.
//
//  WHY THIS IS A SEPARATE TYPE RATHER THAN CODE IN TodayView
//  "Which exercise is due?" is arithmetic over dates and trial counts, and every
//  term in it is a judgement someone should be able to argue with. Buried in a
//  view body it can only be checked by launching the app and squinting; here it
//  is a pure function over plain values, and the tests can pin each rule.
//
//  THERE IS NO PERSISTED STAIRCASE.
//  Only sessions and trials are stored, so mastery and threshold reliability are
//  DERIVED. That is a deliberate trade: a persisted staircase would be a more
//  direct answer, but it would also be a second source of truth that can drift
//  from the trial log. The derivations below are conservative — they under-claim
//  rather than over-claim, because the cost of wrongly calling something
//  mastered is that the app stops offering the exercise that was working.
//
//  docs/06-AI-ENGINE-SPEC.md section 3.
//

import Foundation

struct SessionPlanBuilder: Sendable {

    /// One row per exercise, as read out of the store. Deliberately plain values
    /// — no SwiftData models — so this is testable without a container.
    struct History: Sendable {
        let exerciseID: String
        /// Every non-discarded trial for this exercise, newest last.
        let trialDays: [Date]
        /// Difficulty values of non-discarded trials, paired with `trialDays`.
        let difficulties: [Double]
        /// Sessions this exercise appeared in that ended for fatigue. The
        /// closest thing the store has to the staircase's frustration counter.
        let fatigueEndings: Int

        init(exerciseID: String, trialDays: [Date] = [],
             difficulties: [Double] = [], fatigueEndings: Int = 0) {
            self.exerciseID = exerciseID
            self.trialDays = trialDays
            self.difficulties = difficulties
            self.fatigueEndings = fatigueEndings
        }
    }

    /// Distinct practice days needed before a threshold is treated as trendable.
    /// Matches `Trend.minimumPointsForAClaim` on purpose: a threshold "reliable"
    /// here but untrendable there would be two different claims about the same
    /// number.
    static let daysForReliableThreshold = Trend.minimumPointsForAClaim

    /// Mastery needs BOTH a reliable threshold and the last three practice days
    /// sitting within a whisker of the hardest renderable value. Sitting at the
    /// bound for one day is noise; three days is the staircase telling us it has
    /// nowhere left to go.
    static let daysAtBoundForMastery = 3
    static let masteryToleranceFraction = 0.05

    let now: Date

    init(now: Date = .now) { self.now = now }

    // MARK: States

    /// - Parameter hardestValues: the hardest value each exercise can actually
    ///   be rendered at ON THIS DISPLAY, keyed by exercise id. The caller
    ///   computes these with `descriptor.staircase.resolvedHardestValue(for:)`, which
    ///   needs the live `CalibrationProfile`, which is a SwiftData model and so
    ///   deliberately kept out of this `Sendable` type. Anything missing falls
    ///   back to the descriptor's own bound.
    func states(for descriptors: [ExerciseDescriptor],
                histories: [String: History],
                hardestValues: [String: Double] = [:]) -> [PlanGenerator.ExerciseState] {
        descriptors.map { descriptor in
            let history = histories[descriptor.id] ?? History(exerciseID: descriptor.id)
            let hardest = hardestValues[descriptor.id] ?? descriptor.staircase.hardestValue
            return PlanGenerator.ExerciseState(
                descriptor: descriptor,
                daysSinceLastPractised: daysSinceLastPractised(history),
                isMastered: isMastered(history, hardestValue: hardest,
                                       polarity: descriptor.staircase.polarity),
                frustrationEvents: history.fatigueEndings,
                hasReliableThreshold: hasReliableThreshold(history))
        }
    }

    func daysSinceLastPractised(_ history: History) -> Int? {
        guard let last = history.trialDays.max() else { return nil }
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: last)
        let to = calendar.startOfDay(for: now)
        // Clamped at zero: a device whose clock moved backwards would otherwise
        // produce a negative "days since", which reads as freshly practised and
        // would push the exercise to the bottom of the plan forever.
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    func distinctPracticeDays(_ history: History) -> Int {
        Set(history.trialDays.map { Calendar.current.startOfDay(for: $0) }).count
    }

    func hasReliableThreshold(_ history: History) -> Bool {
        distinctPracticeDays(history) >= Self.daysForReliableThreshold
    }

    /// Per-day medians, oldest first. Median rather than mean because a
    /// staircase visits extremes during its coarse descent and the mean is
    /// dragged by them.
    func dailyMedians(_ history: History) -> [(day: Date, value: Double)] {
        guard history.trialDays.count == history.difficulties.count else { return [] }
        let calendar = Calendar.current
        var byDay: [Date: [Double]] = [:]
        for (day, value) in zip(history.trialDays, history.difficulties) {
            byDay[calendar.startOfDay(for: day), default: []].append(value)
        }
        return byDay.keys.sorted().map { day in
            let sorted = byDay[day]!.sorted()
            return (day, sorted[sorted.count / 2])
        }
    }

    /// - Parameter hardestValue: the bound this DISPLAY can reach, not
    ///   necessarily the one the descriptor asks for. Without that correction a
    ///   device that physically cannot render the hardest level would never call
    ///   anything mastered.
    func isMastered(_ history: History, hardestValue hardest: Double,
                    polarity: Staircase.Polarity) -> Bool {
        guard hasReliableThreshold(history) else { return false }

        let medians = dailyMedians(history)
        guard medians.count >= Self.daysAtBoundForMastery else { return false }

        let recent = medians.suffix(Self.daysAtBoundForMastery).map(\.value)
        let tolerance = abs(hardest) * Self.masteryToleranceFraction

        switch polarity {
        case .lowerIsHarder:
            return recent.allSatisfy { $0 <= hardest + tolerance }
        case .higherIsHarder:
            return recent.allSatisfy { $0 >= hardest - tolerance }
        }
    }
}
