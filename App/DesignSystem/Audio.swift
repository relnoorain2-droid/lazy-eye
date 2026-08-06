//
//  Audio.swift
//
//  Audio session configuration. See docs/05-DESIGN-SYSTEM.md section 7.
//
//  The category choice is deliberate and should not be changed:
//
//    .ambient  — the hardware silent switch silences us, and the user's own
//                music keeps playing. People training for 20 minutes want their
//                own audio; an app that stops their podcast to play a blip is an
//                app they delete.
//
//    NOT .playback — that ignores the silent switch, which is precisely the
//                behaviour that earned the reference app its 1-star reviews.
//

import AVFoundation
import os

enum AudioEngine {

    private static let log = Logger(subsystem: "com.amblyo.app", category: "audio")

    /// Called once at launch, before any view appears.
    static func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Audio is never required for the app to function, so a failure here
            // is logged and ignored rather than surfaced.
            log.error("Audio session configuration failed: \(error.localizedDescription)")
        }
    }

    /// Every sound-producing call site must go through this gate.
    /// Phase 3 fills in the actual playback; the gate exists from day one so it
    /// can never be forgotten.
    @MainActor
    static func play(_ cue: Cue, settings: SettingsStore) {
        guard !settings.masterMuted else { return }
        switch cue.channel {
        case .music: guard settings.musicEnabled else { return }
        case .effect: guard settings.soundEffectsEnabled else { return }
        case .voice: guard settings.voiceGuidanceEnabled else { return }
        }
        // Phase 3: actual playback.
    }

    enum Channel { case music, effect, voice }

    struct Cue {
        let name: String
        let channel: Channel
    }
}
