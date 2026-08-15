//
//  AssessmentRunner.swift
//
//  Drives the four-part check-in and writes one `AssessmentResult`.
//
//  WHY THIS IS NOT `SessionRunner`
//  They look similar and their contracts are opposites. `SessionRunner` exists to
//  make a training session pleasant and safe: it offers breaks, honours the
//  fatigue button, ends early without penalty, and treats the threshold as a
//  by-product. This runner exists to produce a number, so it has a fixed trial
//  budget per sub-test, runs every sub-test in a stated order, and hands each
//  threshold to `AssessmentBattery.reportableThreshold` — which returns nil
//  rather than a value it does not trust.
//
//  Sharing one type between the two would mean every future change to session
//  comfort silently changing what the measurement means.
//
//  THE FATIGUE BUTTON STILL WORKS, AND IT ABANDONS RATHER THAN TRUNCATES
//  Someone whose eyes hurt must be able to stop. But a half-finished battery is
//  not a shorter battery — it is an unmeasured one, so stopping discards the
//  sub-tests that did not finish rather than writing whatever they had reached.
//  A partial record on the Progress chart would be indistinguishable from a real
//  one a month later.
//
//  docs/06-AI-ENGINE-SPEC.md, docs/03-EXERCISE-CATALOG.md assessment battery.
//

import Foundation
import Observation

@Observable
@MainActor
final class AssessmentRunner {

    enum Phase: Equatable {
        case ready
        /// Running a sub-test. `index` is into `plan`.
        case running(index: Int)
        /// Between sub-tests, so the user can rest and read what is next.
        case betweenTests(nextIndex: Int)
        case finished(AssessmentResult)
        case abandoned
    }

    private(set) var phase: Phase = .ready
    private(set) var currentTrial: Trial?
    /// Trials completed in the CURRENT sub-test.
    private(set) var trialsInSubtest = 0

    /// Sub-tests this run will attempt, in order.
    let plan: [AssessmentTest]

    private let profile: Profile
    private let calibration: CalibrationProfile
    private var generator: SeededGenerator
    private var staircase: Staircase?
    private var exercise: (any Exercise)?

    /// Thresholds accepted so far. A sub-test that did not earn a number is
    /// simply absent, which is how the result records "not measured".
    private var results: [AssessmentTest: Double] = [:]
    private var stereoNotDetected = false
    private var acuityFellowEye: Double?
    private var contrastByFrequency: [Double] = []
    private let startedAt = Date()

    /// Acuity runs twice. This tracks which eye the current acuity block is for.
    private var measuringFellowEye = false

    /// Whether the fellow-eye acuity block has RUN — which is not the same as
    /// whether it produced a number, and conflating the two hung the battery.
    /// See `finishSubtest`.
    private var fellowEyeBlockFinished = false

    init(profile: Profile, calibration: CalibrationProfile, isPro: Bool,
         seed: UInt64 = UInt64.random(in: 0..<UInt64.max)) {
        self.profile = profile
        self.calibration = calibration
        self.generator = SeededGenerator(seed: seed)
        var tests = AssessmentBattery.availableTests(isPro: isPro)
        // A profile that cannot use the glasses cannot do the binocular
        // sub-tests. Offering them anyway would produce two numbers measured
        // through no separation at all, which is worse than two missing ones.
        if !profile.canUseDichopticTrack {
            tests = tests.filter { !AssessmentBattery.requiresGlasses($0) }
        }
        self.plan = tests
    }

    // MARK: Running

    func start() {
        guard !plan.isEmpty else {
            phase = .abandoned
            return
        }
        begin(index: 0)
    }

    /// The eye the current sub-test trains, for the UI's "cover your other eye"
    /// instruction. Binocular tests use both.
    var currentEye: Eye {
        guard case .running(let index) = phase, index < plan.count else { return .unknown }
        switch plan[index] {
        case .acuity, .contrast:
            return measuringFellowEye ? profile.fellowEye : profile.amblyopicEye
        case .balance, .stereo:
            return .unknown          // both eyes
        }
    }

    /// The renderer for the current sub-test's stimulus, or nil where the
    /// borrowed exercise draws itself live rather than producing an image.
    ///
    /// Acuity and contrast rasterise a stimulus, so they bridge straight across
    /// from their training presenters and the check-in shows exactly what the
    /// training screen shows. Balance and stereo are ANIMATED anaglyph canvases
    /// — a moving dot field and a random-dot stereogram — which are drawn frame
    /// by frame rather than rendered to an image, so they cannot be bridged the
    /// same way and are not pretended to be.
    ///
    /// Nil is handled visibly by the screen. It is not a silent blank.
    var currentPresenter: AssessmentPresenter? {
        switch currentTest {
        case .acuity:   BridgedAssessmentPresenter(wrapped: LandoltPresenter())
        case .contrast: BridgedAssessmentPresenter(wrapped: ContrastHuntPresenter())
        case .balance, .stereo, .none: nil
        }
    }

    /// How many answer buttons the current trial needs.
    ///
    /// Asks the EXERCISE rather than reading `staircase.alternatives`, because
    /// those two numbers differ for the exercises whose option count grows with
    /// difficulty. None of the four sub-tests borrows one of those today, and
    /// hard-coding that assumption into the screen is how it would break the
    /// first time the battery borrowed a different exercise.
    var currentOptionCount: Int {
        guard let exercise, let currentTrial else { return 2 }
        return Swift.max(2, exercise.optionCount(for: currentTrial))
    }

