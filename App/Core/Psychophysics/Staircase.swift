//
//  Staircase.swift
//
//  THE CORRECTNESS CORE OF THE ENTIRE APP.
//
//  Every threshold this app reports, every "you improved" sentence, every plan
//  decision, traces back to this struct. If it is wrong, the app is a toy that
//  shows confident numbers derived from nothing - which is exactly what the
//  reference app is, and exactly what its reviews complain about.
//
//  METHOD: 3-down / 1-up transformed staircase.
//  Three consecutive correct answers make the task harder; one wrong answer makes
//  it easier. That asymmetry converges on the stimulus level where the observer
//  is correct 79.4% of the time (0.5^(1/3) = 0.794), which is a standard,
//  well-validated operating point requiring no training data and no model.
//
//  WHAT THE TUNING IS AND WHY (all values below were chosen by simulation, not
//  taste - see StaircaseTests, and the numbers quoted here are from 6,000
//  simulated runs against observers with known thresholds):
//
//    stepShrinkFactor 0.75, applied to the FIRST 4 REVERSALS ONLY.
//      A step that keeps shrinking on every reversal is the obvious design and
//      it is wrong: if the staircase is still far from threshold when the step
//      collapses, it can no longer travel and strands itself. In simulation that
//      produced worst-case errors above 300%. Freezing the step after 4
//      reversals cut the worst case to 33% and left the median unchanged.
//
//    16 reversals to converge, threshold = mean of the last 8, first 3 discarded.
//      The first reversals happen during the coarse descent from the start value
//      and carry no information about the threshold. Averaging an EVEN number of
//      reversals cancels the systematic up/down offset of the final oscillation.
//
//  MEASURED PERFORMANCE (6,000 runs, thresholds spanning 1.5-30 units):
//      bias (median signed error)   under 1.5%
//      median absolute error        ~7.5%
//      95th percentile              ~22%
//      convergence rate             100%, mean 77 trials
//  A single run being +-20% out is the psychophysics, not a defect. That is why
//  the app never shows a threshold from one session as a change - the progress
//  analyser fits a trend across sessions instead.
//
//  docs/06-AI-ENGINE-SPEC.md section 2, docs/04-ARCHITECTURE.md section 7.
//

import Foundation

struct Staircase: Equatable, Sendable, Codable {

    // MARK: Polarity
    //
    // Some dimensions get harder as the number falls (orientation difference,
    // contrast, motion coherence, disparity); some get harder as it rises (set
    // size, distractor count, speed). Getting this backwards produces a
    // staircase that runs confidently in the wrong direction and reports a
    // threshold, so it is a required parameter with no default.

    enum Polarity: String, Sendable, Codable {
        case lowerIsHarder
        case higherIsHarder
    }

    enum Direction: String, Sendable, Codable { case harder, easier }

    // MARK: Configuration

    /// Difficulty on this exercise's dimension, in that dimension's own units.
    private(set) var value: Double

    /// The hardest and easiest values the exercise will ever present. Named by
    /// DIFFICULTY, not by magnitude, because which numeric end is which depends
    /// on polarity - `hardestValue` may be numerically smaller or larger than
    /// `easiestValue`.
    let hardestValue: Double
    let easiestValue: Double

    let polarity: Polarity

    /// Multiplicative step. 0.5 means "divide or multiply by 1.5".
    /// Multiplicative rather than additive because perceptual dimensions are
    /// roughly logarithmic - a 1 degree step is enormous near 2 degrees and
    /// invisible near 40.
    private(set) var stepSize: Double
    let minimumStepSize: Double

    // MARK: State

    private var consecutiveCorrect = 0
    private var lastDirection: Direction?

    /// Values at which the staircase changed direction, in order.
    private(set) var reversals: [Double] = []

    /// Rolling window used by the anti-frustration guard.
    private var recentOutcomes: [Bool] = []

    private var trialsAtHardest = 0

    /// Incremented whenever the anti-frustration guard fires. Surfaced to the
    /// plan generator: a user hitting this repeatedly is being handed the wrong
    /// exercise, not failing at it.
    private(set) var frustrationEvents = 0

    /// True once the user has sat at maximum difficulty long enough that this
    /// exercise has nothing left to teach them.
    private(set) var isMastered = false

    private(set) var trialCount = 0

    // MARK: Tuning constants

    static let requiredCorrectForHarder = 3
    static let reversalsToConverge = 16
    static let reversalsDiscardedAsWarmup = 3
    static let reversalAveragingWindow = 8
    static let stepShrinkFactor = 0.75
    static let reversalsWithShrinkingStep = 4

    /// Anti-frustration: below this accuracy over the window, back off.
    static let frustrationAccuracyFloor = 0.40
    static let frustrationWindow = 12

    /// Anti-ceiling: this many trials pinned at maximum difficulty means mastered.
    static let trialsAtHardestForMastery = 20

    // MARK: Init

    init(
        start: Double,
        hardestValue: Double,
        easiestValue: Double,
        polarity: Polarity,
        initialStepSize: Double = 0.5,
        minimumStepSize: Double = 0.03
    ) {
        self.hardestValue = hardestValue
        self.easiestValue = easiestValue
        self.polarity = polarity
        self.stepSize = initialStepSize
        self.minimumStepSize = minimumStepSize
        self.value = Self.clamp(start,
                                hardest: hardestValue,
                                easiest: easiestValue,
                                polarity: polarity)
    }

    // MARK: Recording

