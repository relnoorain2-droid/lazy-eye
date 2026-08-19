//
//  MotionAndSearchStimuli.swift
//
//  Random-dot kinematograms, Sloan letter grids and search fields — the stimuli
//  for M7, M6, M11 and M12.
//
//  WHY MOTION IS SAFE HERE DESPITE THE FLICKER RULE.
//  `FlickerGuard` caps temporal rate at 3 Hz because photosensitive seizures are
//  provoked by high-contrast LUMINANCE OSCILLATION - a region of screen going
//  light-dark-light. A random-dot kinematogram does not do that: individual dots
//  translate smoothly, and any given screen region holds a roughly constant mean
//  luminance because the dot density is uniform. The provocative quantity is
//  flash rate, not dot speed, so a dot field moving at 4 degrees per second has
//  a temporal rate of ZERO by the measure that matters.
//
//  What WOULD be unsafe is regenerating the whole field on a fast cycle, so dot
//  lifetime is deliberately long and staggered - see `dotLifetimeFrames`.
//
//  docs/01-RESEARCH-BRIEF.md section 7, docs/03-EXERCISE-CATALOG.md M6, M7, M11, M12.
//

import CoreGraphics
import Foundation

// MARK: - M7 · Random-dot kinematogram

struct KinematogramParameters: Hashable, Sendable {

    enum Direction: Int, CaseIterable, Sendable {
        case up = 0, right = 1, down = 2, left = 3

        /// Radians, screen coordinates (y down).
        var radians: Double {
            switch self {
            case .up: -.pi / 2
            case .right: 0
            case .down: .pi / 2
            case .left: .pi
            }
        }

        // NAMES AND ICONS LIVE ON THE TYPE, NOT IN THE VIEWS.
        // They were private helpers inside `BalanceMeterView`. The moment the
        // Check-in needed the same four buttons, that became a second copy of
        // the same switch — and two copies of "which arrow means up" is exactly
        // how a screen ends up labelling a stimulus wrongly while still
        // compiling and still passing every test.
        var label: String {
            switch self {
            case .up: "Up"
            case .right: "Right"
            case .down: "Down"
            case .left: "Left"
            }
        }

        var systemImage: String {
            switch self {
            case .up: "arrow.up"
            case .right: "arrow.right"
            case .down: "arrow.down"
            case .left: "arrow.left"
            }
        }
    }

    var direction: Direction

    /// Fraction of dots moving coherently, 0...1. The staircase axis.
    var coherence: Double

    var dotCount: Int = 200
    var fieldDegrees: Double = 6.5
    var dotDiameterPoints: Double = 4

    /// Degrees of visual angle per second. Slow enough to track, fast enough
    /// that direction is unambiguous within a short presentation.
    var speedDegreesPerSecond: Double = 4

    /// Frames a dot lives before being replaced at a random position. Long, and
    /// STAGGERED across dots, so the field never refreshes wholesale - a
    /// synchronised replacement would be a full-field luminance event.
    var dotLifetimeFrames: Int = 30

    var pointsPerDegree: Double

    var contrast: Double = 0.9

    var fieldPoints: Double { fieldDegrees * pointsPerDegree }

    /// Displacement per frame at 60 fps.
    var stepPoints: Double {
        (speedDegreesPerSecond * pointsPerDegree) / 60.0
    }
}

/// One dot's state. The renderer advances these; the view owns the array.
struct KinematogramDot: Sendable {
    var x: Double
    var y: Double
    var isSignal: Bool
    var framesLived: Int
}

enum KinematogramGenerator {

    /// Initial dot field. Lifetimes are staggered so replacements are spread
    /// evenly over time rather than happening to every dot at once.
    static func makeDots(_ p: KinematogramParameters,
                         generator: inout SeededGenerator) -> [KinematogramDot] {
        let side = p.fieldPoints
        return (0..<p.dotCount).map { _ in
            KinematogramDot(
                x: Double.random(in: 0..<side, using: &generator),
                y: Double.random(in: 0..<side, using: &generator),
                isSignal: Double.random(in: 0..<1, using: &generator) < p.coherence,
                framesLived: Int.random(in: 0..<p.dotLifetimeFrames, using: &generator)
            )
        }
    }

    /// Advances one frame. Signal dots move coherently; noise dots take a random
    /// walk of the SAME step size, so speed cannot be used as a cue instead of
    /// direction.
    static func advance(_ dots: inout [KinematogramDot],
                        parameters p: KinematogramParameters,
                        generator: inout SeededGenerator) {
        let side = p.fieldPoints
        let step = p.stepPoints
        let signalAngle = p.direction.radians

        for index in dots.indices {
            dots[index].framesLived += 1

            if dots[index].framesLived >= p.dotLifetimeFrames {
                dots[index].x = Double.random(in: 0..<side, using: &generator)
                dots[index].y = Double.random(in: 0..<side, using: &generator)
                dots[index].isSignal = Double.random(in: 0..<1, using: &generator) < p.coherence
                dots[index].framesLived = 0
                continue
            }

            let angle = dots[index].isSignal
                ? signalAngle
                : Double.random(in: 0..<(2 * .pi), using: &generator)

            dots[index].x += step * cos(angle)
            dots[index].y += step * sin(angle)

            // Wrap rather than clamp: clamping would pile dots along the edges
            // and the resulting density gradient is itself a direction cue.
            if dots[index].x < 0 { dots[index].x += side }
            if dots[index].x >= side { dots[index].x -= side }
            if dots[index].y < 0 { dots[index].y += side }
            if dots[index].y >= side { dots[index].y -= side }
        }
    }
}

