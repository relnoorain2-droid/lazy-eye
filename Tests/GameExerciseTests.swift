//
//  GameExerciseTests.swift
//
//  D3 Stack Drop, G1 Balloon Pop, G2 Sky Catch and G8 Space Dodge.
//
//  Both have a failure mode that looks like healthy play. If a balloon can never
//  escape, the trial never ends in a miss, the staircase only ever gets
//  successes, and it climbs until the balloon is invisible — with nothing on
//  screen looking wrong. If a column is smaller than a fingertip, misses are
//  motor rather than visual and the app reads them as suppression.
//

import Testing
import Foundation
import CoreGraphics
@testable import Amblyo

@Suite("Stack Drop")
struct StackDropTests {

    private static let smallestPointsPerDegree: Double = 29.8   // iPhone SE at 30 cm

    @Test("a column is at least Apple's minimum touch target on the smallest screen")
    func columnsClearTheTouchMinimum() {
        // Eight columns gives 33 pt here, under the 44 pt minimum. A user missing
        // a 33 pt column misses it with their thumb, and the app would record
        // that as a suppression failure and make the exercise easier.
        let columnPoints = StackDropExercise.cellDegrees * Self.smallestPointsPerDegree
        #expect(columnPoints >= 44,
                "a column is \(columnPoints) pt on an iPhone SE")
    }

    @Test("the grid fits the field exactly, with no dead strip")
    func gridFitsTheField() {
        let width = Double(StackDropExercise.columns) * StackDropExercise.cellDegrees
        #expect(abs(width - GameField.widthDegrees) < 1e-9)
        let height = Double(StackDropExercise.rows) * StackDropExercise.cellDegrees
        #expect(height <= GameField.heightDegrees + 1e-9)
    }

    @Test("a piece is always aimable, at every difficulty")
    func dropIsSlowEnoughToAim() {
        // The shared ramp reaches 15 deg/s, which crosses the field in 0.8 s —
        // reaction time, not fusion. D3 caps at 8 deg/s.
        for ratio in stride(from: 0.1, through: 2.0, by: 0.1) {
            let seconds = StackDropExercise.dropSeconds(
                for: GameDifficulty(contrastRatio: ratio))
            #expect(seconds >= 1.4,
                    "ratio \(ratio) drops in \(seconds) s, too fast to aim")
        }
    }

    @Test("drop speed still rises with difficulty below the cap")
    func dropSpeedRises() {
        let easy = StackDropExercise.dropSpeed(for: GameDifficulty(contrastRatio: 0.1))
        let hard = StackDropExercise.dropSpeed(for: GameDifficulty(contrastRatio: 1.0))
        #expect(easy < hard, "capping must not flatten the ramp entirely")
        #expect(hard <= StackDropExercise.maximumDropSpeed + 1e-9)
    }

    @Test("column lookup and centre are inverse of each other")
    func columnRoundTrips() {
        for column in 0..<StackDropExercise.columns {
            let centre = StackDropExercise.centreX(ofColumn: column)
            #expect(StackDropExercise.column(atX: centre) == column)
        }
    }

    @Test("a position outside the grid clamps rather than crashing")
    func columnLookupClamps() {
        #expect(StackDropExercise.column(atX: -5) == 0)
        #expect(StackDropExercise.column(atX: GameField.widthDegrees + 5)
                == StackDropExercise.columns - 1)
        // Exactly on the right edge is the last column, not one past it.
        #expect(StackDropExercise.column(atX: GameField.widthDegrees)
                == StackDropExercise.columns - 1)
    }

    @Test("the piece never starts above its target")
    func startNeverEqualsTarget() {
        // Starting on target means the correct answer is "do nothing", which
        // measures whether the user left their finger still.
        let exercise = StackDropExercise()
        var generator = SeededGenerator(seed: 4)
        for _ in 0..<500 {
            let trial = exercise.makeTrial(difficulty: 0.4, generator: &generator)
            #expect(exercise.startColumn(for: trial) != exercise.targetColumn(for: trial))
        }
    }

    @Test("every column is used as a target")
    func targetsCoverTheGrid() {
        let exercise = StackDropExercise()
        var generator = SeededGenerator(seed: 12)
        var targets: Set<Int> = []
        for _ in 0..<600 {
            targets.insert(exercise.targetColumn(
                for: exercise.makeTrial(difficulty: 0.4, generator: &generator)))
        }
        #expect(targets.count == StackDropExercise.columns,
                "only \(targets.count) of \(StackDropExercise.columns) columns were ever the target")
    }

    @Test("targets and starts are always inside the grid")
    func trialsStayInBounds() {
        let exercise = StackDropExercise()
        var generator = SeededGenerator(seed: 19)
        for _ in 0..<500 {
            let trial = exercise.makeTrial(difficulty: 0.7, generator: &generator)
            #expect((0..<StackDropExercise.columns).contains(exercise.targetColumn(for: trial)))
            #expect((0..<StackDropExercise.columns).contains(exercise.startColumn(for: trial)))
            #expect(trial.correctAnswer == exercise.targetColumn(for: trial),
                    "the scored answer must be the target column")
        }
    }

    @Test("chance level matches the number of columns")
    func alternativesMatchColumns() {
        // The staircase's guess correction uses this. Six columns and a stated
        // two alternatives would make the app think a guesser was performing.
        #expect(StackDropExercise.descriptor.staircase.alternatives
                == StackDropExercise.columns)
    }
}

