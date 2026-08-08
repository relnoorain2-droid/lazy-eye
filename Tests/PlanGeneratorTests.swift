//
//  PlanGeneratorTests.swift
//
//  Every assertion here pins a judgement call. If someone later changes a
//  weight, the test that breaks tells them which behaviour they traded away.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Plan generator")
struct PlanGeneratorTests {

    private func state(_ id: String,
                       tier: EvidenceTier = .b,
                       daysSince: Int? = 1,
                       mastered: Bool = false,
                       frustration: Int = 0,
                       reliable: Bool = true) -> PlanGenerator.ExerciseState {
        let descriptor = ExerciseDescriptor(
            id: id, title: id, track: .monocular, evidenceTier: tier,
            summary: "", targets: "",
            staircase: StaircaseConfiguration(
                dimensionName: "x", startValue: 10, hardestValue: 1,
                easiestValue: 20, polarity: .lowerIsHarder, alternatives: 2),
            safety: .still)
        return .init(descriptor: descriptor,
                     daysSinceLastPractised: daysSince,
                     isMastered: mastered,
                     frustrationEvents: frustration,
                     hasReliableThreshold: reliable)
    }

    private let generator = PlanGenerator()
    private let openCap = SessionCap(ageGroup: .thirteenPlus, secondsUsedToday: 0)

    // MARK: Ranking

    @Test("Better evidence wins when everything else is equal")
    func evidenceOutranks() {
        let a = generator.score(state("a", tier: .a))
        let b = generator.score(state("b", tier: .b))
        let c = generator.score(state("c", tier: .c))
        #expect(a > b && b > c)
    }

    @Test("Never-practised exercises come first")
    func noveltyWins() {
        #expect(generator.score(state("new", daysSince: nil))
                > generator.score(state("old", daysSince: 3)))
    }

    @Test("Neglect raises priority, saturating after a week")
    func neglectSaturates() {
        let day1 = generator.score(state("x", daysSince: 1))
        let day5 = generator.score(state("x", daysSince: 5))
        let day7 = generator.score(state("x", daysSince: 7))
        let day30 = generator.score(state("x", daysSince: 30))

        #expect(day5 > day1)
        #expect(day7 > day5)
        // After a week everything is overdue, so the signal stops carrying
        // information and must not keep growing without bound.
        #expect(abs(day30 - day7) < 1e-9)
    }

    @Test("Already practised today drops to the back, but is not forbidden")
    func doneTodayDeprioritised() {
        let today = generator.score(state("x", daysSince: 0))
        let yesterday = generator.score(state("x", daysSince: 1))
        #expect(today < yesterday)
        #expect(today > 0, "a second session should be possible, just not suggested")
    }

    @Test("Mastered exercises are retired, not deleted")
    func masteryRetires() {
        let mastered = generator.score(state("x", mastered: true))
        let normal = generator.score(state("x"))
        #expect(mastered < normal)
        #expect(mastered > 0,
                "a library that shrinks as you improve reads as a punishment")
    }

    @Test("Repeated frustration backs an exercise off")
    func frustrationBacksOff() {
        #expect(generator.score(state("x", frustration: 3))
                < generator.score(state("x", frustration: 0)))
        // One bad run is not a pattern.
        #expect(generator.score(state("x", frustration: 1))
                == generator.score(state("x", frustration: 0)))
    }

    // MARK: Plan shape

    @Test("A plan uses the whole budget, exactly")
    func budgetIsExact() {
        let states = ["a", "b", "c", "d"].map { state($0) }
        for requested in [600, 900, 1_200, 1_500] {
            let plan = generator.plan(states: states, cap: openCap,
                                      requestedSeconds: requested)
            #expect(plan.totalSeconds == requested,
                    "requested \(requested), planned \(plan.totalSeconds)")
        }
    }

    @Test("Longer sessions get more variety")
    func varietyScalesWithLength() {
        let states = ["a", "b", "c", "d"].map { state($0) }
        #expect(generator.plan(states: states, cap: openCap,
                               requestedSeconds: 10 * 60).items.count == 2)
        #expect(generator.plan(states: states, cap: openCap,
                               requestedSeconds: 20 * 60).items.count == 3)
    }

    @Test("The daily cap is respected and explained")
    func capRespected() {
        let capped = SessionCap(ageGroup: .fiveToTwelve, secondsUsedToday: 20 * 60)
        let plan = generator.plan(states: [state("a")], cap: capped,
                                  requestedSeconds: 600)
        #expect(plan.isEmpty)
        #expect(plan.totalSeconds == 0)
        #expect(plan.rationale.contains("today"))
    }

    @Test("A partial remaining budget is used, not rounded away")
    func partialBudget() {
        let capped = SessionCap(ageGroup: .fiveToTwelve, secondsUsedToday: 17 * 60)
        let plan = generator.plan(states: ["a", "b"].map { state($0) },
                                  cap: capped, requestedSeconds: 20 * 60)
        #expect(plan.totalSeconds == 3 * 60)
    }

    @Test("An empty library produces an empty plan rather than a crash")
    func emptyLibrary() {
        let plan = generator.plan(states: [], cap: openCap, requestedSeconds: 600)
        #expect(plan.isEmpty)
        #expect(!plan.rationale.isEmpty)
    }

    // MARK: Stability

    @Test("The same inputs always produce the same plan")
    func planIsStable() {
        // Two exercises with identical scores must not reshuffle between
        // launches — a plan that changes when nothing changed looks broken.
        let states = ["b", "a"].map { state($0, tier: .b, daysSince: 2) }
        let first = generator.plan(states: states, cap: openCap, requestedSeconds: 900)
        let second = generator.plan(states: states.reversed(), cap: openCap,
                                    requestedSeconds: 900)
        #expect(first == second)
        #expect(first.items.first?.exerciseID == "a", "ties break on id, ascending")
    }

    @Test("Rationale never claims an outcome")
    func rationaleMakesNoClaims() {
        // docs/08-COMPLIANCE-LEGAL.md section 3. The plan explains what it chose
        // and why, never what it will achieve.
        let banned = ["improve", "cure", "fix", "treat", "heal", "correct",
                      "restore", "better vision", "will help"]
        let scenarios: [[PlanGenerator.ExerciseState]] = [
            ["a", "b"].map { state($0, daysSince: nil) },
            ["a", "b"].map { state($0, daysSince: 6) },
            ["a", "b"].map { state($0, frustration: 3) },
            ["a", "b"].map { state($0, daysSince: 1) }
        ]
        for states in scenarios {
            let text = generator.plan(states: states, cap: openCap,
                                      requestedSeconds: 900).rationale.lowercased()
            for phrase in banned {
                #expect(!text.contains(phrase), "rationale contains '\(phrase)': \(text)")
            }
        }
    }
}
