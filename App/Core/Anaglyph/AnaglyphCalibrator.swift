//
//  AnaglyphCalibrator.swift
//
//  Measures the three things the dichoptic track needs from the user's actual
//  glasses and eyes: which lens covers which eye, how much each filter leaks,
//  and whether they can tell red from cyan at all.
//
//  THE COLOUR-VISION CHECK IS NOT A GATE, IT IS A ROUTE.
//  Roughly 8% of men have a colour vision deficiency. For some of them red-cyan
//  anaglyph will never separate cleanly, and no amount of calibration fixes it.
//  When the check fails, the dichoptic track is HIDDEN and the user is routed to
//  the monocular track — not shown a locked feature, and never told their eyes
//  are wrong. A greyed-out list of things you can never have is a worse
//  experience than a shorter list, and the framing matters for someone already
//  dealing with a visual difference.
//
//  docs/01-RESEARCH-BRIEF.md section 4, docs/05-DESIGN-SYSTEM.md section 8.
//

import Foundation

struct AnaglyphCalibrator: Sendable {

    // MARK: Filter assignment

    /// Which lens should cover the amblyopic eye.
    ///
    /// The RED lens goes over the amblyopic eye by default, and the reason is
    /// physical rather than arbitrary: a red filter passes roughly 30% of a white
    /// screen's luminance while cyan passes about 70%. Putting red over the weak
    /// eye would dim the eye that needs the most signal — so the convention here
    /// is that the amblyopic eye gets CYAN, and `.red` in
    /// `CalibrationProfile.anaglyphFilter` names the FELLOW eye's lens.
    ///
    /// That naming is confusing enough to be worth stating twice, so the enum
    /// case is interpreted through this one function everywhere.
    static func recommendedFilterForAmblyopicEye() -> AnaglyphFilter { .cyan }

    // MARK: Crosstalk measurement

    /// One step of the crosstalk measurement.
    ///
    /// The user looks at a patch that should be invisible to one eye and adjusts
    /// until it disappears. The value at which it vanishes IS the leak: if a
    /// patch drawn only in the red channel is still faintly visible through the
    /// cyan lens, the cyan lens is passing that much red.
    struct LeakProbe: Sendable {
        /// Which channel the probe patch is drawn in.
        let channel: Channel
        /// Current guess at the leak, 0...0.5. The user's slider.
        var leak: Double

        enum Channel: String, Sendable {
            /// Probe drawn in red; measures how much red the CYAN lens passes.
            case red
            /// Probe drawn in cyan; measures how much cyan the RED lens passes.
            case cyan
        }

        /// The patch luminance to draw, given the current leak estimate.
        ///
        /// A cancellation patch is drawn in the opposite channel at `leak`
        /// strength. When `leak` matches the true leakage the two cancel and the
        /// patch vanishes; too little and it shows as the probe colour, too much
        /// and it shows as the opposite. A null point is far easier to judge than
        /// a threshold, which is why the task is "make it disappear" rather than
        /// "say when you can see it".
        func patch() -> (red: Double, green: Double, blue: Double) {
            let mid = AnaglyphCompositor.layerMidpoint
            let amplitude = 0.35
            switch channel {
            case .red:
                return (mid + amplitude, mid - amplitude * leak, mid - amplitude * leak)
            case .cyan:
                return (mid - amplitude * leak, mid + amplitude, mid + amplitude)
            }
        }
    }

    /// Plausible leak values. Anything outside this is a mis-drag or the glasses
    /// are not on, and storing it would corrupt every dichoptic stimulus after.
    static let plausibleLeak: ClosedRange<Double> = 0...0.35

    static func isPlausible(_ leak: Double) -> Bool { plausibleLeak.contains(leak) }

    // MARK: Colour-vision check

    /// A single discrimination trial: two patches, one red-dominant and one
    /// cyan-dominant, and the user says which side is which.
    ///
    /// Deliberately NOT an Ishihara plate. Those are copyrighted, need precise
    /// printing calibration to be valid, and diagnose a condition — which this
    /// app must not claim to do. This asks only the question the app actually
    /// needs answered: can you tell these two screen colours apart well enough
    /// for anaglyph to work?
    struct DiscriminationTrial: Sendable {
        /// True when the red-dominant patch is on the left.
        let redIsOnLeft: Bool

        static func make(generator: inout SeededGenerator) -> DiscriminationTrial {
            DiscriminationTrial(redIsOnLeft: Bool.random(using: &generator))
        }

        func isCorrect(saidRedOnLeft: Bool) -> Bool { saidRedOnLeft == redIsOnLeft }
    }

