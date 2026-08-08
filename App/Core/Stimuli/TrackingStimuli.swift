//
//  TrackingStimuli.swift
//
//  Paths, grids and passages for the five interactive exercises: M9 Smooth
//  Pursuit, M10 Jump Targets, M11 Hart Chart, M13 Path Tracer, M14 Reading.
//
//  These differ from every stimulus so far: the user's RESPONSE is continuous or
//  sequential rather than one choice per trial. That changes what a "trial"
//  means, and each exercise below says explicitly what it counts as one, because
//  a staircase fed an inconsistent trial definition converges on nothing.
//
//  docs/03-EXERCISE-CATALOG.md M9, M10, M11, M13, M14.
//

import CoreGraphics
import Foundation

// MARK: - M9 · Smooth pursuit path

/// A Lissajous figure: x = A·sin(at + δ), y = B·sin(bt).
///
/// Chosen over a circle because a circle is predictable — after one lap the eye
/// stops pursuing and starts anticipating, which is a different oculomotor
/// behaviour and not the one being trained. Incommensurable frequencies make the
/// path take a long time to repeat.
struct PursuitPath: Hashable, Sendable {

    var amplitudeDegrees: Double = 2.5
    /// Frequency ratio. 3:2 traces a figure that does not close quickly.
    var frequencyX: Double = 3
    var frequencyY: Double = 2
    var phase: Double = .pi / 2

    /// Degrees of visual angle per second along the path. The staircase axis.
    var speedDegreesPerSecond: Double

    var pointsPerDegree: Double

    var amplitudePoints: Double { amplitudeDegrees * pointsPerDegree }

    /// Canvas is the full excursion plus room for the target itself.
    var canvasPoints: Double { amplitudePoints * 2 + targetDiameterPoints * 2 }

    var targetDiameterPoints: Double { 0.8 * pointsPerDegree }

    /// Position at time `t` seconds, in canvas coordinates.
    func position(at t: Double) -> CGPoint {
        // Angular speed scaled so the tangential speed is roughly the requested
        // value. Exact arc-length parameterisation of a Lissajous has no closed
        // form; this approximation is within a few percent over the figure and
        // the staircase measures the resulting difficulty either way.
        let omega = speedDegreesPerSecond / amplitudeDegrees
        let centre = canvasPoints / 2
        return CGPoint(
            x: centre + amplitudePoints * sin(frequencyX * omega * t + phase),
            y: centre + amplitudePoints * sin(frequencyY * omega * t)
        )
    }
}

// MARK: - M10 · Saccade targets

/// Targets that appear away from centre. The user taps them; how far out they
/// appear is the staircase axis.
struct SaccadeTarget: Sendable, Identifiable {
    let id: Int
    let x: Double
    let y: Double
    let diameterPoints: Double
}

enum SaccadeGenerator {

    /// Places one target at the requested eccentricity, in a random direction,
    /// clamped so it stays fully on screen.
    static func makeTarget(eccentricityDegrees: Double,
                           pointsPerDegree: Double,
                           fieldPoints: Double,
                           id: Int,
                           generator: inout SeededGenerator) -> SaccadeTarget {
        let diameter = max(Layout.minTouchTarget, 1.2 * pointsPerDegree)
        let radius = eccentricityDegrees * pointsPerDegree
        let centre = fieldPoints / 2
        let maximumRadius = centre - diameter / 2 - 4

        let angle = Double.random(in: 0..<(2 * .pi), using: &generator)
        let used = min(radius, max(0, maximumRadius))

        return SaccadeTarget(
            id: id,
            x: centre + used * cos(angle),
            y: centre + used * sin(angle),
            diameterPoints: diameter
        )
    }
}

// MARK: - M11 · Hart chart

/// The digital version of the wall chart used in optometric practice: a grid of
/// letters, called out in a prompted order. Density is the staircase axis.
struct HartChart: Sendable {
    let columns: Int
    let rows: Int
    let letters: [String]
    /// Indices into `letters`, in the order they must be tapped.
    let sequence: [Int]
    let letterHeightPoints: Double

    var cellPoints: Double { letterHeightPoints * 2.2 }
    var widthPoints: Double { cellPoints * Double(columns) }
    var heightPoints: Double { cellPoints * Double(rows) }
}

enum HartChartGenerator {

    /// Builds a grid and a short call-out sequence.
    ///
    /// The sequence is a ROW, not scattered cells: the clinical exercise is
    /// reading across a line, which is what makes it a stamina and tracking
    /// task rather than a search task. Scattered targets would make it M12.
    static func make(columns: Int, rows: Int,
                     letterHeightPoints: Double,
                     sequenceLength: Int,
                     generator: inout SeededGenerator) -> HartChart {
        let count = columns * rows
        var letters: [String] = []
        letters.reserveCapacity(count)
        for _ in 0..<count {
            let index = Int(generator.next() % UInt64(SloanLetters.all.count))
            letters.append(SloanLetters.all[index])
        }

        let row = Int(generator.next() % UInt64(max(1, rows)))
        let start = row * columns
        let length = min(sequenceLength, columns)
        let sequence = Array(start..<(start + length))

        return HartChart(columns: columns, rows: rows, letters: letters,
                         sequence: sequence, letterHeightPoints: letterHeightPoints)
    }
}

