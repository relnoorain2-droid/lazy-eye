//
//  Audio.swift
//
//  Audio session configuration and playback. See docs/05-DESIGN-SYSTEM.md
//  section 7 and docs/16-EXERCISE-STAGE-SPEC.md section 4.
//
//  THIS FILE USED TO BE A PROMISE.
//  `play(_:settings:)` ended with `// Phase 3: actual playback` and the project
//  contained no audio files at all, so four toggles in Settings controlled
//  nothing and the app shipped to TestFlight silent. The gate was written first
//  "so it can never be forgotten", and then it was forgotten anyway — a stub
//  that reads as finished is worse than no stub, because nothing about it looks
//  outstanding from the call site.
//
//  THE CATEGORY CHOICE IS DELIBERATE AND SHOULD NOT BE CHANGED:
//
//    .ambient  — the hardware silent switch silences us, and the user's own
//                music keeps playing. People training for 20 minutes want their
//                own audio; an app that stops their podcast to play a blip is an
//                app they delete.
//
//    NOT .playback — that ignores the silent switch, which is precisely the
//                behaviour that earned the reference app its 1-star reviews.
//
//  TONES ARE SYNTHESISED, NOT BUNDLED.
//  Every cue is a sine with an envelope, built at runtime. No asset licensing,
//  no attribution, no megabytes, and — the reason that actually matters — every
//  cue is consistent with every other by construction, because they come from
//  one function with different arguments rather than from six files a stock
//  library happened to contain.
//

import AVFoundation
import os

@MainActor
enum AudioEngine {

    private static let log = Logger(subsystem: "com.amblyo.app", category: "audio")

    private static let engine = AVAudioEngine()
    private static var player = AVAudioPlayerNode()
    private static var started = false

    /// Rendered once on first use and reused. A trial can end every 1.5 seconds
    /// and synthesising a buffer per answer would allocate in the response path.
    private static var buffers: [String: AVAudioPCMBuffer] = [:]

    private static let speaker = AVSpeechSynthesizer()

    // MARK: - Session

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

    /// Starts the engine lazily, on the first sound rather than at launch.
    ///
    /// Most sessions never make a sound — every channel defaults to off — so
    /// starting an `AVAudioEngine` at launch would spend startup time and hold
    /// an audio route for a feature the user has not switched on.
    private static func startIfNeeded() -> Bool {
        guard !started else { return true }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: Self.format)
        do {
            try engine.start()
            player.play()
            started = true
            return true
        } catch {
            log.error("Audio engine failed to start: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Playback

    /// Every sound-producing call site must go through this gate.
    static func play(_ cue: Cue, settings: SettingsStore) {
        guard !settings.masterMuted else { return }
        switch cue.channel {
        case .music: guard settings.musicEnabled else { return }
        case .effect: guard settings.soundEffectsEnabled else { return }
        case .voice: guard settings.voiceGuidanceEnabled else { return }
        }
        guard startIfNeeded() else { return }

        let buffer: AVAudioPCMBuffer
        if let cached = buffers[cue.name] {
            buffer = cached
        } else if let made = render(cue.tones) {
            buffers[cue.name] = made
            buffer = made
        } else {
            return
        }

        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// Speaks a line, if spoken guidance is on. On-device, no network, no key.
    static func speak(_ line: String, settings: SettingsStore) {
        guard !settings.masterMuted, settings.voiceGuidanceEnabled else { return }
        // A queued synthesiser would stack up instructions behind each other and
        // narrate a trial the user has already answered.
        if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: line)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0
        speaker.speak(utterance)
    }

    // MARK: - Synthesis

    private static let sampleRate: Double = 44_100
    private static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                              channels: 1)!

    /// One tone: frequency, duration, and relative loudness.
    struct Tone {
        let hertz: Double
        let seconds: Double
        let gain: Double

        init(_ hertz: Double, _ seconds: Double, gain: Double = 0.5) {
            self.hertz = hertz
            self.seconds = seconds
            self.gain = gain
        }
    }

    /// Renders a sequence of tones into one buffer.
    ///
    /// THE ENVELOPE IS THE WHOLE DIFFERENCE BETWEEN A TONE AND A CLICK.
    /// A sine that starts and stops at full amplitude has a discontinuity at
    /// each end, and a discontinuity is broadband noise — it is heard as a click
    /// on top of the note. A few milliseconds of fade at each edge removes it.
    /// This is why a naive `sin(2πft)` implementation sounds cheap.
    private static func render(_ tones: [Tone]) -> AVAudioPCMBuffer? {
        let total = tones.reduce(0.0) { $0 + $1.seconds }
        let frames = AVAudioFrameCount(total * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        let fade = 0.006 * sampleRate          // 6 ms
        var cursor = 0

        for tone in tones {
            let count = Int(tone.seconds * sampleRate)
            let step = 2.0 * Double.pi * tone.hertz / sampleRate
            for i in 0..<count where cursor + i < Int(frames) {
                let position = Double(i)
                let remaining = Double(count - i)
                let envelope = min(1.0, min(position / fade, remaining / fade))
                channel[cursor + i] = Float(sin(step * position) * envelope * tone.gain)
            }
            cursor += count
        }
        return buffer
    }

    // MARK: - Cues

    enum Channel { case music, effect, voice }

    struct Cue {
        let name: String
        let channel: Channel
        let tones: [Tone]
    }
}

// MARK: - The catalogue
//
// Every sound the app makes, in one place, so the set stays coherent. Anything
// added here should be defensible in the terms of section 4 of the spec.

extension AudioEngine.Cue {

    /// A correct answer. Rising, brief, quiet — it happens about four times in
    /// five by design, so it must never become tiring.
    static let correct = AudioEngine.Cue(
        name: "correct", channel: .effect,
        tones: [.init(880, 0.09, gain: 0.34)])

    /// A wrong answer. Lower and slightly longer, and deliberately NOT harsh.
    /// A 3-down/1-up staircase produces a wrong answer roughly one trial in
    /// five on purpose; a buzzer would punish the user for the method working.
    static let incorrect = AudioEngine.Cue(
        name: "incorrect", channel: .effect,
        tones: [.init(320, 0.12, gain: 0.28)])

    static let sessionStart = AudioEngine.Cue(
        name: "sessionStart", channel: .effect,
        tones: [.init(523.25, 0.10, gain: 0.30), .init(783.99, 0.14, gain: 0.30)])

    static let sessionEnd = AudioEngine.Cue(
        name: "sessionEnd", channel: .effect,
        tones: [.init(659.25, 0.11, gain: 0.30),
                .init(783.99, 0.11, gain: 0.30),
                .init(1046.50, 0.20, gain: 0.30)])

    static let breakStart = AudioEngine.Cue(
        name: "breakStart", channel: .effect,
        tones: [.init(440, 0.16, gain: 0.26)])

    static let breakEnd = AudioEngine.Cue(
        name: "breakEnd", channel: .effect,
        tones: [.init(587.33, 0.14, gain: 0.28)])

    /// The difficulty stepped to a new level. Very quiet: informative, not a
    /// reward, because the staircase moves constantly and a fanfare every few
    /// trials would be unbearable.
    static let levelChange = AudioEngine.Cue(
        name: "levelChange", channel: .effect,
        tones: [.init(1174.66, 0.06, gain: 0.16)])
}
