//
//  SimulatedObserver.swift
//
//  A synthetic participant with a KNOWN threshold, used to prove the staircase
//  recovers it.
//
//  WHY THIS LIVES IN THE APP TARGET AND NOT IN TESTS
//  Two reasons. It is the only honest way to validate the adaptive engine
//  without recruiting people, so it needs to be as maintained as the engine
//  itself. And the plan generator will later use the same psychometric function
//  to predict how many trials an exercise needs before it can report anything,
//  which is a shipping behaviour, not a test fixture.
//
//  THE MODEL
//  A Weibull psychometric function with a guess floor and a lapse ceiling:
//
//      P(correct | x) = g + (1 - g - lambda) * (1 - exp(-(x/T)^beta))
//
//      g       guess rate, fixed by the task's alternative count (2AFC = 0.5)
//      lambda  lapse rate - attention slips that are independent of difficulty.
//              Real observers lapse on 1-4% of trials even at trivial levels.
//              Omitting it makes the simulation easier than a human and hides
//              exactly the failure mode a lapse causes: a spurious reversal at
//              high difficulty.
//      T       the threshold being recovered
//      beta    slope; 3.5 is typical for orientation and contrast tasks
//
//  RANDOMNESS IS SEEDED. A test that fails once a fortnight in CI teaches people
//  to re-run the job instead of reading it, which is worse than having no test.
//
//  docs/04-ARCHITECTURE.md section 7, docs/06-AI-ENGINE-SPEC.md section 2.
//

import Foundation

struct SimulatedObserver: Sendable {

    /// The true threshold, in the exercise dimension's own units.
    let threshold: Double

    /// Psychometric slope.
    let slope: Double

    /// Probability of a correct answer by chance alone. 1/alternatives.
    let guessRate: Double

    /// Probability of an error independent of difficulty.
    let lapseRate: Double

    let polarity: Staircase.Polarity

    init(
        threshold: Double,
        slope: Double = 3.5,
        alternatives: Int = 2,
        lapseRate: Double = 0.02,
        polarity: Staircase.Polarity = .lowerIsHarder
    ) {
        self.threshold = threshold
        self.slope = slope
        self.guessRate = 1.0 / Double(max(1, alternatives))
        self.lapseRate = lapseRate
        self.polarity = polarity
    }

    /// Probability this observer answers correctly at difficulty `value`.
    func probabilityCorrect(at value: Double) -> Double {
        guard value > 0, threshold > 0 else { return guessRate }

        // For a higher-is-harder dimension the ratio inverts: difficulty rises
        // with the value, so the observer's performance falls with it.
        let ratio = polarity == .lowerIsHarder
            ? value / threshold
            : threshold / value

        let psi = 1 - exp(-pow(ratio, slope))
        return guessRate + (1 - guessRate - lapseRate) * psi
    }

    /// The stimulus level at which this observer is correct `proportion` of the
    /// time. A 3-down/1-up staircase converges here with proportion = 0.794, so
    /// this - not `threshold` - is what the staircase should be compared against.
    /// Comparing against `threshold` itself builds a fixed few-percent error into
    /// every assertion and then tunes the tolerance to hide it.
    func level(forProportionCorrect proportion: Double) -> Double {
        let span = 1 - guessRate - lapseRate
        let psi = (proportion - guessRate) / span
        guard psi > 0, psi < 1 else { return threshold }

        let ratio = pow(-log(1 - psi), 1 / slope)
        return polarity == .lowerIsHarder ? threshold * ratio : threshold / ratio
    }

    /// Convergence point of a 3-down/1-up staircase: 0.5^(1/3).
    static let threeDownOneUpProportion = pow(0.5, 1.0 / 3.0)

    var convergenceLevel: Double {
        level(forProportionCorrect: Self.threeDownOneUpProportion)
    }

    /// One simulated response.
    func respond(at value: Double, using generator: inout some RandomNumberGenerator) -> Bool {
        Double.random(in: 0..<1, using: &generator) < probabilityCorrect(at: value)
    }
}

// MARK: - Running a whole simulated session

extension SimulatedObserver {

    struct SimulationResult: Sendable {
        let estimatedThreshold: Double?
        let trueConvergenceLevel: Double
        let trials: Int
        let reversals: Int
        let converged: Bool
        let frustrationEvents: Int

        /// Signed relative error. Positive means the staircase over-estimated
        /// (reported the task as easier than it is).
        var relativeError: Double? {
            guard let estimatedThreshold, trueConvergenceLevel > 0 else { return nil }
            return (estimatedThreshold - trueConvergenceLevel) / trueConvergenceLevel
        }
    }

    /// Runs a staircase against this observer until it converges or runs out of
    /// trials, and reports how close it got.
    func run(
        staircase: Staircase,
        maxTrials: Int = 260,
        using generator: inout some RandomNumberGenerator
    ) -> SimulationResult {
        var staircase = staircase
        var trials = 0

        while trials < maxTrials && !staircase.hasConverged {
            let correct = respond(at: staircase.value, using: &generator)
            staircase.record(correct: correct)
            trials += 1
        }

        return SimulationResult(
            estimatedThreshold: staircase.threshold,
            trueConvergenceLevel: convergenceLevel,
            trials: trials,
            reversals: staircase.reversals.count,
            converged: staircase.hasConverged,
            frustrationEvents: staircase.frustrationEvents
        )
    }
}
