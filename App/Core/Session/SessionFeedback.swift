//
//  SessionFeedback.swift
//
//  Turns the moments a session already knows about into sound and touch.
//
//  WHY THIS IS A TYPE AND NOT CALLS TO `AudioEngine` INSIDE `SessionRunner`.
//
//  1. The runner is the app's measurement loop and it should not import a sound
//     engine. Its tests construct one per case; making it depend on audio would
//     mean every one of those tests starts a `SettingsStore` to prove something
//     about a staircase.
//
//  2. Sound and haptics are separately switchable, and the pairing rules are
//     not obvious — a wrong answer gets the lightest available haptic and a soft
//     low tone, a fatigue stop gets neither. Those decisions belong together in
//     one readable place rather than scattered across the runner's branches.
//
//  The runner holds this optionally. When it is nil the app is silent, which is
//  exactly right for a unit test and is not a failure state.
//
//  docs/16-EXERCISE-STAGE-SPEC.md sections 4 and 5.
//

import Foundation

@MainActor
struct SessionFeedback {

    let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: Trial

    /// An answer was judged. Fires for discarded trials too — see the call site.
    func judged(correct: Bool) {
        if correct {
            AudioEngine.play(.correct, settings: settings)
            Haptics.success(settings: settings)
        } else {
            AudioEngine.play(.incorrect, settings: settings)
            Haptics.miss(settings: settings)
        }
    }

    // MARK: Session

    func sessionStarted() {
        AudioEngine.play(.sessionStart, settings: settings)
    }

    func sessionCompleted() {
        AudioEngine.play(.sessionEnd, settings: settings)
        Haptics.completion(settings: settings)
    }

    // MARK: Breaks

    /// Spoken as well as played. A break exists because someone has been staring
    /// at a screen for twenty minutes, and the one instruction that matters —
    /// look at something far away — is useless if it is only on the screen they
    /// have been told to look away from.
    func breakStarted() {
        AudioEngine.play(.breakStart, settings: settings)
        AudioEngine.speak("Take a short break. Look at something far away.",
                          settings: settings)
    }

    func breakEnded() {
        AudioEngine.play(.breakEnd, settings: settings)
    }
}
