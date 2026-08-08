//
//  SessionRunner.swift
//
//  Owns one training session from start to summary: the trial loop, the clock,
//  the staircase, the safety guards, and persistence.
//
//  WHY THIS IS ONE OBJECT AND NOT SPREAD ACROSS VIEWS
//  A session has to survive the app being backgrounded, a phone call, a break
//  card, a fatigue tap and a daily cap - and every one of those has to produce a
//  correctly-labelled SessionRecord. Scatter that across view state and you get
//  sessions that silently record zero trials, or record trials twice. One
//  @Observable @MainActor object with an explicit state machine is the smallest
//  thing that can be reasoned about.
//
//  THE INVARIANT WORTH KNOWING
//  A trial only reaches the staircase if it is VALID. Dropped frames,
//  impossibly-fast taps and interruptions are recorded for honesty but do not
//  move the difficulty. A staircase fed invalid trials reports a threshold for
//  the noise, and the app then draws a confident trend line through it.
//
//  docs/04-ARCHITECTURE.md sections 5 and 6, docs/06-AI-ENGINE-SPEC.md section 2.
//

import Foundation
import Observation
import SwiftData
import os

@MainActor
@Observable
final class SessionRunner {

    // MARK: State machine

    enum Phase: Equatable {
        /// Pre-flight: glasses prompt, cap check, instructions.
        case ready
        /// A trial is on screen awaiting a response.
        case presenting
        /// Brief feedback between trials.
        case feedback(correct: Bool)
        /// 20-20-20 break card.
        case onBreak(secondsRemaining: Int)
        /// Backgrounded or interrupted; the clock is stopped.
        case paused
        /// Terminal.
        case finished(EndReason)

        var isTerminal: Bool { if case .finished = self { true } else { false } }
        var acceptsResponses: Bool { self == .presenting }
    }

    private(set) var phase: Phase = .ready
    private(set) var currentTrial: Trial?
    private(set) var staircase: Staircase
    private(set) var elapsedSeconds: Int = 0

    /// Trials that actually moved the staircase.
    private(set) var validTrialCount = 0
    private(set) var correctCount = 0
    private(set) var discardedCount = 0

    // MARK: Configuration

    let descriptor: ExerciseDescriptor
    let profileID: UUID
    let targetEye: Eye
    private let exercise: any Exercise
    private let plannedSeconds: Int

    private var breaks: BreakScheduler
    private let cap: SessionCap

    // MARK: Collaborators

    private let context: ModelContext
    private var generator: SeededGenerator
    private var record: SessionRecord?
    private var trialShownAt: Date?
    private var clock: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.amblyo.app", category: "session")

    // MARK: Init

    init?(
        descriptor: ExerciseDescriptor,
        profile: Profile,
        targetEye: Eye,
        context: ModelContext,
        cap: SessionCap,
        resuming staircase: Staircase? = nil,
        seed: UInt64 = UInt64.random(in: 0..<UInt64.max)
    ) {
        guard let exercise = ExerciseRegistry.make(descriptor.id) else {
            Self.log.error("No implementation registered for \(descriptor.id, privacy: .public)")
            return nil
        }
        self.descriptor = descriptor
        self.exercise = exercise
        self.profileID = profile.id
        self.targetEye = targetEye
        self.context = context
        self.cap = cap
        self.breaks = BreakScheduler(ageGroup: profile.ageGroup)
        self.generator = SeededGenerator(seed: seed)

        // Resume the user's actual ability if we have it. First exposure starts
        // from the descriptor's default, eased for younger profiles.
        //
        // The calibration is passed in so the staircase cannot descend below
        // what THIS screen at THIS distance can physically draw. Without it a
        // staircase happily walks past the display's limit and starts measuring
        // the pixels instead of the person. See StaircaseConfiguration.
        self.staircase = staircase
            ?? descriptor.staircase.makeStaircase(ageGroup: profile.ageGroup,
                                                  calibration: profile.calibration)

        self.plannedSeconds = cap.allowedSessionSeconds(
            requested: min(profile.plannedSessionSeconds,
                           descriptor.defaultDurationSeconds)
        )
    }

    // MARK: Lifecycle

    func start() {
        guard phase == .ready else { return }
        guard plannedSeconds > 0 else {
            // The cap is reached. Finishing immediately with `.cap` is honest;
            // starting a zero-length session would log a phantom record.
            phase = .finished(.cap)
            return
        }

        let session = SessionRecord(
            profile: nil,
            startedAt: .now,
            plannedSeconds: plannedSeconds,
            track: descriptor.track
        )
        context.insert(session)
        record = session

        startClock()
        presentNextTrial()
    }