@Suite("Balloon Pop")
struct BalloonPopTests {

    private static let smallestPointsPerDegree: Double = 29.8

    private var field: GameField {
        GameField(pointsPerDegree: Self.smallestPointsPerDegree)
    }

    @Test("a balloon is bigger than Apple's minimum touch target everywhere")
    func balloonClearsTheTouchMinimum() {
        let points = BalloonPopExercise.balloonDegrees * Self.smallestPointsPerDegree
        #expect(points >= 44, "a balloon is \(points) pt on an iPhone SE")
    }

    @Test("a rising balloon escapes through the top and ends the trial")
    func balloonEscapes() {
        // THE BUG THIS EXISTS FOR: `GamePhysics.step` bounces off the top by
        // default. Left that way, the balloon rebounds and drifts forever, the
        // trial never ends in a miss, and the staircase climbs until every
        // balloon is invisible — while the game looks perfectly healthy.
        let exercise = BalloonPopExercise()
        var generator = SeededGenerator(seed: 3)
        let trial = exercise.makeTrial(difficulty: 0.3, generator: &generator)
        var body = exercise.launch(for: trial)

        var escaped = false
        for _ in 0..<(60 * 20) {
            body = GamePhysics.step(body, in: field, bounceBottom: true, bounceTop: false)
            if BalloonPopExercise.escaped(body) { escaped = true; break }
        }
        #expect(escaped, "the balloon never left the field, so a miss is impossible")
    }