    var currentTest: AssessmentTest? {
        guard case .running(let index) = phase, index < plan.count else { return nil }
        return plan[index]
    }

    func respond(answer: Int) {
        guard case .running(let index) = phase,
              let trial = currentTrial, var staircase else { return }

        staircase.record(correct: answer == trial.correctAnswer)
        self.staircase = staircase
        trialsInSubtest += 1

        let budget = plan[index] == .acuity
            ? AssessmentBattery.trialsPerSubtest
            : AssessmentBattery.trialsPerSubtest
        if trialsInSubtest >= budget {
            finishSubtest(index: index)
        } else {
            currentTrial = nextTrial()
        }
    }

    /// Stops the whole battery. Everything unfinished is discarded, deliberately.
    func abandon() {
        phase = .abandoned
        currentTrial = nil
    }

    // MARK: Sub-test lifecycle

    private func begin(index: Int) {
        guard index < plan.count else {
            finish()
            return
        }
        let test = plan[index]
        let id = AssessmentBattery.exerciseID(for: test)
        guard let made = ExerciseRegistry.make(id),
              let descriptor = ExerciseRegistry.descriptor(for: id) else {
            // An unregistered sub-test is a programming error, not a user
            // problem: skip it rather than stranding the battery.
            begin(index: index + 1)
            return
        }
        exercise = made
        staircase = Staircase(
            start: descriptor.staircase.startValue,
            hardestValue: descriptor.staircase.resolvedHardestValue(for: calibration),
            easiestValue: descriptor.staircase.easiestValue,
            polarity: descriptor.staircase.polarity,
            initialStepSize: descriptor.staircase.initialStepSize,
            minimumStepSize: descriptor.staircase.minimumStepSize)
        trialsInSubtest = 0
        phase = .running(index: index)
        currentTrial = nextTrial()
    }

    private func nextTrial() -> Trial? {
        guard let exercise, let staircase else { return nil }
        return exercise.makeTrial(difficulty: staircase.value, generator: &generator)
    }

    private func finishSubtest(index: Int) {
        let test = plan[index]
        let accepted = AssessmentBattery.reportableThreshold(
            estimate: staircase?.threshold,
            reversals: staircase?.reversals.count ?? 0,
            trialsRun: trialsInSubtest)

        switch test {
        case .stereo:
            let descriptor = ExerciseRegistry.descriptor(
                for: AssessmentBattery.exerciseID(for: .stereo))
            let outcome = AssessmentBattery.stereoOutcome(
                estimate: staircase?.threshold,
                reversals: staircase?.reversals.count ?? 0,
                trialsRun: trialsInSubtest,
                easiestValue: descriptor?.staircase.easiestValue ?? 60)
            if let arcminutes = outcome.arcminutes { results[.stereo] = arcminutes }
            stereoNotDetected = outcome.notDetected

        case .acuity:
            if measuringFellowEye {
                acuityFellowEye = accepted
                measuringFellowEye = false
                fellowEyeBlockFinished = true
            } else if let accepted {
                results[.acuity] = accepted
            }

        case .contrast:
            // One threshold per spatial frequency. The battery runs a single
            // staircase and records it against the mid frequency rather than
            // pretending to four separate measurements — a four-frequency curve
            // needs four staircases and four times the trials, which does not
            // fit a six-minute check-in.
            if let accepted { contrastByFrequency = [accepted] }

        case .balance:
            if let accepted { results[.balance] = accepted }
        }

        // Acuity runs a second block for the fellow eye before moving on.
        //
        // THE CONDITION IS "HAS IT RUN", NOT "DID IT PRODUCE A NUMBER".
        // This read `acuityFellowEye == nil`, which hung the battery: a fellow
        // block whose threshold was not reportable — no reversals yet, or a run
        // too short to trust — leaves `acuityFellowEye` nil, so the same block
        // restarted, produced nothing again, and restarted forever. The user
        // would sit in an acuity sub-test that never ended.
        //
        // It is the same distinction the whole battery is built on: not
        // measuring something and measuring nothing are different facts. Every
        // OTHER place in this file gets that right, and the one place that
        // decided control flow from it got it wrong.
        if test == .acuity, !measuringFellowEye, !fellowEyeBlockFinished {
            measuringFellowEye = true
            begin(index: index)
            return
        }

        let next = index + 1
        if next < plan.count {
            phase = .betweenTests(nextIndex: next)
            currentTrial = nil
        } else {
            finish()
        }
    }

    func continueToNextTest() {
        guard case .betweenTests(let next) = phase else { return }
        begin(index: next)
    }

    private func finish() {
        currentTrial = nil
        let result = AssessmentResult(
            date: .now,
            acuityAmblyopic: results[.acuity],
            acuityFellow: acuityFellowEye,
            contrastThresholds: contrastByFrequency,
            binocularBalance: results[.balance],
            stereoArcmin: results[.stereo],
            stereoNotDetected: stereoNotDetected,
            durationSeconds: Int(Date().timeIntervalSince(startedAt)))
        phase = .finished(result)
    }
}
