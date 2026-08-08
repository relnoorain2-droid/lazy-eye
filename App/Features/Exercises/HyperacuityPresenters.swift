//
//  HyperacuityPresenters.swift
//
//  Adapters letting M3, M4 and M8 use the shared `ChoiceExerciseView`.
//

import SwiftUI

// MARK: - M4 · Vernier

struct VernierPresenter: ChoiceExercisePresenter {
    private let exercise = VernierExercise()

    var answers: [(label: String, systemImage: String)] {
        VernierExercise.Answer.allCases.map { ($0.label, $0.systemImage) }
    }

    var instructions: String {
        "Two short lines will appear, one above the other. Say whether the top line is shifted left or right. The shift gets smaller as you go."
    }

    func stimulus(for trial: Trial, calibration: CalibrationProfile,
                  scale: Double) -> CGImage? {
        VernierGenerator.makeImage(
            exercise.parameters(for: trial, calibration: calibration),
            scale: scale)
    }
}

// MARK: - M8 · Glass pattern

struct GlassPatternPresenter: ChoiceExercisePresenter {
    private let exercise = GlassPatternExercise()

    var answers: [(label: String, systemImage: String)] {
        GlassPatternExercise.Answer.allCases.map { ($0.label, $0.systemImage) }
    }

    var instructions: String {
        "A field of dots will appear. The pairs line up either as rings around the centre or as spokes out from it. Say which — and guess when you can't tell."
    }

    func stimulus(for trial: Trial, calibration: CalibrationProfile,
                  scale: Double) -> CGImage? {
        // The dot field is random, but its seed travels in the trial payload, so
        // the exact image can be regenerated later from the trial record. A
        // stimulus nobody can reconstruct is a trial nobody can investigate.
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("seed")))
        return GlassPatternGenerator.makeImage(
            exercise.parameters(for: trial, calibration: calibration),
            generator: &generator,
            scale: scale)
    }
}

// MARK: - M3 · Crowded Gabor

struct CrowdedGaborPresenter: ChoiceExercisePresenter {
    private let exercise = CrowdedGaborExercise()

    var answers: [(label: String, systemImage: String)] {
        CrowdedGaborExercise.Answer.allCases.map { ($0.label, $0.systemImage) }
    }

    var instructions: String {
        "Three striped patches will appear side by side. The outer two are always upright — say which way the faint middle one leans. They move closer together as you go."
    }

    func stimulus(for trial: Trial, calibration: CalibrationProfile,
                  scale: Double) -> CGImage? {
        CrowdedGaborGenerator.makeImage(
            exercise.parameters(for: trial, calibration: calibration),
            scale: scale)
    }
}

// MARK: - M6 · Crowded Letters

/// The only presenter so far that varies its buttons per trial — four fresh
/// Sloan letters each time, which is why `ChoiceExercisePresenter` gained
/// `answers(for:)`.
struct CrowdedLettersPresenter: ChoiceExercisePresenter {
    private let exercise = CrowdedLettersExercise()

    /// Never shown: this exercise always has a trial when buttons are visible.
    /// Present only to satisfy the protocol's fixed-button requirement.
    var answers: [(label: String, systemImage: String)] {
        [("?", "questionmark"), ("?", "questionmark"),
         ("?", "questionmark"), ("?", "questionmark")]
    }

    func answers(for trial: Trial) -> [(label: String, systemImage: String)] {
        exercise.choices(for: trial).map { ($0, "") }
    }

    var instructions: String {
        "Three letters will appear in a row. Tap the letter that was in the MIDDLE. They get closer together as you go."
    }

    func stimulus(for trial: Trial, calibration: CalibrationProfile,
                  scale: Double) -> CGImage? {
        LetterGenerator.makeImage(
            exercise.parameters(for: trial, calibration: calibration),
            scale: scale)
    }
}
