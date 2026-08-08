//
//  SafetyTests.swift
//
//  100% coverage target — docs/04-ARCHITECTURE.md section 7.
//
//  The FlickerGuard suite iterates the WHOLE REGISTRY rather than a fixed list,
//  so every exercise added in Phases 6-8 is audited automatically the moment it
//  is registered. An exercise cannot be forgotten by the thing that checks it is
//  safe, which is the only design that survives 32 exercises written over weeks.
//

import Testing
import Foundation
@testable import Amblyo

// MARK: - Flicker

@Suite("FlickerGuard")
struct FlickerGuardTests {

    @Test("Every registered exercise passes the photosensitivity audit")
    func registryIsSafe() {
        let violations = FlickerGuard.audit(ExerciseRegistry.all)
        #expect(violations.isEmpty,
                "unsafe exercises: \(violations.map(\.description).joined(separator: "; "))")
    }

    @Test("The registry is not empty")
    func registryPopulated() {
        // Guards against the audit above passing vacuously if the registry is
        // ever emptied by a refactor.
        #expect(!ExerciseRegistry.all.isEmpty)
    }

    @Test("Exercise identifiers are unique")
    func identifiersUnique() {
        let ids = ExerciseRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate id would corrupt trial history")
    }

    @Test("Runtime clamp caps any rate at the ceiling")
    func rateIsClamped() {
        #expect(FlickerGuard.rate(1.5) == 1.5)
        #expect(FlickerGuard.rate(3.0) == 3.0)
        #expect(FlickerGuard.rate(-2) == 0, "negative rates are nonsense, not slow")
    }

    @Test("Period clamp enforces the same ceiling from the other direction")
    func periodIsClamped() {
        let minimum = 1.0 / FlickerGuard.maxTemporalRateHz
        #expect(FlickerGuard.period(0.001) == minimum)
        #expect(FlickerGuard.period(2.0) == 2.0)
    }

    // The audit must actually catch things. A guard that never fires is
    // indistinguishable from one that is broken.

    @Test("A too-fast exercise is rejected")
    func catchesFastFlicker() {
        let bad = descriptor(with: SafetyEnvelope(
            maxTemporalRateHz: 12,
            invertsFullFieldLuminance: false,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.1))
        #expect(FlickerGuard.audit(bad).contains(.rateTooHigh(exerciseID: "test", declared: 12)))
    }

    @Test("A full-field inversion is rejected")
    func catchesFullFieldInversion() {
        let bad = descriptor(with: SafetyEnvelope(
            maxTemporalRateHz: 1,
            invertsFullFieldLuminance: true,
            maxContrast: 0.9,
            maxHighContrastAreaFraction: 0.1))
        #expect(FlickerGuard.audit(bad).contains(.fullFieldInversion(exerciseID: "test")))
    }

    @Test("A large high-contrast area is rejected")
    func catchesLargeHighContrastArea() {
        let bad = descriptor(with: SafetyEnvelope(
            maxTemporalRateHz: 1,
            invertsFullFieldLuminance: false,
            maxContrast: 0.95,
            maxHighContrastAreaFraction: 0.9))
        #expect(!FlickerGuard.audit(bad).isEmpty)
    }

    @Test("A large LOW-contrast area is fine")
    func allowsLargeLowContrastArea() {
        // The area rule exists to bound high-contrast flashing. A big, faint
        // field is not the risk, and rejecting it would rule out the dot-field
        // exercises for no safety benefit.
        let fine = descriptor(with: SafetyEnvelope(
            maxTemporalRateHz: 1,
            invertsFullFieldLuminance: false,
            maxContrast: 0.2,
            maxHighContrastAreaFraction: 0.9))
        #expect(FlickerGuard.audit(fine).isEmpty)
    }

    private func descriptor(with safety: SafetyEnvelope) -> ExerciseDescriptor {
        ExerciseDescriptor(
            id: "test", title: "Test", track: .monocular, evidenceTier: .c,
            summary: "", targets: "",
            staircase: StaircaseConfiguration(
                dimensionName: "x", startValue: 10, hardestValue: 1,
                easiestValue: 20, polarity: .lowerIsHarder, alternatives: 2),
            safety: safety)
    }
}

// MARK: - Breaks

@Suite("BreakScheduler")
struct BreakSchedulerTests {

    @Test("A break falls due at 20 minutes and not before")
    func breakTiming() {
        let scheduler = BreakScheduler(ageGroup: .thirteenPlus)
        #expect(!scheduler.isBreakDue(atElapsedSeconds: 1_199))
        #expect(scheduler.isBreakDue(atElapsedSeconds: 1_200))
    }