    private func startClock() {
        clock?.cancel()
        // `Task {}` inside a @MainActor method inherits main-actor isolation, so
        // `tick()` is called directly - no `await`, no hop, no reentrancy window
        // between the sleep and the state change.
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard !phase.isTerminal else { return }

        if case .onBreak(let remaining) = phase {
            // Break time is real rest, so it does not count toward the session
            // budget - otherwise a break shortens the training it exists to make
            // sustainable.
            phase = remaining <= 1 ? .presenting : .onBreak(secondsRemaining: remaining - 1)
            if phase == .presenting {
                breaks.recordBreakTaken(atElapsedSeconds: elapsedSeconds)
                presentNextTrial()
            }
            return
        }

        guard phase != .paused else { return }

        elapsedSeconds += 1

        if elapsedSeconds >= plannedSeconds {
            finish(.completed)
        } else if breaks.isBreakDue(atElapsedSeconds: elapsedSeconds) {
            phase = .onBreak(secondsRemaining: breaks.breakSeconds)
            currentTrial = nil
        }
    }

    // MARK: Trials

    private func presentNextTrial() {
        guard !phase.isTerminal else { return }

        // Converging is a better reason to stop than the clock running out: it
        // means we have the measurement. The reference app's flat five-minute
        // timer keeps going long after it has learned everything it can.
        if staircase.hasConverged {
            finish(.completed)
            return
        }

        currentTrial = exercise.makeTrial(difficulty: staircase.value,
                                          generator: &generator)
        trialShownAt = .now
        phase = .presenting
    }

    /// Records a response. `frameWasDropped` comes from the renderer.
    func respond(answer: Int, frameWasDropped: Bool = false) {
        guard phase.acceptsResponses,
              let trial = currentTrial,
              let shownAt = trialShownAt else { return }

        let responseMS = Int(Date.now.timeIntervalSince(shownAt) * 1000)
        let correct = answer == trial.correctAnswer

        // Validity, decided before anything else touches the staircase.
        var discardReason: String?
        if frameWasDropped {
            discardReason = "droppedFrame"
        } else if responseMS < 150 {
            // Faster than a human can see the patch and choose. Almost always a
            // double-tap landing on the next trial.
            discardReason = "impossiblyFast"
        }

        let trialRecord = TrialRecord(
            exerciseID: descriptor.id,
            correct: correct,
            responseTimeMS: responseMS,
            difficultyValue: trial.difficulty,
            targetEye: targetEye,
            parametersJSON: trial.payload.encoded,
            discarded: discardReason != nil,
            discardReason: discardReason
        )
        trialRecord.session = record
        context.insert(trialRecord)

        if discardReason == nil {
            staircase.record(correct: correct)
            validTrialCount += 1
            if correct { correctCount += 1 }
        } else {
            staircase.discardTrial()
            discardedCount += 1
        }

        phase = .feedback(correct: correct)
        currentTrial = nil

        Task { [weak self] in
            // Long enough to register, short enough not to become the pace of
            // the session. Feedback is confirmation, not celebration.
            try? await Task.sleep(for: .milliseconds(320))
            self?.presentNextTrial()
        }
    }

    // MARK: Interruptions

    func pause() {
        guard !phase.isTerminal, phase != .paused else { return }
        phase = .paused
        currentTrial = nil
    }

    func resume() {
        guard phase == .paused else { return }
        presentNextTrial()
    }

    /// Backgrounding mid-trial. The trial in flight is abandoned rather than
    /// scored - we have no idea what the user saw or when.
    func handleBackgrounding() {
        guard !phase.isTerminal else { return }
        if currentTrial != nil { discardedCount += 1 }
        pause()
    }

    // MARK: Ending

    /// The fatigue button. Ends immediately, in one tap, from anywhere.
    /// No confirmation dialog: asking "are you sure?" after someone reports eye
    /// strain is pressure dressed as politeness. docs/14 R4.
    func reportFatigue() { finish(.fatigue) }

    func stopEarly() { finish(.userStopped) }

    func finish(_ reason: EndReason) {
        guard !phase.isTerminal else { return }
        clock?.cancel()
        clock = nil
        currentTrial = nil

        if let record {
            record.endedAt = .now
            record.actualSeconds = elapsedSeconds
            record.endedReason = reason
            record.breakCount = breaks.breaksTaken
        }
        try? context.save()

        phase = .finished(reason)
        Self.log.info("Session ended: \(reason.rawValue, privacy: .public), \(self.validTrialCount) valid trials")
    }

    /// Cancels the clock without recording an end reason - for view teardown
    /// where `finish` has already run.
    func stop() {
        clock?.cancel()
        clock = nil
    }

    // MARK: Derived

    var accuracy: Double? {
        guard validTrialCount > 0 else { return nil }
        return Double(correctCount) / Double(validTrialCount)
    }

    var secondsRemaining: Int { max(0, plannedSeconds - elapsedSeconds) }

    var progress: Double {
        guard plannedSeconds > 0 else { return 0 }
        // Whichever finishes first: the clock, or the measurement.
        return max(Double(elapsedSeconds) / Double(plannedSeconds),
                   staircase.convergenceProgress)
    }

    /// Threshold to show on the summary, or nil if we do not yet know.
    var threshold: Double? { staircase.threshold }

    var formattedThreshold: String? {
        threshold.map { descriptor.staircase.format($0) }
    }
}