// MARK: - M13 · Traced path

/// A winding corridor the user follows with a finger. Corridor width is the
/// staircase axis.
struct TracePath: Sendable {
    let points: [CGPoint]
    let corridorWidthPoints: Double
    let canvasPoints: Double

    /// Shortest distance from `point` to the path, for the inside/outside test.
    func distance(to point: CGPoint) -> Double {
        guard points.count >= 2 else { return .greatestFiniteMagnitude }
        var best = Double.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            best = min(best, Self.distance(from: point,
                                           to: points[index],
                                           and: points[index + 1]))
        }
        return best
    }

    /// Point-to-segment distance. Used per touch sample, so it stays cheap.
    private static func distance(from p: CGPoint, to a: CGPoint, and b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-9 else {
            return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot()
        }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        let cx = a.x + t * dx, cy = a.y + t * dy
        return ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
    }
}

enum TracePathGenerator {

    /// A sinusoidal corridor across the canvas, with a seeded phase and
    /// amplitude so no two trials are the same shape.
    static func make(canvasPoints: Double,
                     corridorWidthPoints: Double,
                     curviness: Double,
                     generator: inout SeededGenerator) -> TracePath {
        let steps = 60
        let margin = corridorWidthPoints / 2 + 8
        let usableHeight = canvasPoints - margin * 2
        let amplitude = usableHeight / 2 * min(max(curviness, 0), 1)
        let centre = canvasPoints / 2
        let phase = Double.random(in: 0..<(2 * .pi), using: &generator)
        let waves = Double.random(in: 1.5...2.5, using: &generator)

        var points: [CGPoint] = []
        points.reserveCapacity(steps + 1)
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            points.append(CGPoint(
                x: margin + t * (canvasPoints - margin * 2),
                y: centre + amplitude * sin(waves * 2 * .pi * t + phase)
            ))
        }
        return TracePath(points: points,
                         corridorWidthPoints: corridorWidthPoints,
                         canvasPoints: canvasPoints)
    }
}

// MARK: - M14 · Reading passages

/// Short passages with a one-question comprehension check.
///
/// THE COMPREHENSION CHECK IS THE MEASUREMENT, NOT DECORATION.
/// Without it the exercise measures how fast someone can scan past text they did
/// not read. The question is deliberately answerable only from the passage, and
/// a wrong answer invalidates the trial rather than merely scoring zero.
struct ReadingPassage: Sendable, Hashable {
    let text: String
    let question: String
    let options: [String]
    let correctOption: Int
}

enum ReadingPassages {

    /// Deliberately mundane, present-tense, and free of anything a reader could
    /// answer from general knowledge instead of from the passage.
    static let all: [ReadingPassage] = [
        ReadingPassage(
            text: "The blue kettle sits on the third shelf, behind a stack of white bowls. Every morning Sam fills it twice, once for tea and once for the flask he takes to work.",
            question: "How many times does Sam fill the kettle?",
            options: ["Once", "Twice", "Three times", "Four times"],
            correctOption: 1),
        ReadingPassage(
            text: "A narrow path runs along the back of the garden, past the shed and under the plum tree. In autumn the fruit drops onto the stones and the wasps arrive by lunchtime.",
            question: "What is the path made of at the end?",
            options: ["Grass", "Gravel", "Stones", "Wood"],
            correctOption: 2),
        ReadingPassage(
            text: "The library closes at six on weekdays and at one on Saturdays. It does not open on Sundays at all, which surprises visitors who have travelled a long way to see the maps.",
            question: "When does the library close on Saturdays?",
            options: ["One", "Three", "Six", "It does not open"],
            correctOption: 0),
        ReadingPassage(
            text: "Rain had been falling since before dawn, so the market was quiet. Two stalls stayed open: the bread stall under the awning, and the man who sells wool at the far end.",
            question: "How many stalls stayed open?",
            options: ["None", "One", "Two", "Three"],
            correctOption: 2),
        ReadingPassage(
            text: "The old clock in the hallway runs four minutes fast. Nobody has corrected it in years, and the family now sets their watches by it without thinking about the difference.",
            question: "How is the clock wrong?",
            options: ["Four minutes fast", "Four minutes slow", "An hour fast", "It has stopped"],
            correctOption: 0),
        ReadingPassage(
            text: "Each spring the birds return to the same gap under the roof tiles. The noise begins at first light and carries on until the young ones leave, usually by the end of June.",
            question: "Where do the birds nest?",
            options: ["In the chimney", "Under the roof tiles", "In the hedge", "On the windowsill"],
            correctOption: 1)
    ]

    static func passage(at index: Int) -> ReadingPassage {
        all[((index % all.count) + all.count) % all.count]
    }
}
