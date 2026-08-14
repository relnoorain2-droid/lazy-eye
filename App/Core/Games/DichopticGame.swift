//
//  DichopticGame.swift
//
//  The shared core under every dichoptic game: D3 Stack Drop, D4 Bounce, and the
//  kids games G1, G2, G3, G8. All of them are the same idea wearing different
//  costumes — one moving thing to the amblyopic eye, its context to the fellow
//  eye, and a contrast ratio between them that the staircase drives.
//
//  WHY A SHARED CORE AND NOT SIX SEPARATE GAMES
//  The therapy is not the game. It is the eye assignment and the contrast ratio,
//  and those must be identical everywhere or two exercises will report thresholds
//  on different scales while both calling the number "balance". Six hand-written
//  loops would drift within a month. The game-specific part is what bounces off
//  what; everything that makes it a TREATMENT lives here.
//
//  EVERYTHING IS IN DEGREES, NOT POINTS
//  Position, size and speed are angular. A ball crossing the screen in two
//  seconds on an iPad must cross in two seconds on an iPhone, and cover the same
//  visual angle doing it — otherwise the same difficulty level is a different
//  task per device and the thresholds cannot be compared. Points appear only at
//  the moment of drawing.
//
//  THE FIELD IS 9 x 12 DEGREES, MEASURED NOT CHOSEN
//  Checked against the real device table before any of this was written:
//
//      device          9 x 12 deg        screen        headroom
//      iPhone SE 3     268 x 358 pt      320 x 568     ok
//      iPhone 14 Pro   346 x 462 pt      393 x 852     ok
//      iPad 10.9       371 x 494 pt      820 x 1180    ok
//      iPad Pro 13     428 x 571 pt      1024 x 1366   ok
//
//  10 x 14 degrees was the first choice and it CLIPS on both phones once the
//  navigation bar and answer controls are allowed for. A clipped playfield is
//  not a cosmetic problem here: the ball would vanish behind the chrome and the
//  user would lose it through no fault of their own.
//
//  SPEED IS CAPPED AT 15 DEGREES PER SECOND
//  Human smooth pursuit degrades badly above roughly 15 deg/s and fails around
//  30. An amblyopic eye is worse. Faster than the cap and the task stops being
//  about sustained fusion and becomes a saccade task — which is M10's job, and
//  measuring it here while calling it fusion would be wrong.
//
//  docs/03-EXERCISE-CATALOG.md D3, D4, G1-G8.
//

import CoreGraphics
import Foundation

/// The playfield, in angular units, plus the one conversion to points.
struct GameField: Sendable, Equatable {

    /// Width and height in degrees of visual angle. Verified to fit every
    /// supported device with room for navigation and controls.
    static let widthDegrees: Double = 9.0
    static let heightDegrees: Double = 12.0

    /// The fastest anything may move, in degrees per second. A ceiling, not a
    /// setting: above this the exercise measures saccades rather than fusion.
    static let maximumSpeedDegreesPerSecond: Double = 15.0

    let pointsPerDegree: Double

    init(pointsPerDegree: Double) {
        self.pointsPerDegree = max(pointsPerDegree, 1)
    }

    init(calibration: CalibrationProfile) {
        self.init(pointsPerDegree: calibration.points(forDegrees: 1.0))
    }

    var widthPoints: Double { Self.widthDegrees * pointsPerDegree }
    var heightPoints: Double { Self.heightDegrees * pointsPerDegree }

    func points(_ degrees: Double) -> Double { degrees * pointsPerDegree }

    /// Angular position (origin at the field's top-left) to a drawing point.
    func point(_ position: CGPoint) -> CGPoint {
        CGPoint(x: position.x * pointsPerDegree, y: position.y * pointsPerDegree)
    }
}

/// Which eye an element is drawn to. The whole therapeutic content of these
/// games is in this assignment, so it is a named type rather than a bool.
enum GameLayer: Sendable, Equatable {
    /// The thing the user must track and act on. Amblyopic eye, full contrast.
    case actor
    /// The context it interacts with: the stack, the bricks, the basket's
    /// surroundings. Fellow eye, contrast set by the staircase.
    case context
    /// Drawn to both eyes. Borders and the fusion lock only — anything else
    /// shown to both eyes gives the fellow eye a way to do the task alone.
    case shared
}

/// One frame's worth of simulation, shared by every game.
///
/// Deliberately a plain struct with a pure `step`: a game loop tangled into a
/// SwiftUI view can only be tested by playing it, and "does the ball pass
/// through the paddle at high speed" is not a question to answer by hand.
struct GamePhysics: Sendable {

    struct Body: Sendable, Equatable {
        /// Centre, in degrees from the field's top-left.
        var position: CGPoint
        /// Degrees per second.
        var velocity: CGPoint
        /// Diameter in degrees.
        var size: Double

        var radius: Double { size / 2 }
    }

    /// Fixed timestep. A variable step driven by actual frame times makes the
    /// simulation depend on how busy the device is, so a dropped frame becomes a
    /// longer jump and the ball can pass through things. It also means the same
    /// seed replays differently on a slow phone.
    static let timestep: Double = 1.0 / 60.0

