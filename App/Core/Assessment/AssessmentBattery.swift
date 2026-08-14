//
//  AssessmentBattery.swift
//
//  The four-part check-in that produces every number on the Progress screen.
//
//  WHY THE BATTERY IS SEPARATE FROM THE EXERCISES IT REUSES
//  The sub-tests use the same stimulus generators and the same staircase as the
//  training exercises — a Landolt C is a Landolt C. What differs is the CONTRACT:
//
//    A training session is allowed to be pleasant. It can start easy, let a tired
//    user coast, and end early without consequence, because its purpose is
//    practice and its threshold is a by-product.
//
//    An assessment is a measurement. It has a fixed trial budget, runs to a
//    stated number of reversals, and refuses to report a number when it did not
//    get enough evidence. A measurement that quietly degrades into a guess when
//    the user is tired is worse than a missing measurement, because it goes on
//    the chart and gets compared to last month.
//
//  So this type owns the stopping rules, and `reportableThreshold` returns nil
//  rather than a number it does not trust.
//
//  ACUITY IS MEASURED PER EYE, WHICH IS THE POINT
//  The single most useful thing this battery produces is the GAP between the two
//  eyes, so the acuity sub-test runs twice — amblyopic eye, then fellow eye —
//  and both go in the record. A one-eye acuity number would be a fine training
//  score and useless as an outcome.
//
//  FREE TIER GETS BALANCE ONLY
//  `AssessmentTest.isFreeTier` already says so. The battery honours it rather
//  than re-deciding: one honest number free, the full set with a subscription.
//
//  docs/03-EXERCISE-CATALOG.md assessment battery, docs/06-AI-ENGINE-SPEC.md.
//

import Foundation

struct AssessmentBattery: Sendable {

    /// One sub-test, in the order they are run.
    ///
    /// Balance comes FIRST, deliberately. It is the free-tier test, it is the
    /// most defensible number the app produces, and it is the one most affected
    /// by fatigue — so it gets the freshest eyes. Acuity, which is the most
    /// robust, goes last.
    static let order: [AssessmentTest] = [.balance, .stereo, .contrast, .acuity]

    /// Trials per sub-test. Enough for the staircase to converge, few enough
    /// that the whole battery stays near the six minutes the catalogue promises.
    ///
    /// Acuity counts DOUBLE because it runs once per eye.
    static let trialsPerSubtest: Int = 24

    /// Reversals required before a threshold is reportable. Below this the
    /// estimate is dominated by where the staircase started rather than by the
    /// user, and `reportableThreshold` returns nil.
    static let requiredReversals: Int = 6

    /// A rough duration estimate, used only to set expectations on screen.
    static var estimatedSeconds: Int {
        // Five staircases (balance, stereo, contrast, acuity x2) at roughly
        // 3 seconds a trial.
        5 * trialsPerSubtest * 3
    }

    /// Which sub-tests this profile may run.
    static func availableTests(isPro: Bool) -> [AssessmentTest] {
        order.filter { isPro || $0.isFreeTier }
    }

    /// Whether a sub-test needs the anaglyph glasses. Balance and stereo are
    /// binocular by definition; the other two are not.
    static func requiresGlasses(_ test: AssessmentTest) -> Bool {
        test == .balance || test == .stereo
    }

    /// The exercise whose stimulus and staircase a sub-test borrows.
    ///
    /// Reusing the exercises rather than reimplementing them is what keeps an
    /// assessment score on the same scale as the training score for the same
    /// task. Two implementations of "Landolt C acuity" would drift apart, and
    /// the Progress screen would be comparing two different things.
    static func exerciseID(for test: AssessmentTest) -> String {
        switch test {
        case .acuity:   LandoltRingsExercise.descriptor.id
        case .contrast: ContrastHuntExercise.descriptor.id
        case .balance:  BalanceMeterExercise.descriptor.id
        case .stereo:   DepthPopExercise.descriptor.id
        }
    }

    /// A threshold the battery is willing to put on the chart, or nil.
    ///
    /// The refusal is the important half. A staircase that ran out of trials at
    /// its starting value has measured nothing, and returning that value would
    /// put a number on the Progress screen that describes the app's opening
    /// guess rather than the user.
    static func reportableThreshold(estimate: Double?, reversals: Int,
                                    trialsRun: Int) -> Double? {
        guard let estimate else { return nil }
        guard reversals >= requiredReversals else { return nil }
        guard trialsRun >= trialsPerSubtest / 2 else { return nil }
        return estimate
    }

    /// Stereo has an extra state the others do not: no measurable depth at all.
    ///
    /// That is a real and common finding in amblyopia, and it must be recorded
    /// as such rather than as a very large number — "600 arcmin" would sit on
    /// the chart looking like a measurement and would average into trends as if
    /// it were one.
    static func stereoOutcome(estimate: Double?, reversals: Int,
                              trialsRun: Int,
                              easiestValue: Double) -> (arcminutes: Double?, notDetected: Bool) {
        guard let value = reportableThreshold(estimate: estimate, reversals: reversals,
                                              trialsRun: trialsRun) else {
            // Ran out of evidence. Not the same as "no stereo": we simply did
            // not measure it, and saying otherwise would be a claim.
            return (nil, false)
        }
        // Sitting at the easiest setting after a full run means the coarsest
        // disparity the app can show was still not seen.
        if value >= easiestValue * 0.95 {
            return (nil, true)
        }
        return (value, false)
    }

    /// Plain-language summary for the end of the battery.
    ///
    /// Never a comparison to a norm, and never a direction of travel — the
    /// Progress screen's trend logic owns that, and it refuses to claim a
    /// direction until the confidence interval supports one.
    static func summary(for result: AssessmentResult) -> [String] {
        var lines: [String] = []
        if let balance = result.binocularBalance {
            lines.append(BalanceMeterExercise.interpretation(balanceRatio: balance))
        }
        if result.stereoNotDetected {
            lines.append("No clear depth from this test today")
        } else if let stereo = result.stereoArcmin {
            lines.append(DepthPopExercise.interpretation(disparityArcminutes: stereo))
        }
        if let gap = result.interocularAcuityGap {
            lines.append(gap < 0.1
                ? "Both eyes scored about the same on detail"
                : String(format: "About %.1f lines of difference between your eyes", gap * 10))
        }
        if lines.isEmpty {
            lines.append("Not enough answers to report a score this time")
        }
        return lines
    }
}
