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

    @Test("Every audio channel is off on a fresh install")
    func audioDefaultsAreOff() {
        let settings = SettingsStore(defaults: freshDefaults())

        #expect(settings.musicEnabled == false)
        #expect(settings.soundEffectsEnabled == false)
        #expect(settings.voiceGuidanceEnabled == false)
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
