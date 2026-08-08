//
//  PlanGenerator.swift
//
//  Chooses what to practise next. Deterministic scoring, no model.
//
//  WHY WEIGHTS AND NOT A SCHEDULE
//  A fixed rotation is what every competitor does, and it is wrong for the same
//  reason a fixed difficulty is wrong: it ignores the person. Someone who has
//  mastered one exercise should stop being handed it; someone who keeps tripping
//  the frustration guard on another is being given the wrong task, not failing
//  at it. The score below encodes those judgements explicitly so they can be
//  argued with, rather than burying them in an opaque ordering.
//
//  EVIDENCE OUTRANKS EVERYTHING ELSE.
//  `EvidenceTier.planWeight` is the first multiplier for a reason: when two
//  exercises are otherwise equally due, the one with better published support
//  wins. That is a deliberate bias, and it is the one place where the research
//  tiering changes behaviour rather than just labelling a card.
//
//  docs/06-AI-ENGINE-SPEC.md section 3.
//

import Foundation

struct SessionPlan: Sendable, Equatable {
    struct Item: Sendable, Equatable {
        let exerciseID: String
        let seconds: Int
    }

    let items: [Item]
    let totalSeconds: Int

    /// Why this plan looks the way it does, in one plain sentence for the
    /// Today screen. Never a claim about outcomes.
    let rationale: String

    var isEmpty: Bool { items.isEmpty }
}

struct PlanGenerator: Sendable {

    struct ExerciseState: Sendable {
        let descriptor: ExerciseDescriptor
        /// Days since this exercise was last practised. Nil if never.
        let daysSinceLastPractised: Int?
        /// From the persisted staircase.
        let isMastered: Bool
        let frustrationEvents: Int
        /// True once its threshold has enough evidence to trend.
        let hasReliableThreshold: Bool
    }

    let now: Date
    init(now: Date = .now) { self.now = now }

    // MARK: Scoring

    /// Higher is more due. Every term is documented because every term is a
    /// judgement call that someone should be able to disagree with.
    func score(_ state: ExerciseState) -> Double {
        var score = state.descriptor.evidenceTier.planWeight

        // Novelty: never practised gets a strong push, so a new user meets the
        // whole library rather than repeating the first thing they were shown.
        switch state.daysSinceLastPractised {
        case nil:
            score *= 2.0
        case .some(let days) where days == 0:
            // Already done today. Not forbidden - some people want a second
            // session - but it goes to the back.
            score *= 0.15
        case .some(let days):
            // Rises with neglect, saturating at a week: after seven days
            // "overdue" stops being a useful signal and everything is overdue.
            score *= 1.0 + min(Double(days), 7.0) / 7.0
        }

        // Mastered exercises are retired rather than removed - occasionally
        // revisiting confirms the gain held, and a library that shrinks as you
        // improve feels like a punishment.
        if state.isMastered { score *= 0.25 }

        // Repeated frustration means the exercise is mismatched to this person
        // right now. Back off rather than insisting.
        if state.frustrationEvents >= 2 { score *= 0.4 }

        // An exercise close to producing its first reliable threshold is worth
        // finishing - a half-measured exercise contributes nothing to the
        // progress view, so switching away wastes the trials already spent.
        if !state.hasReliableThreshold && state.daysSinceLastPractised != nil {
            score *= 1.3
        }

        return score
    }

    // MARK: Plan

    /// Builds a session from the highest-scoring exercises, respecting the cap.
    ///
    /// Two to three exercises rather than one: a single task for twenty minutes
    /// is where adherence dies, and perceptual learning is famously
    /// task-specific, so variety buys transfer as well as tolerance.
    func plan(states: [ExerciseState], cap: SessionCap,
              requestedSeconds: Int) -> SessionPlan {

        let available = cap.allowedSessionSeconds(requested: requestedSeconds)
        guard available > 0, !states.isEmpty else {
            return SessionPlan(items: [], totalSeconds: 0,
                               rationale: cap.isDailyCapReached
                                 ? "You've done today's practice."
                                 : "Nothing to practise yet.")
        }

        // A NAMED STRUCT, NOT A TUPLE — and it fixes two compiler errors at once.
        //
        // This was `(state:, score:)`. Swift cannot form a key path into a
        // tuple, so `chosen.map(\.state)` failed with "cannot infer key path
        // type from context"; and the tie-breaking sort closure over tuples was
        // enough to make the type checker give up entirely with "unable to
        // type-check this expression in reasonable time". Both go away with a
        // real type, and the code reads better besides.
        struct Ranked {
            let state: ExerciseState
            let score: Double
        }

        let scored = states.map { Ranked(state: $0, score: score($0)) }

        // Tie-break on id so the plan is stable between launches rather than
        // reshuffling whenever two scores are equal. Split out of the sort
        // closure so each comparison is a simple expression.
        let ranked = scored.sorted { first, second in
            if first.score != second.score { return first.score > second.score }
            return first.state.descriptor.id < second.state.descriptor.id
        }

        let targetCount = min(ranked.count, available >= 15 * 60 ? 3 : 2)
        let chosen = Array(ranked.prefix(targetCount))
        guard !chosen.isEmpty else {
            return SessionPlan(items: [], totalSeconds: 0, rationale: "Nothing to practise yet.")
        }

        // Split the budget evenly, then give any remainder to the first item so
        // the total lands exactly on the cap rather than a second under it.
        let each = available / chosen.count
        let remainder = available - each * chosen.count
        var items: [SessionPlan.Item] = []
        for (index, entry) in chosen.enumerated() {
            let seconds = index == 0 ? each + remainder : each
            items.append(SessionPlan.Item(exerciseID: entry.state.descriptor.id,
                                          seconds: seconds))
        }

        let total = items.reduce(0) { $0 + $1.seconds }
        let chosenStates = chosen.map { $0.state }

        return SessionPlan(items: items,
                           totalSeconds: total,
                           rationale: rationale(for: chosenStates))
    }

    private func rationale(for states: [ExerciseState]) -> String {
        if states.allSatisfy({ $0.daysSinceLastPractised == nil }) {
            return "Starting with the exercises that have the strongest research behind them."
        }
        if let neglected = states.first(where: { ($0.daysSinceLastPractised ?? 0) >= 4 }) {
            return "Picking up \(neglected.descriptor.title), which you haven't done in a few days."
        }
        if states.contains(where: { $0.frustrationEvents >= 2 }) {
            return "Easing off the harder ones today."
        }
        return "A mix, so no single skill takes the whole session."
    }
}
