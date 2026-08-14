//
//  SettingsStore.swift
//
//  User preferences. THE AUDIO DEFAULTS IN THIS FILE ARE A COMPLIANCE-LEVEL
//  REQUIREMENT, not a taste decision.
//
//  The reference app's single worst-reviewed feature was unmuteable UI sound —
//  see docs/14-REVIEW-COMPLAINTS-MATRIX.md R1 and R2, and
//  docs/05-DESIGN-SYSTEM.md section 7.
//
//  Rules, restated so nobody "helpfully" flips a default later:
//    1. Every audio channel is OFF on first install.
//    2. Three independent channels: music, sound effects, voice guidance.
//    3. A master mute is reachable in one tap from any running exercise.
//    4. Changes apply immediately, mid-sound. No restart.
//    5. The hardware silent switch always wins (AVAudioSession .ambient).
//    6. No exercise requires audio to function.
//

import Foundation
import Observation

@Observable
@MainActor
final class SettingsStore {

    // MARK: Audio — all default false. Do not change.

    var musicEnabled: Bool { didSet { persist(\.musicEnabled, "audio.music") } }
    var soundEffectsEnabled: Bool { didSet { persist(\.soundEffectsEnabled, "audio.sfx") } }
    var voiceGuidanceEnabled: Bool { didSet { persist(\.voiceGuidanceEnabled, "audio.voice") } }

    /// One-tap override. When true, nothing plays regardless of the channels above.
    var masterMuted: Bool { didSet { persist(\.masterMuted, "audio.masterMuted") } }

    /// True when any sound may play at all. Every audio call site checks this.
    var isAudioAudible: Bool {
        !masterMuted && (musicEnabled || soundEffectsEnabled || voiceGuidanceEnabled)
    }

    /// Shown once on first launch so the user never has to hunt for the setting.
    var hasSeenSoundChoice: Bool { didSet { persist(\.hasSeenSoundChoice, "audio.seenChoice") } }

    // MARK: Feedback

    var hapticsEnabled: Bool { didSet { persist(\.hapticsEnabled, "haptics.enabled") } }

    // MARK: Appearance

    var themePreference: ThemePreference {
        didSet { defaults.set(themePreference.rawValue, forKey: Self.key("theme")) }
    }

    /// `displayName` and `colorScheme` live in an extension in
    /// `DesignSystem/Theme.swift`, not here — this type is storage, and the
    /// words shown to the user are presentation. Adding a second `displayName`
    /// here is exactly what broke CI run 34.
    enum ThemePreference: String, CaseIterable, Sendable {
        case system, light, dark
    }

    // MARK: Notifications

    var remindersEnabled: Bool { didSet { persist(\.remindersEnabled, "reminders.enabled") } }
    var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: Self.key("reminders.hour")) } }
    var reminderMinute: Int { didSet { defaults.set(reminderMinute, forKey: Self.key("reminders.minute")) } }

    // MARK: - Storage

    private let defaults: UserDefaults

    private static func key(_ suffix: String) -> String { "amblyo.\(suffix)" }

    private func persist(_ keyPath: KeyPath<SettingsStore, Bool>, _ suffix: String) {
        defaults.set(self[keyPath: keyPath], forKey: Self.key(suffix))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // `bool(forKey:)` returns false for a missing key, which is exactly the
        // default we want for every audio channel. Stated explicitly rather than
        // relied upon implicitly.
        musicEnabled = defaults.bool(forKey: Self.key("audio.music"))
        soundEffectsEnabled = defaults.bool(forKey: Self.key("audio.sfx"))
        voiceGuidanceEnabled = defaults.bool(forKey: Self.key("audio.voice"))
        masterMuted = defaults.bool(forKey: Self.key("audio.masterMuted"))
        hasSeenSoundChoice = defaults.bool(forKey: Self.key("audio.seenChoice"))

        hapticsEnabled = defaults.object(forKey: Self.key("haptics.enabled")) as? Bool ?? true
        remindersEnabled = defaults.bool(forKey: Self.key("reminders.enabled"))

        reminderHour = defaults.object(forKey: Self.key("reminders.hour")) as? Int ?? 18
        reminderMinute = defaults.object(forKey: Self.key("reminders.minute")) as? Int ?? 30

        themePreference = ThemePreference(
            rawValue: defaults.string(forKey: Self.key("theme")) ?? ""
        ) ?? .system
    }

    /// Used by the master mute control in the session nav bar.
    func toggleMasterMute() { masterMuted.toggle() }
}