    @Test("with the top closed the balloon is trapped — the defect, demonstrated")
    func topWallTrapsTheBalloon() {
        let exercise = BalloonPopExercise()
        var generator = SeededGenerator(seed: 3)
        let trial = exercise.makeTrial(difficulty: 0.3, generator: &generator)
        var body = exercise.launch(for: trial)

        for _ in 0..<(60 * 20) {
            body = GamePhysics.step(body, in: field)   // default: top bounces
        }
        #expect(!BalloonPopExercise.escaped(body),
                "if this passes with the top open too, the test proves nothing")
    }

    @Test("a balloon is on screen long enough for a small child")
    func balloonIsSlowEnough() {
        for ratio in stride(from: 0.1, through: 2.0, by: 0.1) {
            let seconds = BalloonPopExercise.secondsOnScreen(
                for: GameDifficulty(contrastRatio: ratio))
            #expect(seconds >= 2.0,
                    "ratio \(ratio) gives a child \(seconds) s to react")
        }
    }

    @Test("a tap on the balloon pops it")
    func directTapPops() {
        let balloon = GamePhysics.Body(position: CGPoint(x: 4, y: 6),
                                       velocity: .zero,
                                       size: BalloonPopExercise.balloonDegrees)
        #expect(BalloonPopExercise.popped(tapAt: CGPoint(x: 4, y: 6), balloon: balloon))
    }

    @Test("a near miss still pops, because this measures seeing not pointing")
    func nearTapPops() {
        let balloon = GamePhysics.Body(position: CGPoint(x: 4, y: 6),
                                       velocity: .zero,
                                       size: BalloonPopExercise.balloonDegrees)
        // Just outside the balloon's edge, inside the forgiving reach.
        let justOutside = CGPoint(x: 4 + balloon.radius * 1.1, y: 6)
        #expect(BalloonPopExercise.popped(tapAt: justOutside, balloon: balloon),
                "a four-year-old's tap lands near the target, not on it")
    }

    @Test("a tap on the other side of the screen does not pop")
    func distantTapDoesNotPop() {
        let balloon = GamePhysics.Body(position: CGPoint(x: 4, y: 6),
                                       velocity: .zero,
                                       size: BalloonPopExercise.balloonDegrees)
        #expect(!BalloonPopExercise.popped(tapAt: CGPoint(x: 8, y: 2), balloon: balloon),
                "tapping anywhere would make every trial a success")
    }

    @Test("balloons launch inside the field and rise")
    func launchesAreLegal() {
        let exercise = BalloonPopExercise()
        var generator = SeededGenerator(seed: 21)
        for _ in 0..<300 {
            let trial = exercise.makeTrial(difficulty: 0.5, generator: &generator)
            let body = exercise.launch(for: trial)
            #expect(body.position.x >= body.radius - 1e-9)
            #expect(body.position.x <= GameField.widthDegrees - body.radius + 1e-9)
            #expect(body.velocity.y < 0, "the balloon must move up, not down")
        }
    }

    @Test("launch positions vary across the width")
    func launchesVary() {
        let exercise = BalloonPopExercise()
        var generator = SeededGenerator(seed: 8)
        var buckets: Set<Int> = []
        for _ in 0..<300 {
            let trial = exercise.makeTrial(difficulty: 0.5, generator: &generator)
            buckets.insert(Int(exercise.launch(for: trial).position.x))
        }
        #expect(buckets.count >= 5,
                "balloons always appeared in the same place, so a child can pre-place a finger")
    }

    @Test("under-fives can reach this exercise and Bounce is held back")
    func ageGatingIsRightWayRound() {
        #expect(BalloonPopExercise.descriptor.minimumAgeGroup == .underFive)
        #expect(BounceExercise.descriptor.minimumAgeGroup == .fiveToTwelve,
                "Bounce needs a dragged paddle and sustained tracking")
    }

    @Test("the games share the balance scale with the measurement exercise")
    func gamesShareTheScale() {
        for game in [StackDropExercise.descriptor.staircase,
                     BalloonPopExercise.descriptor.staircase,
                     BounceExercise.descriptor.staircase] {
            #expect(game.polarity == BalanceMeterExercise.descriptor.staircase.polarity)
            #expect(game.hardestValue == BalanceMeterExercise.descriptor.staircase.hardestValue)
            #expect(game.easiestValue == BalanceMeterExercise.descriptor.staircase.easiestValue)
        }
    }
}

@Suite("Sky Catch and Space Dodge")
struct CatchAndDodgeTests {

    private static let smallestPointsPerDegree: Double = 29.8

    // MARK: Touch and timing floors

    @Test("the fruit clears Apple's touch minimum on the smallest screen")
    func fruitIsBigEnough() {
        let points = SkyCatchExercise.fruitDegrees * Self.smallestPointsPerDegree
        #expect(points >= 44, "fruit is \(points) pt on an iPhone SE")
    }

    @Test("the under-five game gives a child time to react")
    func skyCatchIsSlowEnough() {
        for ratio in stride(from: 0.1, through: 2.0, by: 0.1) {
            let seconds = SkyCatchExercise.secondsToFall(
                for: GameDifficulty(contrastRatio: ratio))
            #expect(seconds >= 2.0, "ratio \(ratio) gives \(seconds) s")
        }
    }

