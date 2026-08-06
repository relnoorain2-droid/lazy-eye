//
//  TrialRecord.swift
//
//  One response to one stimulus. This is the atom of the whole app — every
//  threshold, chart and coach sentence is computed from these rows.
//
//  Expect ~150-400 per session, so keep it cheap: no relationships beyond the
//  parent, no computed persistence, indexed on timestamp.
//
//  docs/04-ARCHITECTURE.md section 3, docs/06-AI-ENGINE-SPEC.md section 2.
//

import Foundation
import SwiftData

@Model
final class TrialRecord {

    var session: SessionRecord?

    var exerciseID: String
    var timestamp: Date

    var correct: Bool
    var responseTimeMS: Int

    /// The value of the exercise's single staircase dimension on this trial.
    /// Its units depend on the exercise (degrees, contrast, arc-seconds…), which
    /// is why the full parameter snapshot is stored alongside it.
    var difficultyValue: Double

    /// Which eye the stimulus targeted. `.unknown` for binocular tasks.
    var targetEyeRaw: String

    /// JSON snapshot of the full `ExerciseParameters` at trial time, so a trial
    /// stays interpretable even after the exercise's defaults change in a later
    /// app version. Phase 5 defines the struct.
    var parametersJSON: Data?

    /// True when the trial must be excluded from threshold estimation — a
    /// dropped frame, a backgrounded app, or a response outside the window.
    /// docs/04-ARCHITECTURE.md section 5: a dropped frame invalidates the trial.
    var discarded: Bool
    var discardReason: String?

    init(
        session: SessionRecord? = nil,
        exerciseID: String,
        timestamp: Date = .now,
        correct: Bool,
        responseTimeMS: Int,
        difficultyValue: Double,
        targetEye: Eye = .unknown,
        parametersJSON: Data? = nil,
        discarded: Bool = false,
        discardReason: String? = nil
    ) {
        self.session = session
        self.exerciseID = exerciseID
        self.timestamp = timestamp
        self.correct = correct
        self.responseTimeMS = responseTimeMS
        self.difficultyValue = difficultyValue
        self.targetEyeRaw = targetEye.rawValue
        self.parametersJSON = parametersJSON
        self.discarded = discarded
        self.discardReason = discardReason
    }
}

extension TrialRecord {
    var targetEye: Eye {
        get { Eye(rawValue: targetEyeRaw) ?? .unknown }
        set { targetEyeRaw = newValue.rawValue }
    }

    /// Implausibly fast responses are almost always mashing, not perception.
    /// Flagged rather than deleted so the behaviour stays visible in diagnostics.
    var isSuspiciouslyFast: Bool { responseTimeMS < 150 }
}
