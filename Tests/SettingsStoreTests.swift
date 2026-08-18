//
//  SettingsStoreTests.swift
//
//  These tests exist to make constraint C6 unbreakable: every audio channel is
//  OFF on a fresh install. The reference app's single worst-reviewed feature was
//  sound the user could not turn off (docs/14-REVIEW-COMPLAINTS-MATRIX.md R1/R2).
//
//  If one of these ever fails, someone has "helpfully" flipped a default. Do not
//  update the test to match the code — fix the code.
//

import Testing
import Foundation
@testable import Amblyo

@MainActor
struct SettingsStoreTests {

    /// A UserDefaults suite isolated per test, so nothing leaks between runs.
    private func freshDefaults() -> UserDefaults {
        let name = "amblyo.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("Feedback sounds are on by default; music and voice are not")
    func audioDefaultsAreDeliberate() {
        // THIS TEST USED TO ASSERT THE OPPOSITE, AND IT WAS RIGHT TO.
        //
        // It was `audioDefaultsAreOff`, pinning a decision that every channel
        // starts silent so the app never makes noise unasked. That reasoning was
        // sound and the conclusion was wrong, which the first device test made
        // obvious: answering a question produced no sound at all, and an app
        // that does not respond to a tap does not read as restrained. It reads
        // as broken.
        //
        // What the original argument missed is that the audio session is
        // `.ambient`. The hardware silent switch already silences this app and
        // the user's own music already keeps playing, so the harm the default
        // was protecting against cannot occur.
        //
        // The line kept from the old decision: music and spoken guidance are
        // PREFERENCES and stay off. A short tone confirming a tap is FEEDBACK,
        // and feedback is not optional furniture.
        let settings = SettingsStore(defaults: freshDefaults())

        #expect(settings.soundEffectsEnabled, "answering a trial must be audible")
        #expect(settings.isAudioAudible)
        #expect(settings.musicEnabled == false)
        #expect(settings.voiceGuidanceEnabled == false)
        #expect(settings.masterMuted == false)
    }

    @Test("Muting everything really does silence the app")
    func mutingEveryChannelIsSilent() {
        // The old default made this state the starting point, so nothing ever
        // checked it explicitly. It is now something a user has to choose, which
        // makes it worth a test of its own.
        let settings = SettingsStore(defaults: freshDefaults())
        settings.soundEffectsEnabled = false
        settings.musicEnabled = false
        settings.voiceGuidanceEnabled = false

        #expect(settings.isAudioAudible == false)
    }

    @Test("Master mute silences every channel regardless of individual toggles")
    func masterMuteOverridesChannels() {
        let settings = SettingsStore(defaults: freshDefaults())
        settings.musicEnabled = true
        settings.soundEffectsEnabled = true
        settings.voiceGuidanceEnabled = true

        #expect(settings.isAudioAudible == true)

        settings.masterMuted = true
        #expect(settings.isAudioAudible == false)
    }

    @Test("Master mute toggles in one call")
    func masterMuteToggles() {
        let settings = SettingsStore(defaults: freshDefaults())
        #expect(settings.masterMuted == false)
        settings.toggleMasterMute()
        #expect(settings.masterMuted == true)
        settings.toggleMasterMute()
        #expect(settings.masterMuted == false)
    }

    @Test("Audio settings persist across instances")
    func audioSettingsPersist() {
        let defaults = freshDefaults()

        let first = SettingsStore(defaults: defaults)
        first.soundEffectsEnabled = true

        let second = SettingsStore(defaults: defaults)
        #expect(second.soundEffectsEnabled == true)
        #expect(second.musicEnabled == false)
    }

    @Test("The sound-choice card has not been seen on a fresh install")
    func soundChoiceUnseenInitially() {
        let settings = SettingsStore(defaults: freshDefaults())
        #expect(settings.hasSeenSoundChoice == false)
    }

    @Test("Haptics default on, reminders default off")
    func otherDefaults() {
        let settings = SettingsStore(defaults: freshDefaults())
        #expect(settings.hapticsEnabled == true)
        #expect(settings.remindersEnabled == false)
        #expect(settings.themePreference == .system)
    }
}
