//
//  Haptics.swift
//
//  Touch feedback. docs/16-EXERCISE-STAGE-SPEC.md section 5.
//
//  WHY THIS IS A SEPARATE CHANNEL FROM SOUND AND NOT A SETTING ON IT.
//  They are used in different rooms. Sound is off for someone training on a bus
//  or next to a sleeping child; haptics still work there and are the only
//  confirmation that a tap registered. Tying them together would mean muting the
//  app also removes its responsiveness, which is how an app comes to feel dead.
//
//  Generators are held rather than created per call. `UIFeedbackGenerator`
//  spins up the Taptic Engine on `prepare()` and lets it idle down afterwards;
//  constructing one at the moment of use gives the first tap of a session a
//  noticeably late buzz, and the first tap of a session is the one that teaches
//  the user whether this app responds.
//

#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum Haptics {

    #if canImport(UIKit)
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()
    #endif

    /// Call when a response screen appears, so the engine is warm for the first
    /// answer rather than a beat behind it.
    static func prepare(settings: SettingsStore) {
        guard settings.hapticsEnabled else { return }
        #if canImport(UIKit)
        impact.prepare()
        notification.prepare()
        #endif
    }

    /// A tap was received. Fires on EVERY answer, before the answer is judged,
    /// because it is confirming the touch and not the outcome.
    static func tap(settings: SettingsStore) {
        guard settings.hapticsEnabled else { return }
        #if canImport(UIKit)
        impact.impactOccurred(intensity: 0.7)
        #endif
    }

    /// The trial was correct.
    static func success(settings: SettingsStore) {
        guard settings.hapticsEnabled else { return }
        #if canImport(UIKit)
        notification.notificationOccurred(.success)
        #endif
    }

    /// The trial was wrong.
    ///
    /// `.warning` rather than `.error`. A staircase is built to produce a wrong
    /// answer about one trial in five, so this fires constantly by design, and
    /// `.error` is a three-part jolt that reads as "you have broken something".
    static func miss(settings: SettingsStore) {
        guard settings.hapticsEnabled else { return }
        #if canImport(UIKit)
        notification.notificationOccurred(.warning)
        #endif
    }

    /// The session finished.
    static func completion(settings: SettingsStore) {
        guard settings.hapticsEnabled else { return }
        #if canImport(UIKit)
        notification.notificationOccurred(.success)
        #endif
    }
}
