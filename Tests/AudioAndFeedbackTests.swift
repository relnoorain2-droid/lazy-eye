//
//  AudioAndFeedbackTests.swift
//
//  The app shipped to TestFlight completely silent, with four working-looking
//  toggles in Settings and an `AudioEngine.play` whose body ended at
//  `// Phase 3: actual playback`. Nothing caught it because nothing asserted
//  that a sound exists — the gate was tested, the sound was not.
//
//  These tests are about the CATALOGUE and the GATES, not about whether a
//  speaker moved. Audio output is not observable in a unit test; what is
//  observable is that every cue has a real waveform behind it, that the cues
//  are sane, and that a muted app stays muted.
//

import Testing
import Foundation
@testable import Amblyo

@MainActor
@Suite("Audio and feedback")
struct AudioAndFeedbackTests {

    // MARK: The catalogue is real

    @Test("every cue has at least one audible tone")
    func everyCueHasSound() {
        // The failure this catches: a cue declared with an empty tone list,
        // which compiles, plays nothing, and looks exactly like a working cue
        // from every call site.
        let cues: [AudioEngine.Cue] = [
            .correct, .incorrect, .sessionStart, .sessionEnd,
            .breakStart, .breakEnd, .levelChange
        ]
        for cue in cues {
            #expect(!cue.tones.isEmpty, "\(cue.name) would play silence")
            for tone in cue.tones {
                #expect(tone.seconds > 0, "\(cue.name) has a zero-length tone")
                #expect(tone.gain > 0, "\(cue.name) has a silent tone")
                // Audible range, and well inside Nyquist for 44.1 kHz.
                #expect(tone.hertz > 100 && tone.hertz < 8_000,
                        "\(cue.name) at \(tone.hertz) Hz is outside a sensible range")
            }
        }
    }

    @Test("cue names are unique, because they are the buffer cache keys")
    func cueNamesAreUnique() {
        // Two cues sharing a name would silently play each other's sound: the
        // first one rendered wins the cache and the second never renders.
        let names = [AudioEngine.Cue.correct, .incorrect, .sessionStart,
                     .sessionEnd, .breakStart, .breakEnd, .levelChange].map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test("a wrong answer is not louder or harsher than a right one")
    func wrongAnswerIsNotPunitive() {
        // A 3-down/1-up staircase produces a wrong answer roughly one trial in
        // five BY DESIGN. A buzzer would punish the user for the method working,
        // and this app is used by children.
        let correctPeak = AudioEngine.Cue.correct.tones.map(\.gain).max() ?? 0
        let wrongPeak = AudioEngine.Cue.incorrect.tones.map(\.gain).max() ?? 0
        #expect(wrongPeak <= correctPeak,
                "the incorrect cue is louder than the correct one")

        let wrongPitch = AudioEngine.Cue.incorrect.tones.first?.hertz ?? 0
        let rightPitch = AudioEngine.Cue.correct.tones.first?.hertz ?? 0
        #expect(wrongPitch < rightPitch, "wrong should be lower, not sharper")
    }

    @Test("the level-change cue is the quietest thing the app does")
    func levelChangeIsUnobtrusive() {
        // The staircase steps constantly. Anything noticeable here becomes the
        // dominant sound of a session within about ninety seconds.
        let level = AudioEngine.Cue.levelChange.tones.map(\.gain).max() ?? 1
        let correct = AudioEngine.Cue.correct.tones.map(\.gain).max() ?? 0
        #expect(level < correct)
    }

    // MARK: Defaults

    @Test("sound effects and haptics are on by default; music and voice are not")
    func defaultsAreDeliberate() {
        // The app shipped with every channel off, which read as broken rather
        // than restrained: answering a question produced nothing at all. The
        // `.ambient` category means the silent switch still wins, so there is
        // nothing to protect the user from here.
        let defaults = UserDefaults(suiteName: "audio-defaults-test")!
        defaults.removePersistentDomain(forName: "audio-defaults-test")
        let settings = SettingsStore(defaults: defaults)

        #expect(settings.soundEffectsEnabled, "answering should make a sound")
        #expect(settings.hapticsEnabled)
        #expect(!settings.musicEnabled, "music is a preference, not feedback")
        #expect(!settings.voiceGuidanceEnabled)
        #expect(!settings.masterMuted)
    }

    @Test("master mute silences every channel")
    func masterMuteWins() {
        let defaults = UserDefaults(suiteName: "audio-mute-test")!
        defaults.removePersistentDomain(forName: "audio-mute-test")
        let settings = SettingsStore(defaults: defaults)
        settings.musicEnabled = true
        settings.soundEffectsEnabled = true
        settings.voiceGuidanceEnabled = true
        settings.masterMuted = true

        #expect(!settings.isAudioAudible,
                "master mute must override the individual channels")
    }
}
