//
//  SessionSafety.swift
//
//  BreakScheduler, SessionCap and FatigueMonitor. All three are pure value
//  types with no timers of their own: they are asked "given this much elapsed
//  time, what should happen?" and answer. That makes every rule in this file
//  testable without waiting twenty real minutes.
//
//  docs/04-ARCHITECTURE.md section 6, docs/14-REVIEW-COMPLAINTS-MATRIX.md R4.
//

import Foundation

// MARK: - Break scheduler

/// The 20-20-20 rule: every 20 minutes of screen work, look at something 20 feet
/// away for 20 seconds. It is the standard recommendation for sustained near
/// work, and this app deliberately asks for sustained near work.
///
/// Skippable for adults, NOT skippable for under-13 profiles. An adult ignoring
/// a break card is making an informed choice about their own eyes; a nine-year-old
/// tapping past it is not.
struct BreakScheduler: Equatable, Sendable {

    let intervalSeconds: Int
    let breakSeconds: Int
    let isSkippable: Bool

    private(set) var breaksTaken: Int = 0
    private(set) var secondsAtLastBreak: Int = 0

    init(ageGroup: AgeGroup) {
        self.intervalSeconds = SafetyLimits.breakIntervalSeconds
        self.breakSeconds = SafetyLimits.breakDurationSeconds
        self.isSkippable = ageGroup == .thirteenPlus
    }

    /// True when a break is owed at this elapsed time.
    func isBreakDue(atElapsedSeconds elapsed: Int) -> Bool {
        elapsed - secondsAtLastBreak >= intervalSeconds
    }

    func secondsUntilNextBreak(atElapsedSeconds elapsed: Int) -> Int {
        max(0, intervalSeconds - (elapsed - secondsAtLastBreak))
    }

    mutating func recordBreakTaken(atElapsedSeconds elapsed: Int) {
        breaksTaken += 1
        secondsAtLastBreak = elapsed
    }
}

// MARK: - Session cap

/// Two ceilings, and the tighter one always wins.
///
/// WHY A DAILY CAP AT ALL, when more practice sounds better: dose-response for
/// this kind of training flattens out well before the point where eye strain
/// and abandonment begin. A parent who lets a child do ninety minutes because
/// the app allowed it gets a child who refuses to open the app on day four. The
/// cap protects adherence as much as it protects eyes.
struct SessionCap: Equatable, Sendable {

    let ageGroup: AgeGroup

    /// Seconds already practised today, from the session history.
    let secondsUsedToday: Int

    /// Set when a parent has passed the gate and chosen to continue past the
    /// daily cap. Never bypasses the per-session ceiling.
    let dailyCapOverridden: Bool

    init(ageGroup: AgeGroup, secondsUsedToday: Int, dailyCapOverridden: Bool = false) {
        self.ageGroup = ageGroup
        self.secondsUsedToday = secondsUsedToday
        self.dailyCapOverridden = dailyCapOverridden
    }

    var dailyCapSeconds: Int { ageGroup.dailyCapSeconds }
    var perSessionCeilingSeconds: Int { SafetyLimits.maxSessionSeconds }

    /// Seconds left today. Zero means the cap is reached.
    var remainingTodaySeconds: Int {
        dailyCapOverridden
            ? perSessionCeilingSeconds
            : max(0, dailyCapSeconds - secondsUsedToday)
    }

    var isDailyCapReached: Bool { remainingTodaySeconds == 0 }

    /// How long a session may actually run, given what the plan asked for.
    /// The per-session ceiling is absolute and is NOT lifted by the parent
    /// override - a parent can allow a second session today, not a ninety-minute
    /// one.
    func allowedSessionSeconds(requested: Int) -> Int {
        min(requested, perSessionCeilingSeconds, max(0, remainingTodaySeconds))
    }

    /// Whether a parent gate could lift the current block. Only the daily cap is
    /// overridable, and only for profiles that have a parent gate at all.
    var isOverridable: Bool {
        isDailyCapReached && ageGroup.requiresParentGate && !dailyCapOverridden
    }
}

// MARK: - Fatigue

/// Backs the always-visible "My eyes feel tired" control.
///
/// THE RULE THAT MATTERS: tapping it ends the session. It does not ask "are you
/// sure?", it does not offer "take a short break and continue", and it never
/// congratulates the user for pushing on. The reference app's equivalent flow
/// nudges people back into the exercise, and that is the behaviour our review
/// matrix R4 exists to avoid. Someone reporting eye strain in a vision app is
/// giving us safety information, not asking for encouragement.
struct FatigueMonitor: Equatable, Sendable {

    enum Guidance: Equatable, Sendable {
        case rest
        case restAndConsiderProfessional

        var title: String {
            switch self {
            case .rest: "Let's stop there"
            case .restAndConsiderProfessional: "Let's stop, and worth mentioning"
            }
        }

        var message: String {
            switch self {
            case .rest:
                """
                Tired eyes are a signal to stop, not to push through. Look at \
                something far away for a minute, and come back tomorrow.
                """
            case .restAndConsiderProfessional:
                """
                That's a few sessions in a row ending this way. Please mention it \
                to your eye doctor before your next session - it's worth them \
                knowing.
                """
            }
        }
    }

    /// Consecutive recent sessions that ended with the fatigue button.
    let consecutiveFatigueEndings: Int

    /// Three in a row stops being "a long day" and starts being a pattern
    /// somebody qualified should hear about.
    static let escalationThreshold = 3

    var guidance: Guidance {
        consecutiveFatigueEndings + 1 >= Self.escalationThreshold
            ? .restAndConsiderProfessional
            : .rest
    }

    /// There is deliberately no `shouldOfferToContinue`. The absence is the
    /// feature; a future refactor adding one should have to delete this comment.
}
