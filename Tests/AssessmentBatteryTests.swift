//
//  AssessmentBatteryTests.swift
//
//  The battery's job is to REFUSE to report numbers it did not earn. Every test
//  here is about that refusal, because the failure mode is silent: a staircase
//  that ran out of trials still has a current value, and putting that value on
//  the Progress chart would describe the app's opening guess rather than the
//  user — then get compared against next month's.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Assessment battery")
struct AssessmentBatteryTests {

    // MARK: Refusing to report

    @Test("a threshold with too few reversals is not reportable")
    func tooFewReversalsIsRefused() {
        for reversals in 0..<AssessmentBattery.requiredReversals {
            #expect(AssessmentBattery.reportableThreshold(
                estimate: 0.42, reversals: reversals,
                trialsRun: AssessmentBattery.trialsPerSubtest) == nil,
                    "\(reversals) reversals should not produce a number")
        }
        #expect(AssessmentBattery.reportableThreshold(
            estimate: 0.42, reversals: AssessmentBattery.requiredReversals,
            trialsRun: AssessmentBattery.trialsPerSubtest) == 0.42)
    }

    @Test("a threshold from a truncated run is not reportable")
    func tooFewTrialsIsRefused() {
        // Someone who stops after four trials has not been measured, however
        // many reversals those four happened to contain.
        #expect(AssessmentBattery.reportableThreshold(
            estimate: 0.42, reversals: 10, trialsRun: 4) == nil)
    }

    @Test("a missing estimate stays missing")
    func missingEstimateIsRefused() {
        #expect(AssessmentBattery.reportableThreshold(
            estimate: nil, reversals: 99, trialsRun: 99) == nil)
    }

    // MARK: Stereo's third state

    @Test("no measurable stereo is recorded as absent, not as a huge number")
    func stereoAbsenceIsItsOwnState() {
        // Recording "600 arcmin" would sit on the chart looking like a
        // measurement and would average into trends as if it were one. A real
        // and common finding in amblyopia deserves its own flag.
        let easiest = DepthPopExercise.descriptor.staircase.easiestValue
        let outcome = AssessmentBattery.stereoOutcome(
            estimate: easiest, reversals: 8,
            trialsRun: AssessmentBattery.trialsPerSubtest, easiestValue: easiest)
        #expect(outcome.notDetected)
        #expect(outcome.arcminutes == nil)
    }

    @Test("a measured stereo threshold is reported as a number")
    func stereoMeasurementIsReported() {
        let easiest = DepthPopExercise.descriptor.staircase.easiestValue
        let outcome = AssessmentBattery.stereoOutcome(
            estimate: 8, reversals: 8,
            trialsRun: AssessmentBattery.trialsPerSubtest, easiestValue: easiest)
        #expect(outcome.arcminutes == 8)
        #expect(!outcome.notDetected)
    }

    @Test("running out of evidence is NOT the same as no stereo")
    func insufficientEvidenceIsNotAbsence() {
        // The distinction that matters: "we did not measure it" must not be
        // recorded as "there is none", which would be a claim about the user.
        let easiest = DepthPopExercise.descriptor.staircase.easiestValue
        let outcome = AssessmentBattery.stereoOutcome(
            estimate: 30, reversals: 1, trialsRun: 3, easiestValue: easiest)
        #expect(outcome.arcminutes == nil)
        #expect(!outcome.notDetected,
                "an abandoned sub-test must not be logged as absent stereopsis")
    }

    // MARK: Ordering and scope

    @Test("balance runs first, on the freshest eyes")
    func balanceRunsFirst() {
        // It is the free-tier test, the most defensible number the app produces,
        // and the one most affected by fatigue.
        #expect(AssessmentBattery.order.first == .balance)
        #expect(AssessmentBattery.order.last == .acuity,
                "the most robust test should absorb the fatigue")
        #expect(Set(AssessmentBattery.order) == Set(AssessmentTest.allCases),
                "every sub-test must be in the running order")
    }

    @Test("the free tier gets exactly one sub-test, and it is balance")
    func freeTierScope() {
        let free = AssessmentBattery.availableTests(isPro: false)
        #expect(free == [.balance])
        #expect(AssessmentBattery.availableTests(isPro: true).count
                == AssessmentTest.allCases.count)
    }

    @Test("the binocular sub-tests are the ones that need glasses")
    func glassesRequirementIsCorrect() {
        #expect(AssessmentBattery.requiresGlasses(.balance))
        #expect(AssessmentBattery.requiresGlasses(.stereo))
        #expect(!AssessmentBattery.requiresGlasses(.acuity))
        #expect(!AssessmentBattery.requiresGlasses(.contrast))
    }

    @Test("each sub-test borrows a real, registered exercise")
    func subtestsMapToRegisteredExercises() {
        // Reimplementing a Landolt C for assessment would drift from the
        // training version, and the Progress screen would compare two different
        // measurements while calling them one.
        for test in AssessmentTest.allCases {
            let id = AssessmentBattery.exerciseID(for: test)
            #expect(ExerciseRegistry.descriptor(for: id) != nil,
                    "\(test) borrows \(id), which is not registered")
            #expect(ExerciseRegistry.make(id) != nil)
        }
    }

    @Test("the battery is near the six minutes the catalogue promises")
    func durationIsHonest() {
        let minutes = Double(AssessmentBattery.estimatedSeconds) / 60
        #expect(minutes >= 4 && minutes <= 8,
                "estimated at \(minutes) minutes, which is not the ~6 promised")
    }

    // MARK: Summaries

    @Test("a summary never claims a direction or a norm")
    func summaryStaysHonest() {
        let result = AssessmentResult(binocularBalance: 0.8, stereoArcmin: 6)
        let lines = AssessmentBattery.summary(for: result)
        #expect(!lines.isEmpty)
        for line in lines {
            let lowered = line.lowercased()
            for phrase in ["normal", "improv", "better than", "worse than",
                           "diagnos", "healthy", "average"] {
                #expect(!lowered.contains(phrase),
                        "\"\(phrase)\" in \"\(line)\" — the trend logic owns direction claims")
            }
        }
    }

    @Test("an empty result says so rather than inventing a line")
    func emptyResultIsStated() {
        let lines = AssessmentBattery.summary(for: AssessmentResult())
        #expect(lines.count == 1)
        #expect(lines[0].lowercased().contains("not enough"))
    }

    @Test("absent stereo is described in the summary")
    func absentStereoIsDescribed() {
        let result = AssessmentResult(binocularBalance: 0.5, stereoNotDetected: true)
        let lines = AssessmentBattery.summary(for: result)
        #expect(lines.contains { $0.lowercased().contains("no clear depth") })
    }

    @Test("the acuity gap is what the summary leads with when both eyes ran")
    func acuityGapIsSummarised() {
        let close = AssessmentResult(acuityAmblyopic: 0.32, acuityFellow: 0.30)
        #expect(AssessmentBattery.summary(for: close)
            .contains { $0.lowercased().contains("about the same") })

        let wide = AssessmentResult(acuityAmblyopic: 0.60, acuityFellow: 0.20)
        #expect(AssessmentBattery.summary(for: wide)
            .contains { $0.contains("lines of difference") })
    }

    @Test("a result is only complete when every sub-test produced something")
    func completenessIsStrict() {
        var result = AssessmentResult(acuityAmblyopic: 0.3,
                                      contrastThresholds: [0.02, 0.03, 0.05, 0.09],
                                      binocularBalance: 0.7)
        #expect(!result.isComplete, "stereo has not reported yet")

        result = AssessmentResult(acuityAmblyopic: 0.3,
                                  contrastThresholds: [0.02, 0.03, 0.05, 0.09],
                                  binocularBalance: 0.7,
                                  stereoNotDetected: true)
        #expect(result.isComplete,
                "absent stereo is a result, not a missing one")
    }

    @Test("the contrast index rises as thresholds fall")
    func contrastIndexDirection() {
        // Sensitivity is the inverse of threshold, and the index has to move the
        // way a user expects "better" to move on a chart.
        let sensitive = AssessmentResult(contrastThresholds: [0.01, 0.02, 0.03, 0.05])
        let less = AssessmentResult(contrastThresholds: [0.10, 0.20, 0.30, 0.50])
        let a = sensitive.contrastSensitivityIndex ?? 0
        let b = less.contrastSensitivityIndex ?? 0
        #expect(a > b, "index \(a) vs \(b): lower thresholds must score higher")
    }
}