    /// Advances a body and bounces it off the field's walls.
    ///
    /// EACH EDGE IS OPTIONAL, and that is not over-engineering. Bounce needs the
    /// bottom open so a missed ball can leave; Balloon Pop needs the TOP open so
    /// an unpopped balloon can escape. With the top hard-wired as a wall — which
    /// is how this was first written — a balloon would bounce back down forever
    /// and the trial could never end in a miss. The game would look fine and
    /// simply never record a failure, so the staircase would climb until every
    /// balloon was invisible.
    ///
    /// - Parameter bounceBottom: false where the bottom edge is a miss.
    /// - Parameter bounceTop: false where the top edge is an escape.
    static func step(_ body: Body, in field: GameField,
                     bounceBottom: Bool = true,
                     bounceTop: Bool = true,
                     timestep: Double = Self.timestep) -> Body {
        var moved = body
        moved.position.x += body.velocity.x * timestep
        moved.position.y += body.velocity.y * timestep

        let radius = body.radius
        if moved.position.x - radius < 0 {
            moved.position.x = radius
            moved.velocity.x = abs(moved.velocity.x)
        } else if moved.position.x + radius > GameField.widthDegrees {
            moved.position.x = GameField.widthDegrees - radius
            moved.velocity.x = -abs(moved.velocity.x)
        }

        if bounceTop, moved.position.y - radius < 0 {
            moved.position.y = radius
            moved.velocity.y = abs(moved.velocity.y)
        } else if bounceBottom, moved.position.y + radius > GameField.heightDegrees {
            moved.position.y = GameField.heightDegrees - radius
            moved.velocity.y = -abs(moved.velocity.y)
        }
        return moved
    }

    /// Distance covered in one frame, in degrees. The tunnelling check compares
    /// this against the thickness of whatever the body must not pass through.
    static func travelPerFrame(_ body: Body, timestep: Double = Self.timestep) -> Double {
        (body.velocity.x * body.velocity.x + body.velocity.y * body.velocity.y)
            .squareRoot() * timestep
    }

    /// Swept collision against a horizontal bar: did the body's PATH cross the
    /// bar's plane between two frames, and where was it when it did?
    ///
    /// WHAT THIS IS AND IS NOT FOR, measured rather than assumed.
    ///
    /// It is tempting to justify this as tunnelling protection — a body moving
    /// faster than the bar is thick passing through with no frame of overlap.
    /// That was the first version of this comment and it was WRONG for this app:
    /// at the 15 deg/s speed cap a ball covers 0.25 deg per frame against a
    /// 0.6 deg paddle, so plain overlap testing would never miss. Tunnelling is
    /// prevented by the speed cap, and `travelPerFrameIsBounded` is the test
    /// that keeps it that way if someone later raises the ceiling.
    ///
    /// What the sweep actually buys is the CONTACT POSITION. A ball moving
    /// diagonally is meaningfully further along in x by the time the frame
    /// lands, so judging an edge hit by the post-frame x gets it wrong: a ball
    /// squarely over the paddle when it reached the plane, but past the edge one
    /// frame later, reads as a miss. Measured on a real edge case, the two
    /// methods disagree — and the user, who saw contact, is the one who would be
    /// told they missed.
    static func crossesBar(from previous: CGPoint, to current: CGPoint,
                           radius: Double,
                           barY: Double, barMinX: Double, barMaxX: Double) -> Bool {
        let previousEdge = previous.y + radius
        let currentEdge = current.y + radius
        // Only a downward crossing counts; a body already below the bar and
        // moving up is leaving, not arriving.
        guard previousEdge <= barY, currentEdge >= barY else { return false }

        // Where along its path did it reach the bar's plane? Interpolating gives
        // the x it actually had at contact, rather than the x it has now — which
        // at 12 pt per frame is a different answer near the paddle's edge.
        let span = currentEdge - previousEdge
        let fraction = span > 1e-9 ? (barY - previousEdge) / span : 0
        let contactX = previous.x + (current.x - previous.x) * fraction
        return contactX + radius >= barMinX && contactX - radius <= barMaxX
    }
}

/// Maps the staircase's value onto what the game actually does.
///
/// ONE MEASURED DIMENSION, NOT TWO. The catalogue describes these games as
/// "contrast ratio plus speed", and it would be easy to staircase both. That
/// would produce a threshold describing neither: a user could be at level 8
/// because the contrast is hard or because the speed is, and the number would
/// not say which. So the ratio is the measured dimension and speed rises with it
/// on a fixed schedule — the same schedule for every user, so it never varies
/// between sessions and cannot contaminate the threshold.
struct GameDifficulty: Sendable, Equatable {

    /// Fellow-eye contrast as a fraction of the actor's. This is the number the
    /// staircase moves, and the one that gets recorded.
    let contrastRatio: Double

    /// Contrast the actor (amblyopic eye) is always drawn at. Fixed, so the
    /// ratio is the only thing that varies.
    static let actorContrast: Double = 0.8

    /// Slowest and fastest the game runs, in degrees per second.
    static let slowestSpeed: Double = 5.0
    static let fastestSpeed: Double = GameField.maximumSpeedDegreesPerSecond

    /// Ratio at which speed stops rising. Beyond this the contrast alone carries
    /// the difficulty — piling more speed onto an already-hard ratio just makes
    /// the game unplayable rather than more sensitive.
    static let ratioAtFullSpeed: Double = 1.0

    var fellowContrast: Double {
        min(Self.actorContrast * contrastRatio, AnaglyphCompositor.maximumContrast)
    }

    /// Speed for this ratio, clamped to the pursuit ceiling at both ends.
    var speedDegreesPerSecond: Double {
        let progress = min(max(contrastRatio / Self.ratioAtFullSpeed, 0), 1)
        let speed = Self.slowestSpeed + (Self.fastestSpeed - Self.slowestSpeed) * progress
        return min(speed, GameField.maximumSpeedDegreesPerSecond)
    }

    /// Plain reading of a converged ratio, matching D5's bands so the two
    /// numbers mean the same thing to a user who sees both.
    static func interpretation(contrastRatio: Double) -> String {
        BalanceMeterExercise.interpretation(balanceRatio: contrastRatio)
    }
}