    @Test("the older-children game is faster but still trackable")
    func spaceDodgeIsFasterButBounded() {
        let kid = SkyCatchExercise.fallSpeed(for: GameDifficulty(contrastRatio: 2.0))
        let older = SpaceDodgeExercise.fallSpeed(for: GameDifficulty(contrastRatio: 2.0))
        #expect(older > kid, "the 8+ game should not run at under-five speed")
        #expect(older <= GameField.maximumSpeedDegreesPerSecond,
                "and must still be inside the smooth-pursuit ceiling")
        for ratio in stride(from: 0.1, through: 2.0, by: 0.1) {
            let seconds = SpaceDodgeExercise.secondsToFall(
                for: GameDifficulty(contrastRatio: ratio))
            #expect(seconds >= 1.2, "ratio \(ratio) gives \(seconds) s to steer clear")
        }
    }

    // MARK: The scoring is opposite, on purpose

    @Test("catching scores a success and being struck scores a failure")
    func scoringIsOppositeBetweenTheTwoGames() {
        // Both exercises call a correct trial "1". What differs is which EVENT
        // produces it: contact in Sky Catch, avoiding contact in Space Dodge.
        // Wire them the same way round and Space Dodge would train a user to
        // fly into the rocks, with the staircase faithfully finding the contrast
        // at which they hit four in five.
        let centre = GameField.widthDegrees / 2

        let fruitRadius = SkyCatchExercise.fruitDegrees / 2
        #expect(SkyCatchExercise.caught(
            previous: CGPoint(x: centre, y: SkyCatchExercise.basketY - fruitRadius - 0.2),
            current: CGPoint(x: centre, y: SkyCatchExercise.basketY - fruitRadius + 0.2),
            basketCentreX: centre))

        let rockRadius = SpaceDodgeExercise.rockDegrees / 2
        #expect(SpaceDodgeExercise.struckShip(
            previous: CGPoint(x: centre, y: SpaceDodgeExercise.shipY - rockRadius - 0.2),
            current: CGPoint(x: centre, y: SpaceDodgeExercise.shipY - rockRadius + 0.2),
            shipCentreX: centre))
    }

    @Test("a rock well away from the ship does not strike it")
    func wideRockMisses() {
        let shipCentre = 3.0
        let radius = SpaceDodgeExercise.rockDegrees / 2
        let x = shipCentre + SpaceDodgeExercise.shipWidthDegrees / 2
            + SpaceDodgeExercise.rockDegrees + 0.5
        #expect(!SpaceDodgeExercise.struckShip(
            previous: CGPoint(x: x, y: SpaceDodgeExercise.shipY - radius - 0.2),
            current: CGPoint(x: x, y: SpaceDodgeExercise.shipY - radius + 0.2),
            shipCentreX: shipCentre))
    }

    @Test("a fruit that reaches the bottom is a miss")
    func fruitCanBeMissed() {
        let body = GamePhysics.Body(
            position: CGPoint(x: 4, y: GameField.heightDegrees + 2),
            velocity: .zero,
            size: SkyCatchExercise.fruitDegrees)
        #expect(SkyCatchExercise.fellPast(body))
    }

    @Test("a rock that reaches the bottom is a successful dodge")
    func rockCanPassSafely() {
        let body = GamePhysics.Body(
            position: CGPoint(x: 4, y: GameField.heightDegrees + 2),
            velocity: .zero,
            size: SpaceDodgeExercise.rockDegrees)
        #expect(SpaceDodgeExercise.passedSafely(body))
    }

    // MARK: Trials

    @Test("both games drop things inside the field, moving down")
    func dropsAreLegal() {
        var generator = SeededGenerator(seed: 61)
        let catcher = SkyCatchExercise()
        let dodger = SpaceDodgeExercise()
        for _ in 0..<200 {
            let catchTrial = catcher.makeTrial(difficulty: 0.4, generator: &generator)
            let fruit = catcher.drop(for: catchTrial)
            #expect(fruit.position.x >= fruit.radius - 1e-9)
            #expect(fruit.position.x <= GameField.widthDegrees - fruit.radius + 1e-9)
            #expect(fruit.velocity.y > 0)

            let dodgeTrial = dodger.makeTrial(difficulty: 0.4, generator: &generator)
            let rock = dodger.rock(for: dodgeTrial)
            #expect(rock.position.x >= rock.radius - 1e-9)
            #expect(rock.position.x <= GameField.widthDegrees - rock.radius + 1e-9)
            #expect(rock.velocity.y > 0)
        }
    }

    @Test("drop positions vary across the width in both games")
    func dropsVary() {
        var generator = SeededGenerator(seed: 88)
        let catcher = SkyCatchExercise()
        var buckets: Set<Int> = []
        for _ in 0..<300 {
            let trial = catcher.makeTrial(difficulty: 0.4, generator: &generator)
            buckets.insert(Int(catcher.drop(for: trial).position.x))
        }
        #expect(buckets.count >= 5,
                "fruit always fell in the same place, so the basket can just sit there")
    }

    @Test("every game reports on the balance meter's scale")
    func allGamesShareTheScale() {
        let reference = BalanceMeterExercise.descriptor.staircase
        for staircase in [SkyCatchExercise.descriptor.staircase,
                          SpaceDodgeExercise.descriptor.staircase] {
            #expect(staircase.polarity == reference.polarity)
            #expect(staircase.hardestValue == reference.hardestValue)
            #expect(staircase.easiestValue == reference.easiestValue)
        }
    }

    @Test("the two games are on the games track, not the dichoptic one")
    func gamesAreLabelledAsGames() {
        // They ARE dichoptic exercises, but the Train screen groups them as
        // games so a parent looking for something a child will tolerate can
        // find them. The evidence tier stays honest at A.
        for descriptor in [SkyCatchExercise.descriptor, SpaceDodgeExercise.descriptor,
                           BalloonPopExercise.descriptor] {
            #expect(descriptor.track == .game)
            #expect(descriptor.evidenceTier == .a)
        }
    }
}

