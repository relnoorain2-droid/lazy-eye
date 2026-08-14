//
//  SessionPlanBuilderTests.swift
//
//  The plan builder turns history into "what's due". Every rule in it is a
//  judgement call, so every rule gets a test that would fail if the judgement
//  were silently changed.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Session plan builder")
struct SessionPlanBuilderTests {

    private let day = 24.0 * 3600
    private let reference = Date(timeIntervalSince1970: 1_770_000_000)   // fixed

    private func builder() -> SessionPlanBuilder {
        SessionPlanBuilder(now: reference)
    }

    private func days(back offsets: [Int]) -> [Date] {
        offsets.map { reference.addingTimeInterval(-Double($0) * day) }
    }

    // MARK: Recency

    @Test("never practised reports nil rather than a large number")
    func neverPractisedIsNil() {
        let history = SessionPlanBuilder.History(exerciseID: "x")
        #expect(builder().daysSinceLastPractised(history) == nil,
                "nil and 'a long time ago' are different states, and the plan generator treats them differently")
    }

    @Test("days since last practised counts calendar days, not elapsed hours")
    func recencyUsesCalendarDays() {
        // Yesterday evening and this morning are 1 day apart even if only a few
        // hours have passed.
        let history = SessionPlanBuilder.History(exerciseID: "x",
                                                trialDays: days(back: [1]))
        #expect(builder().daysSinceLastPractised(history) == 1)
    }

    @Test("a clock that moved backwards cannot produce a negative recency")
    func recencyClampsAtZero() {
        let future = reference.addingTimeInterval(3 * day)
        let history = SessionPlanBuilder.History(exerciseID: "x", trialDays: [future])
        let result = builder().daysSinceLastPractised(history)
        #expect(result == 0,
                "a negative value reads as freshly practised and would bury the exercise forever")
    }

    @Test("recency uses the most recent day, not the first")
    func recencyUsesMostRecent() {
        let history = SessionPlanBuilder.History(exerciseID: "x",
                                                trialDays: days(back: [40, 2, 30]))
        #expect(builder().daysSinceLastPractised(history) == 2)
    }

    // MARK: Reliability

    @Test("threshold reliability counts distinct days, not trials")
    func reliabilityCountsDays() {
        // 40 trials, all on one day. That is one observation of ability, not 40.
        let sameDay = Array(repeating: reference.addingTimeInterval(-day), count: 40)
        let history = SessionPlanBuilder.History(exerciseID: "x", trialDays: sameDay)
        #expect(builder().distinctPracticeDays(history) == 1)
        #expect(builder().hasReliableThreshold(history) == false)
    }

    @Test("reliability threshold matches the trend module's minimum")
    func reliabilityMatchesTrend() {
        #expect(SessionPlanBuilder.daysForReliableThreshold == Trend.minimumPointsForAClaim,
                "two different answers to 'is this number trustworthy' is one too many")

        let enough = SessionPlanBuilder.History(
            exerciseID: "x",
            trialDays: days(back: Array(1...SessionPlanBuilder.daysForReliableThreshold)))
        #expect(builder().hasReliableThreshold(enough))

        let oneShort = SessionPlanBuilder.History(
            exerciseID: "x",
            trialDays: days(back: Array(1..<SessionPlanBuilder.daysForReliableThreshold)))
        #expect(builder().hasReliableThreshold(oneShort) == false)
    }

    // MARK: Medians

    @Test("daily median ignores the extremes a staircase visits on its way down")
    func medianResistsCoarseDescent() {
        let today = reference
        let history = SessionPlanBuilder.History(
            exerciseID: "x",
            trialDays: Array(repeating: today, count: 5),
            // 0.9 and 0.8 are the coarse descent; the real threshold is ~0.2.
            difficulties: [0.9, 0.8, 0.2, 0.21, 0.19])
        let medians = builder().dailyMedians(history)
        #expect(medians.count == 1)
        #expect((medians.first?.value ?? 1.0) < 0.3,
                "the mean of that set is 0.46, which is nowhere near the threshold")
    }

    @Test("mismatched arrays produce no medians rather than a crash")
    func mismatchedArraysAreSafe() {
        let history = SessionPlanBuilder.History(exerciseID: "x",
                                                trialDays: days(back: [1, 2, 3]),
                                                difficulties: [0.5])
        #expect(builder().dailyMedians(history).isEmpty,
                "zip would silently drop data; returning nothing is the honest answer")
    }

    @Test("medians come back oldest first")
    func mediansAreOrdered() {
        let history = SessionPlanBuilder.History(
            exerciseID: "x",
            trialDays: days(back: [1, 5, 3]),
            difficulties: [0.1, 0.5, 0.3])
        let medians = builder().dailyMedians(history)
        #expect(medians.count == 3)
        #expect(medians.map(\.value) == [0.5, 0.3, 0.1],
                "5 days ago first, yesterday last")
    }

    // MARK: Mastery

    /// A history sitting right at the bound for the last `atBound` days, with
    /// enough distinct days to be reliable.
    private func masteredHistory(bound: Double, atBound: Int,
                                 easierValue: Double) -> SessionPlanBuilder.History {
        let total = SessionPlanBuilder.daysForReliableThreshold
        var trialDays: [Date] = []
        var difficulties: [Double] = []
        for offset in stride(from: total, through: 1, by: -1) {
            trialDays.append(reference.addingTimeInterval(-Double(offset) * day))
            difficulties.append(offset <= atBound ? bound : easierValue)
        }
        return SessionPlanBuilder.History(exerciseID: "x",
                                          trialDays: trialDays,
                                          difficulties: difficulties)
    }

    @Test("mastery needs the bound held for three days, not one")
    func masteryNeedsThreeDays() {
        let oneDay = masteredHistory(bound: 0.1, atBound: 1, easierValue: 0.6)
        #expect(builder().isMastered(oneDay, hardestValue: 0.1,
                                    polarity: .lowerIsHarder) == false,
                "one day at the bound is noise")

        let threeDays = masteredHistory(bound: 0.1, atBound: 3, easierValue: 0.6)
        #expect(builder().isMastered(threeDays, hardestValue: 0.1,
                                    polarity: .lowerIsHarder),
                "three days at the bound is the staircase saying it has nowhere left to go")
    }

    @Test("mastery is impossible without a reliable threshold")
    func masteryNeedsReliability() {
        let short = SessionPlanBuilder.History(
            exerciseID: "x",
            trialDays: days(back: [1, 2, 3]),
            difficulties: [0.1, 0.1, 0.1])
        #expect(builder().isMastered(short, hardestValue: 0.1,
                                    polarity: .lowerIsHarder) == false)
    }

    @Test("mastery respects polarity in both directions")
    func masteryRespectsPolarity() {
        // Sitting at 12 with the bound at 12: mastered when higher is harder.
        let atCeiling = masteredHistory(bound: 12.0, atBound: 3, easierValue: 2.0)
        #expect(builder().isMastered(atCeiling, hardestValue: 12.0,
                                    polarity: .higherIsHarder))

        // Sitting at 2 with the bound still at 12. Under `higherIsHarder` that
        // is the EASY end and nothing has been mastered; under `lowerIsHarder`
        // the same numbers mean the opposite. Testing with values that differ
        // from the bound is the only way to tell the two apart — a history that
        // sits exactly ON the bound satisfies both comparisons.
        let atFloor = masteredHistory(bound: 2.0, atBound: 3, easierValue: 12.0)
        #expect(builder().isMastered(atFloor, hardestValue: 12.0,
                                    polarity: .higherIsHarder) == false,
                "2 is nowhere near a ceiling of 12")
        #expect(builder().isMastered(atFloor, hardestValue: 12.0,
                                    polarity: .lowerIsHarder),
                "the same three values are comfortably under a floor of 12")
    }

    @Test("mastery uses the bound this display can render, not the descriptor's")
    func masteryUsesDisplayBound() {
        // The person has bottomed out at 0.05 because that is all the screen can
        // show. Judged against a descriptor bound of 0.01 they are not mastered,
        // and the exercise would be offered forever at a level it cannot present.
        let history = masteredHistory(bound: 0.05, atBound: 3, easierValue: 0.6)
        #expect(builder().isMastered(history, hardestValue: 0.01,
                                    polarity: .lowerIsHarder) == false)
        #expect(builder().isMastered(history, hardestValue: 0.05,
                                    polarity: .lowerIsHarder),
                "clamping to what the display can do is the whole reason RenderLimit exists")
    }

    @Test("tolerance is proportional, so it doesn't swamp small bounds")
    func toleranceIsProportional() {
        // 5% of 0.1 is 0.005. A value of 0.11 must NOT count as mastered.
        let justOver = masteredHistory(bound: 0.11, atBound: 3, easierValue: 0.6)
        #expect(builder().isMastered(justOver, hardestValue: 0.1,
                                    polarity: .lowerIsHarder) == false)

        let justWithin = masteredHistory(bound: 0.104, atBound: 3, easierValue: 0.6)
        #expect(builder().isMastered(justWithin, hardestValue: 0.1,
                                    polarity: .lowerIsHarder),
                "floating-point equality at a staircase bound never holds exactly")
    }

    // MARK: States

    @Test("states are produced for every descriptor, practised or not")
    func statesCoverAllDescriptors() {
        let descriptors = Array(ExerciseRegistry.all.prefix(4))
        let states = builder().states(for: descriptors, histories: [:])
        #expect(states.count == descriptors.count)
        #expect(states.allSatisfy { $0.daysSinceLastPractised == nil })
        #expect(states.allSatisfy { !$0.isMastered })
        #expect(states.allSatisfy { !$0.hasReliableThreshold })
    }

    @Test("fatigue endings become frustration events the plan generator can see")
    func fatigueBecomesFrustration() throws {
        let descriptor = try #require(ExerciseRegistry.all.first)
        let history = SessionPlanBuilder.History(exerciseID: descriptor.id,
                                                 trialDays: days(back: [1]),
                                                 difficulties: [0.5],
                                                 fatigueEndings: 3)
        let states = builder().states(for: [descriptor],
                                     histories: [descriptor.id: history])
        #expect(states.first?.frustrationEvents == 3)
    }

    @Test("a missing hardest value falls back to the descriptor's own bound")
    func missingHardestValueFallsBack() throws {
        let descriptor = try #require(ExerciseRegistry.all.first)
        let bound = descriptor.staircase.hardestValue
        let history = masteredHistory(bound: bound, atBound: 3,
                                      easierValue: descriptor.staircase.easiestValue)
        let states = builder().states(for: [descriptor],
                                      histories: [descriptor.id: history],
                                      hardestValues: [:])
        #expect(states.first?.isMastered == true,
                "with no display correction supplied, the descriptor's bound is the right default")
    }

    // MARK: End to end

    @Test("a fresh user's plan is non-empty and inside the cap")
    func freshUserGetsAPlan() {
        let descriptors = ExerciseRegistry.available(track: .monocular)
        let states = builder().states(for: descriptors, histories: [:])
        let cap = SessionCap(ageGroup: .thirteenPlus, secondsUsedToday: 0)
        let plan = PlanGenerator(now: reference).plan(states: states, cap: cap,
                                                     requestedSeconds: 20 * 60)
        #expect(!plan.isEmpty)
        #expect(plan.totalSeconds <= cap.allowedSessionSeconds(requested: 20 * 60))
        #expect(!plan.rationale.isEmpty, "the Today screen shows this sentence")
    }

    @Test("a used-up day yields an empty plan rather than a zero-length session")
    func capReachedYieldsEmptyPlan() {
        let states = builder().states(for: ExerciseRegistry.available(track: .monocular),
                                      histories: [:])
        let cap = SessionCap(ageGroup: .underFive, secondsUsedToday: 60 * 60)
        let plan = PlanGenerator(now: reference).plan(states: states, cap: cap,
                                                     requestedSeconds: 10 * 60)
        #expect(plan.isEmpty)
        #expect(plan.totalSeconds == 0)
    }

    @Test("mastered exercises rank below unpractised ones")
    func masteredRanksLower() throws {
        let descriptors = Array(ExerciseRegistry.available(track: .monocular).prefix(6))
        let first = try #require(descriptors.first)
        let bound = first.staircase.hardestValue

        var histories: [String: SessionPlanBuilder.History] = [:]
        histories[first.id] = masteredHistory(bound: bound, atBound: 3,
                                              easierValue: first.staircase.easiestValue)

        let states = builder().states(for: descriptors, histories: histories,
                                      hardestValues: [first.id: bound])
        let plan = PlanGenerator(now: reference).plan(
            states: states,
            cap: SessionCap(ageGroup: .thirteenPlus, secondsUsedToday: 0),
            requestedSeconds: 20 * 60)

        #expect(!plan.items.contains { $0.exerciseID == first.id },
                "a mastered exercise should not be the app's suggestion while five untouched ones exist")
    }
}