// MARK: - M6 · Sloan letters

/// The ten Sloan letters, which are the standard optotype set: they were
/// designed to be equally legible, so an acuity measured with one is comparable
/// with another. Using arbitrary letters would mean partly measuring which
/// letters the person happened to be shown.
enum SloanLetters {
    static let all: [String] = ["C", "D", "H", "K", "N", "O", "R", "S", "V", "Z"]

    /// A target plus three distractors, all distinct.
    static func choices(generator: inout SeededGenerator) -> [String] {
        var pool = all
        var picked: [String] = []
        for _ in 0..<4 {
            guard !pool.isEmpty else { break }
            let index = Int(generator.next() % UInt64(pool.count))
            picked.append(pool.remove(at: index))
        }
        return picked
    }
}

struct CrowdedLettersParameters: Hashable, Sendable {

    var target: String
    var flankers: [String]

    /// Letter height in logMAR. Held FIXED while spacing varies — this exercise
    /// measures crowding, not acuity, and letting both move would confound them.
    var logMAR: Double

    /// Centre-to-centre spacing, in multiples of letter width. The staircase axis.
    var spacingRatio: Double

    var pointsPerDegree: Double
    var contrast: Double = 0.9

    /// A letter's height is 5x the gap that defines its logMAR, by the same
    /// convention the Landolt C uses.
    var letterHeightPoints: Double {
        pow(10, logMAR) * (pointsPerDegree / 60.0) * 5
    }

    var spacingPoints: Double { letterHeightPoints * spacingRatio }

    /// Target plus one flanker each side.
    var canvasWidth: Double { spacingPoints * 2 + letterHeightPoints * 1.2 }
    var canvasHeight: Double { letterHeightPoints * 1.6 }
}

// MARK: - M12 · Visual search

struct SearchFieldParameters: Hashable, Sendable {

    /// How many items are on screen. More is harder — this is the staircase axis
    /// and it is HIGHER-IS-HARDER, unlike most of the catalogue.
    var itemCount: Int

    /// How similar distractors are to the target, 0...1. Held fixed so set size
    /// is the only thing varying.
    var similarity: Double = 0.6

    var fieldDegrees: Double = 7.0

    /// 0.7 degrees, paired with a maximum of 20 items.
    ///
    /// SIZED SO THE FIELD CAN ACTUALLY HOLD THE HARDEST SETTING.
    /// At 0.8 degrees the rejection sampler can only place about 27 items on an
    /// iPhone SE before it runs out of non-overlapping positions, but the
    /// staircase was allowed to ask for 40. It would have silently returned
    /// fewer items than requested, so difficulty would stop rising while the
    /// staircase kept climbing - and the threshold would come back as "40 items"
    /// for a screen that never showed more than 27. Capacity is now roughly 36
    /// against a ceiling of 20.
    var itemDegrees: Double = 0.7
    var pointsPerDegree: Double

    var fieldPoints: Double { fieldDegrees * pointsPerDegree }
    var itemPoints: Double { itemDegrees * pointsPerDegree }
}

struct SearchItem: Sendable, Identifiable {
    let id: Int
    let x: Double
    let y: Double
    let rotationDegrees: Double
    let isTarget: Bool
}

enum SearchFieldGenerator {

    /// Places items without overlap, using rejection sampling with a bounded
    /// attempt count so a crowded field cannot loop forever.
    static func makeItems(_ p: SearchFieldParameters,
                          generator: inout SeededGenerator) -> [SearchItem] {
        var items: [SearchItem] = []
        let minimumSeparation = p.itemPoints * 1.3
        let margin = p.itemPoints / 2
        let usable = p.fieldPoints - p.itemPoints

        guard usable > 0 else { return [] }

        // The target's rotation is what the user is looking for; distractors sit
        // at a fixed angular offset from it, scaled by similarity.
        let targetRotation = Double.random(in: 0..<360, using: &generator)
        let distractorOffset = 90 * (1 - p.similarity)

        var attempts = 0
        let maximumAttempts = p.itemCount * 60

        while items.count < p.itemCount && attempts < maximumAttempts {
            attempts += 1
            let x = margin + Double.random(in: 0..<usable, using: &generator)
            let y = margin + Double.random(in: 0..<usable, using: &generator)

            let clashes = items.contains { other in
                let dx = other.x - x, dy = other.y - y
                return (dx * dx + dy * dy).squareRoot() < minimumSeparation
            }
            if clashes { continue }

            let isTarget = items.isEmpty      // exactly one target, placed first
            let rotation = isTarget
                ? targetRotation
                : targetRotation + distractorOffset
                    * (Double.random(in: 0..<1, using: &generator) < 0.5 ? 1 : -1)

            items.append(SearchItem(id: items.count, x: x, y: y,
                                    rotationDegrees: rotation, isTarget: isTarget))
        }
        return items
    }
}