@Suite("Hidden Half")
struct HiddenHalfTests {

    private static let smallestPointsPerDegree: Double = 29.8

    @Test("items clear Apple's touch minimum")
    func itemsAreTappable() {
        let points = HiddenHalfExercise.itemDegrees * Self.smallestPointsPerDegree
        #expect(points >= 44, "an item is \(points) pt on an iPhone SE")
    }

    @Test("every layout places the FULL number of items the difficulty called for")
    func layoutNeverComesUpShort() {
        // THE M12 DEFECT, GUARDED. In Phase 6, Find It asked for 40 items on a
        // field that could hold 27; the sampler quietly returned fewer, so
        // difficulty stopped rising while the staircase kept climbing and the
        // reported threshold was for a display that never existed.
        let exercise = HiddenHalfExercise()
        var generator = SeededGenerator(seed: 101)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 2.0, generator: &generator)
            let wanted = Int(trial.payload.value("itemCount"))
            let placed = exercise.layout(for: trial)
            #expect(placed.count == wanted,
                    "asked for \(wanted) items, placed \(placed.count)")
        }
    }

    @Test("placed items never overlap")
    func itemsAreSeparated() {
        let exercise = HiddenHalfExercise()
        var generator = SeededGenerator(seed: 55)
        for _ in 0..<50 {
            let trial = exercise.makeTrial(difficulty: 1.5, generator: &generator)
            let items = exercise.layout(for: trial)
            for (i, a) in items.enumerated() {
                for b in items[(i + 1)...] {
                    let dx = a.position.x - b.position.x
                    let dy = a.position.y - b.position.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    #expect(distance >= HiddenHalfExercise.minimumSeparationDegrees - 1e-9,
                            "two items are \(distance) deg apart")
                }
            }
        }
    }

    @Test("items stay inside the field")
    func itemsStayInBounds() {
        let exercise = HiddenHalfExercise()
        var generator = SeededGenerator(seed: 71)
        let radius = HiddenHalfExercise.itemDegrees / 2
        for _ in 0..<50 {
            let trial = exercise.makeTrial(difficulty: 1.0, generator: &generator)
            for item in exercise.layout(for: trial) {
                #expect(item.position.x >= radius - 1e-9)
                #expect(item.position.x <= GameField.widthDegrees - radius + 1e-9)
                #expect(item.position.y >= radius - 1e-9)
                #expect(item.position.y <= GameField.heightDegrees - radius + 1e-9)
            }
        }
    }

    @Test("exactly one item is the target, and it is the scored answer")
    func exactlyOneTarget() {
        let exercise = HiddenHalfExercise()
        var generator = SeededGenerator(seed: 33)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 0.8, generator: &generator)
            let items = exercise.layout(for: trial)
            let targets = items.indices.filter { items[$0].isTarget }
            #expect(targets.count == 1, "\(targets.count) items had both marks")
            #expect(targets.first == trial.correctAnswer,
                    "the scored answer is not the item carrying both marks")
        }
    }

    @Test("neither eye alone can identify the target")
    func neitherEyeCanSolveItAlone() {
        // The whole premise. If only one item had a ring, the amblyopic eye
        // would find the target by itself; if only one had a dot, the fellow eye
        // would. Both monocular views must contain SEVERAL candidates.
        let exercise = HiddenHalfExercise()
        var generator = SeededGenerator(seed: 44)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 1.0, generator: &generator)
            let items = exercise.layout(for: trial)
            let ringed = items.filter(\.hasRing).count
            let dotted = items.filter(\.hasDot).count
            #expect(ringed >= 2, "only \(ringed) item(s) had a ring — one eye solves it")
            #expect(dotted >= 2, "only \(dotted) item(s) had a dot — one eye solves it")
        }
    }

    @Test("item count rises with difficulty and stays inside its bounds")
    func itemCountSchedule() {
        var previous = 0
        for ratio in stride(from: 0.0, through: 2.0, by: 0.1) {
            let count = HiddenHalfExercise.itemCount(
                for: GameDifficulty(contrastRatio: ratio))
            #expect(count >= HiddenHalfExercise.minimumItems)
            #expect(count <= HiddenHalfExercise.maximumItems)
            #expect(count >= previous, "the count must never fall as difficulty rises")
            previous = count
        }
    }

    @Test("chance level is set by the EASIEST trial, not the average")
    func chanceLevelUsesTheWorstCase() {
        // With 4 items a guesser is right 25% of the time and with 12 only 8%.
        // The staircase takes one `alternatives`, so it has to be the easiest
        // trial's count or a lucky guesser reads as a performer.
        #expect(HiddenHalfExercise.descriptor.staircase.alternatives
                == HiddenHalfExercise.minimumItems)
    }

    @Test("a tap on empty space selects nothing")
    func tapOnEmptySpaceIsIgnored() {
        // Scoring a stray tap would make the threshold partly a measure of
        // dexterity rather than of vision.
        let items = [HiddenHalfExercise.Item(position: CGPoint(x: 2, y: 2),
                                             hasRing: true, hasDot: true)]
        #expect(HiddenHalfExercise.item(at: CGPoint(x: 7, y: 9), in: items) == nil)
    }

    @Test("a tap on an item selects that item")
    func tapSelectsTheItem() {
        let items = [
            HiddenHalfExercise.Item(position: CGPoint(x: 2, y: 2), hasRing: true, hasDot: false),
            HiddenHalfExercise.Item(position: CGPoint(x: 6, y: 8), hasRing: true, hasDot: true),
        ]
        #expect(HiddenHalfExercise.item(at: CGPoint(x: 6, y: 8), in: items) == 1)
        #expect(HiddenHalfExercise.item(at: CGPoint(x: 2, y: 2), in: items) == 0)
    }

    @Test("the same seed reproduces the same layout")
    func layoutIsDeterministic() {
        let exercise = HiddenHalfExercise()
        var generator = SeededGenerator(seed: 9)
        let trial = exercise.makeTrial(difficulty: 1.0, generator: &generator)
        #expect(exercise.layout(for: trial) == exercise.layout(for: trial),
                "a session must replay exactly from its seed")
    }
}