    @Test("The next break is measured from the last one, not from zero")
    func breakIntervalRestarts() {
        var scheduler = BreakScheduler(ageGroup: .thirteenPlus)
        scheduler.recordBreakTaken(atElapsedSeconds: 1_200)
        #expect(!scheduler.isBreakDue(atElapsedSeconds: 1_800))
        #expect(scheduler.isBreakDue(atElapsedSeconds: 2_400))
        #expect(scheduler.breaksTaken == 1)
    }

    @Test("Children cannot skip the break; adults can")
    func skippability() {
        #expect(BreakScheduler(ageGroup: .thirteenPlus).isSkippable)
        #expect(!BreakScheduler(ageGroup: .fiveToTwelve).isSkippable)
        #expect(!BreakScheduler(ageGroup: .underFive).isSkippable)
    }
}

// MARK: - Caps

@Suite("SessionCap")
struct SessionCapTests {

    @Test("The daily cap is enforced per age group")
    func dailyCap() {
        let child = SessionCap(ageGroup: .fiveToTwelve, secondsUsedToday: 20 * 60)
        #expect(child.isDailyCapReached)
        #expect(child.allowedSessionSeconds(requested: 600) == 0)

        let adult = SessionCap(ageGroup: .thirteenPlus, secondsUsedToday: 20 * 60)
        #expect(!adult.isDailyCapReached)
        #expect(adult.allowedSessionSeconds(requested: 600) == 600)
    }

    @Test("A session is truncated to what remains today")
    func truncatesToRemaining() {
        let cap = SessionCap(ageGroup: .fiveToTwelve, secondsUsedToday: 15 * 60)
        #expect(cap.allowedSessionSeconds(requested: 20 * 60) == 5 * 60)
    }

    @Test("The 30-minute per-session ceiling is absolute")
    func perSessionCeiling() {
        let cap = SessionCap(ageGroup: .thirteenPlus, secondsUsedToday: 0)
        #expect(cap.allowedSessionSeconds(requested: 90 * 60) == 30 * 60)
    }

    @Test("A parent override lifts the daily cap but NOT the session ceiling")
    func overrideIsBounded() {
        let cap = SessionCap(ageGroup: .fiveToTwelve,
                             secondsUsedToday: 60 * 60,
                             dailyCapOverridden: true)
        #expect(!cap.isDailyCapReached)
        #expect(cap.allowedSessionSeconds(requested: 90 * 60) == 30 * 60,
                "a parent may allow another session, not an endless one")
    }

    @Test("Only child profiles can override, and only once")
    func overridability() {
        #expect(SessionCap(ageGroup: .fiveToTwelve, secondsUsedToday: 20 * 60).isOverridable)
        #expect(!SessionCap(ageGroup: .thirteenPlus, secondsUsedToday: 20 * 60).isOverridable)
        #expect(!SessionCap(ageGroup: .fiveToTwelve, secondsUsedToday: 20 * 60,
                            dailyCapOverridden: true).isOverridable)
    }
}

// MARK: - Fatigue

@Suite("FatigueMonitor")
struct FatigueMonitorTests {

    @Test("One tired session gets rest guidance")
    func firstTime() {
        #expect(FatigueMonitor(consecutiveFatigueEndings: 0).guidance == .rest)
    }

    @Test("Three in a row escalates to a professional")
    func escalates() {
        #expect(FatigueMonitor(consecutiveFatigueEndings: 2).guidance
                == .restAndConsiderProfessional)
        #expect(FatigueMonitor(consecutiveFatigueEndings: 9).guidance
                == .restAndConsiderProfessional)
    }

    @Test("No guidance text ever encourages continuing")
    func neverEncouragesContinuing() {
        // docs/14-REVIEW-COMPLAINTS-MATRIX.md R4. The reference app's equivalent
        // flow nudges people back into the exercise; ours must not, and this
        // test is what stops a future copy edit reintroducing it.
        let banned = ["keep going", "push through", "carry on", "one more",
                      "continue", "almost there", "don't give up"]
        for endings in 0...4 {
            let text = (FatigueMonitor(consecutiveFatigueEndings: endings).guidance.title
                        + " " + FatigueMonitor(consecutiveFatigueEndings: endings).guidance.message)
                .lowercased()
            for phrase in banned {
                #expect(!text.contains(phrase), "fatigue guidance contains '\(phrase)'")
            }
        }
    }
}