    mutating func record(correct: Bool) {
        trialCount += 1

        recentOutcomes.append(correct)
        if recentOutcomes.count > Self.frustrationWindow {
            recentOutcomes.removeFirst(recentOutcomes.count - Self.frustrationWindow)
        }

        if correct {
            consecutiveCorrect += 1
            if consecutiveCorrect >= Self.requiredCorrectForHarder {
                consecutiveCorrect = 0
                step(.harder)
            }
        } else {
            consecutiveCorrect = 0
            step(.easier)
        }

        applyFrustrationGuard()
        updateMastery()
    }

    /// A trial that cannot be trusted - a dropped frame, a sub-150ms response,
    /// an interruption. It must not move the staircase, because a staircase fed
    /// noise reports a threshold for the noise.
    mutating func discardTrial() {
        trialCount += 1
    }

    // MARK: Stepping

    private mutating func step(_ direction: Direction) {
        if let last = lastDirection, last != direction {
            reversals.append(value)
            // Shrink only during the early descent. See the header.
            if reversals.count <= Self.reversalsWithShrinkingStep {
                stepSize = max(minimumStepSize, stepSize * Self.stepShrinkFactor)
            }
        }
        lastDirection = direction
        nudge(direction)
    }

    /// Moves `value` one step without touching reversal bookkeeping. Used by the
    /// frustration guard, which must not fake reversals - a reversal is evidence
    /// about the threshold, and a backed-off step is not.
    private mutating func nudge(_ direction: Direction) {
        let harder = direction == .harder
        let increase = (polarity == .higherIsHarder) == harder

        value = increase ? value * (1 + stepSize) : value / (1 + stepSize)
        value = Self.clamp(value, hardest: hardestValue,
                           easiest: easiestValue, polarity: polarity)
    }

    // MARK: Guards

    /// Children abandon apps at exactly the point where they stop getting
    /// anything right. Two steps easier, and the window is cleared so the guard
    /// cannot fire again on the same twelve answers.
    private mutating func applyFrustrationGuard() {
        guard recentOutcomes.count == Self.frustrationWindow else { return }
        let accuracy = Double(recentOutcomes.filter { $0 }.count)
            / Double(recentOutcomes.count)
        guard accuracy < Self.frustrationAccuracyFloor else { return }

        frustrationEvents += 1
        nudge(.easier)
        nudge(.easier)
        recentOutcomes.removeAll()
        consecutiveCorrect = 0
    }

    private mutating func updateMastery() {
        if abs(value - hardestValue) < 1e-9 {
            trialsAtHardest += 1
            if trialsAtHardest >= Self.trialsAtHardestForMastery { isMastered = true }
        } else {
            trialsAtHardest = 0
        }
    }

    // MARK: Results

    /// Estimated threshold, or nil while there is not yet enough evidence.
    ///
    /// Returning nil rather than a number is deliberate and load-bearing: every
    /// caller is forced to handle "we do not know yet", which is how the app
    /// avoids showing a confident figure derived from four trials.
    ///
    /// NOTE ON `reversalsDiscardedAsWarmup`: once 12 or more reversals have
    /// accumulated, dropping the first 3 and then taking the last 8 selects the
    /// SAME slice as taking the last 8 outright - so on a converged session the
    /// warmup discard changes nothing. It earns its place only on sessions that
    /// end early, at 4 to 10 reversals, where the coarse-descent reversals are
    /// still inside the averaging window and would drag the estimate toward the
    /// start value. That is the common case for a user who runs out of time, and
    /// it is covered by a dedicated test rather than by the simulation, which
    /// only ever measures converged runs.
    var threshold: Double? {
        let usable = reversals.dropFirst(Self.reversalsDiscardedAsWarmup)
        guard usable.count >= 4 else { return nil }

        var window = Array(usable.suffix(Self.reversalAveragingWindow))
        // An odd count biases the estimate toward whichever direction the final
        // reversal happened to be.
        if window.count % 2 == 1 { window.removeFirst() }

        // The guard above makes this unreachable (the smallest possible window
        // is 4). Stated anyway, because an empty average is a NaN threshold that
        // would propagate silently into a trend line.
        guard !window.isEmpty else { return nil }

        return window.reduce(0, +) / Double(window.count)
    }

    var hasConverged: Bool { reversals.count >= Self.reversalsToConverge }

    /// 0...1, for the session progress indicator.
    var convergenceProgress: Double {
        min(1, Double(reversals.count) / Double(Self.reversalsToConverge))
    }

    var recentAccuracy: Double? {
        guard !recentOutcomes.isEmpty else { return nil }
        return Double(recentOutcomes.filter { $0 }.count) / Double(recentOutcomes.count)
    }

    // MARK: Clamping

    /// Clamps between the two bounds without assuming which one is numerically
    /// larger - that depends on polarity, and hard-coding min/max here was the
    /// obvious bug this helper exists to prevent.
    private static func clamp(_ value: Double, hardest: Double,
                              easiest: Double, polarity: Polarity) -> Double {
        let low = Swift.min(hardest, easiest)
        let high = Swift.max(hardest, easiest)
        return Swift.min(Swift.max(value, low), high)
    }
}

// MARK: - Persistence
//
// One staircase per (profile, exercise, eye), carried across sessions so a
// returning user resumes at their actual ability rather than at level 1. The
// reference app restarts everyone at the beginning every time, which is why its
// reviews say it "never gets harder".

extension Staircase {

    struct Key: Hashable, Sendable, Codable {
        let profileID: UUID
        let exerciseID: String
        let eye: Eye
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }

    static func decoded(from data: Data) -> Staircase? {
        try? JSONDecoder().decode(Staircase.self, from: data)
    }
}