    /// Trials in the check, and how many must be right.
    ///
    /// 6 of 8 with a 50% guess rate: the chance of passing by guessing is about
    /// 14%, low enough to be a useful screen without failing someone who blinked
    /// at the wrong moment. Set higher and normal users get excluded; lower and
    /// it screens nothing.
    static let discriminationTrialCount = 8
    static let discriminationPassMark = 6

    static func passed(correct: Int) -> Bool { correct >= discriminationPassMark }

    /// Probability of passing purely by guessing, for the record.
    static var falsePassRate: Double {
        // Binomial tail: P(X >= 6) with n = 8, p = 0.5.
        func choose(_ n: Int, _ k: Int) -> Double {
            var result = 1.0
            for index in 0..<k { result *= Double(n - index) / Double(index + 1) }
            return result
        }
        let total = pow(2.0, Double(discriminationTrialCount))
        var tail = 0.0
        for k in discriminationPassMark...discriminationTrialCount {
            tail += choose(discriminationTrialCount, k)
        }
        return tail / total
    }

    // MARK: Verdict

    struct Result: Sendable {
        let redLeakIntoCyan: Double
        let cyanLeakIntoRed: Double
        let colorVisionOK: Bool

        /// Worst of the two leaks — the one that limits separation.
        var worstLeak: Double { max(redLeakIntoCyan, cyanLeakIntoRed) }

        /// Above this, cancellation can no longer keep cross-modulation low
        /// enough for the stimuli to be trustworthy, and the user is asked to
        /// recalibrate or try a different pair of glasses rather than train on
        /// bad data.
        static let unusableLeak: Double = 0.25

        var isUsable: Bool { colorVisionOK && worstLeak < Self.unusableLeak }

        /// Cross-modulation the compositor will actually achieve with these
        /// numbers. The honest headline: how well the two eyes are separated.
        func crossModulation(amblyopicFilter: AnaglyphFilter,
                             fellowEyeContrast: Double) -> Double {
            AnaglyphCompositor(amblyopicFilter: amblyopicFilter,
                               fellowEyeContrast: fellowEyeContrast,
                               redLeakIntoCyan: redLeakIntoCyan,
                               cyanLeakIntoRed: cyanLeakIntoRed)
                .crossModulationIntoFellowEye()
        }
    }

    /// Applies a completed calibration to a profile.
    static func apply(_ result: Result, to calibration: CalibrationProfile,
                      now: Date = .now) {
        calibration.redLeakIntoCyan = result.redLeakIntoCyan
        calibration.cyanLeakIntoRed = result.cyanLeakIntoRed
        calibration.colorVisionOK = result.colorVisionOK
        calibration.anaglyphFilter = recommendedFilterForAmblyopicEye() == .cyan
            ? .cyan
            : .red
        // Only stamp the date when the calibration is actually usable, so
        // `isAnaglyphCalibrated` never reports true for a failed attempt.
        calibration.anaglyphCalibratedAt = result.isUsable ? now : nil
    }
}

// MARK: - Contrast rebalance ramp

/// The slow outer loop on top of every dichoptic exercise: as the user succeeds,
/// the fellow eye's contrast is raised toward parity.
///
/// This ramp IS the therapeutic variable in the contrast-rebalanced literature —
/// not the game score. It moves between sessions, not within them, because a
/// within-session ramp would confound it with the trial-by-trial staircase.
struct ContrastRebalanceRamp: Sendable {

    /// Raise by this much after a session completed comfortably.
    static let stepUp: Double = 0.05
    /// Drop by this much after a session the user struggled with. Larger than
    /// the step up: losing fusion is worse than progressing slowly, and the
    /// asymmetry means the ramp settles just below the user's limit.
    static let stepDown: Double = 0.10

    static let completionForStepUp: Double = 0.80
    static let completionForStepDown: Double = 0.50

    static let minimum: Double = 0.10
    static let maximum: Double = 1.00

    /// Next value, given how much of the session the user completed.
    static func next(from current: Double, completionRatio: Double) -> Double {
        let value: Double
        if completionRatio >= completionForStepUp {
            value = current + stepUp
        } else if completionRatio < completionForStepDown {
            value = current - stepDown
        } else {
            value = current
        }
        return min(max(value, minimum), maximum)
    }

    /// True once the fellow eye is at full contrast and fusion is holding — the
    /// goal state, and worth telling the user about.
    static func hasReachedParity(_ value: Double) -> Bool {
        value >= maximum - 1e-9
    }
}
