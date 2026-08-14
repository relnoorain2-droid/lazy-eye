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

@Suite("Split Match")
struct SplitMatchTests {

    @Test("neither eye alone can pick the target out")
    func neitherEyeCanSolveItAlone() {
        // The premise of the exercise. Each eye sees only its own half of every
        // card, so the target must NOT be unique in either monocular view — if
        // it were, one eye would answer correctly every time and the trial would
        // measure nothing.
        let exercise = SplitMatchExercise()
        var generator = SeededGenerator(seed: 17)
        // Difficulties swept deterministically rather than drawn from the system
        // RNG. A `Double.random` here would make the test's coverage differ every
        // run, so a failure could vanish on a re-run — the exact trap that made
        // two Phase 9 tests flaky.
        for step in 0..<400 {
            let difficulty = 0.1 + Double(step % 20) * 0.1
            let trial = exercise.makeTrial(difficulty: difficulty,
                                           generator: &generator)
            let target = exercise.target(for: trial)
            let options = exercise.options(for: trial)

            let leftMatches = options.filter { $0.leftHalf == target.leftHalf }.count
            let rightMatches = options.filter { $0.rightHalf == target.rightHalf }.count
            #expect(leftMatches >= 2,
                    "the amblyopic eye saw a unique match and can answer alone")
            #expect(rightMatches >= 2,
                    "the fellow eye saw a unique match and can answer alone")
        }
    }

    @Test("exactly one option is the whole target")
    func exactlyOneCompleteMatch() {
        let exercise = SplitMatchExercise()
        var generator = SeededGenerator(seed: 23)
        for _ in 0..<300 {
            let trial = exercise.makeTrial(difficulty: 0.8, generator: &generator)
            let target = exercise.target(for: trial)
            let options = exercise.options(for: trial)
            let complete = options.indices.filter { options[$0] == target }
            #expect(complete.count == 1, "\(complete.count) options matched entirely")
            #expect(complete.first == trial.correctAnswer,
                    "the scored answer is not the matching card")
        }
    }

    @Test("every distractor matches on exactly one half")
    func distractorsMatchOnOneHalf() {
        // A distractor differing in BOTH halves can be eliminated with one eye,
        // which reduces the effective number of options and inflates the
        // guess rate above what the staircase assumes.
        let exercise = SplitMatchExercise()
        var generator = SeededGenerator(seed: 29)
        for _ in 0..<300 {
            let trial = exercise.makeTrial(difficulty: 1.2, generator: &generator)
            let target = exercise.target(for: trial)
            for (index, option) in exercise.options(for: trial).enumerated()
            where index != trial.correctAnswer {
                let matchesLeft = option.leftHalf == target.leftHalf
                let matchesRight = option.rightHalf == target.rightHalf
                #expect(matchesLeft != matchesRight,
                        "distractor \(index) matches on \(matchesLeft && matchesRight ? "both" : "neither") half")
            }
        }
    }

    @Test("no two options on screen are identical")
    func optionsAreDistinct() {
        // Two identical cards would make the trial unanswerable: both would be
        // correct and only one is scored so.
        let exercise = SplitMatchExercise()
        var generator = SeededGenerator(seed: 37)
        for _ in 0..<300 {
            let trial = exercise.makeTrial(difficulty: 1.5, generator: &generator)
            let options = exercise.options(for: trial)
            let keys = options.map { "\($0.leftHalf),\($0.rightHalf)" }
            #expect(Set(keys).count == keys.count, "duplicate cards on screen: \(keys)")
        }
    }

    @Test("the layout always has the full number of options")
    func layoutIsNeverShort() {
        let exercise = SplitMatchExercise()
        var generator = SeededGenerator(seed: 41)
        for _ in 0..<300 {
            let trial = exercise.makeTrial(difficulty: 2.0, generator: &generator)
            let wanted = Int(trial.payload.value("optionCount"))
            #expect(exercise.options(for: trial).count == wanted,
                    "asked for \(wanted) options")
        }
    }

    @Test("option count rises with difficulty and stays in bounds")
    func optionCountSchedule() {
        var previous = 0
        for ratio in stride(from: 0.0, through: 2.0, by: 0.1) {
            let count = SplitMatchExercise.optionCount(
                for: GameDifficulty(contrastRatio: ratio))
            #expect(count >= SplitMatchExercise.minimumOptions)
            #expect(count <= SplitMatchExercise.maximumOptions)
            #expect(count >= previous)
            previous = count
        }
    }

    @Test("chance level uses the easiest trial")
    func chanceUsesTheEasiestTrial() {
        #expect(SplitMatchExercise.descriptor.staircase.alternatives
                == SplitMatchExercise.minimumOptions)
    }

    @Test("the same seed reproduces the same options")
    func optionsAreDeterministic() {
        let exercise = SplitMatchExercise()
        var generator = SeededGenerator(seed: 53)
        let trial = exercise.makeTrial(difficulty: 1.0, generator: &generator)
        #expect(exercise.options(for: trial) == exercise.options(for: trial))
    }
}

@Suite("Peekaboo and Colour Sort")
struct PeekabooAndSortTests {

    private static let smallestPointsPerDegree: Double = 29.8

    // MARK: G3 Peekaboo

    @Test("burrows are comfortably tappable on the smallest screen")
    func burrowsAreTappable() {
        let points = PeekabooExercise.burrowDegrees * Self.smallestPointsPerDegree
        #expect(points >= 44, "a burrow is \(points) pt on an iPhone SE")
    }

    @Test("the burrow grid fits the field without overlapping")
    func burrowsFitTheField() {
        let radius = PeekabooExercise.burrowDegrees / 2
        for index in 0..<PeekabooExercise.burrowCount {
            let centre = PeekabooExercise.centre(ofBurrow: index)
            #expect(centre.x - radius >= -1e-9)
            #expect(centre.x + radius <= GameField.widthDegrees + 1e-9)
            #expect(centre.y - radius >= -1e-9)
            #expect(centre.y + radius <= GameField.heightDegrees + 1e-9)
        }
        // And no two burrows overlap.
        for a in 0..<PeekabooExercise.burrowCount {
            for b in (a + 1)..<PeekabooExercise.burrowCount {
                let p = PeekabooExercise.centre(ofBurrow: a)
                let q = PeekabooExercise.centre(ofBurrow: b)
                let distance = ((p.x - q.x) * (p.x - q.x)
                                + (p.y - q.y) * (p.y - q.y)).squareRoot()
                #expect(distance >= PeekabooExercise.burrowDegrees,
                        "burrows \(a) and \(b) overlap")
            }
        }
    }

    @Test("the creature is always up long enough for a small child")
    func creatureIsVisibleLongEnough() {
        for ratio in stride(from: 0.0, through: 2.0, by: 0.1) {
            let seconds = PeekabooExercise.secondsVisible(
                for: GameDifficulty(contrastRatio: ratio))
            #expect(seconds >= PeekabooExercise.shortestVisible - 1e-9,
                    "ratio \(ratio) gives \(seconds) s")
            #expect(seconds <= PeekabooExercise.longestVisible + 1e-9)
        }
    }

    @Test("the creature's time on screen shortens as difficulty rises")
    func visibleTimeShortens() {
        let easy = PeekabooExercise.secondsVisible(for: GameDifficulty(contrastRatio: 0.1))
        let hard = PeekabooExercise.secondsVisible(for: GameDifficulty(contrastRatio: 1.0))
        #expect(easy > hard)
    }

    @Test("every burrow is used")
    func everyBurrowIsUsed() {
        let exercise = PeekabooExercise()
        var generator = SeededGenerator(seed: 63)
        var seen: Set<Int> = []
        for _ in 0..<400 {
            seen.insert(exercise.burrow(
                for: exercise.makeTrial(difficulty: 0.4, generator: &generator)))
        }
        #expect(seen.count == PeekabooExercise.burrowCount,
                "only \(seen.count) of \(PeekabooExercise.burrowCount) burrows appeared")
    }

    @Test("a tap on the right burrow counts, one elsewhere does not")
    func tapHitsTheRightBurrow() {
        let centre = PeekabooExercise.centre(ofBurrow: 0)
        #expect(PeekabooExercise.tapped(at: centre, burrow: 0))
        #expect(!PeekabooExercise.tapped(at: PeekabooExercise.centre(ofBurrow: 5),
                                         burrow: 0))
    }

    // MARK: G6 Colour Sort

    @Test("matching and non-matching trials are evenly balanced")
    func answersAreBalanced() {
        // Unbalanced and a user could beat chance by always saying "different",
        // which the staircase would read as performance.
        let exercise = ColourSortExercise()
        var generator = SeededGenerator(seed: 67)
        var same = 0
        let total = 1_000
        for _ in 0..<total {
            let trial = exercise.makeTrial(difficulty: 0.5, generator: &generator)
            if trial.correctAnswer == ColourSortExercise.Answer.same.rawValue { same += 1 }
        }
        let ratio = Double(same) / Double(total)
        #expect(abs(ratio - 0.5) < 0.08, "\(Int(ratio * 100))% of trials were matches")
    }

    @Test("the marks agree with the scored answer")
    func marksMatchTheAnswer() {
        let exercise = ColourSortExercise()
        var generator = SeededGenerator(seed: 71)
        for _ in 0..<1_000 {
            let trial = exercise.makeTrial(difficulty: 0.5, generator: &generator)
            let identical = exercise.leftMark(for: trial) == exercise.rightMark(for: trial)
            let scoredSame = trial.correctAnswer == ColourSortExercise.Answer.same.rawValue
            #expect(identical == scoredSame,
                    "marks \(exercise.leftMark(for: trial))/\(exercise.rightMark(for: trial)) scored as \(scoredSame ? "same" : "different")")
        }
    }

    @Test("marks stay inside the available set")
    func marksAreInRange() {
        let exercise = ColourSortExercise()
        var generator = SeededGenerator(seed: 73)
        for _ in 0..<500 {
            let trial = exercise.makeTrial(difficulty: 1.0, generator: &generator)
            #expect((0..<ColourSortExercise.markCount).contains(exercise.leftMark(for: trial)))
            #expect((0..<ColourSortExercise.markCount).contains(exercise.rightMark(for: trial)))
        }
    }

    @Test("every mark value is used on both sides")
    func marksCoverTheSet() {
        let exercise = ColourSortExercise()
        var generator = SeededGenerator(seed: 79)
        var lefts: Set<Int> = []
        var rights: Set<Int> = []
        for _ in 0..<600 {
            let trial = exercise.makeTrial(difficulty: 1.0, generator: &generator)
            lefts.insert(exercise.leftMark(for: trial))
            rights.insert(exercise.rightMark(for: trial))
        }
        #expect(lefts.count == ColourSortExercise.markCount)
        #expect(rights.count == ColourSortExercise.markCount)
    }

    @Test("both new games report on the balance scale")
    func newGamesShareTheScale() {
        let reference = BalanceMeterExercise.descriptor.staircase
        for staircase in [PeekabooExercise.descriptor.staircase,
                          ColourSortExercise.descriptor.staircase] {
            #expect(staircase.polarity == reference.polarity)
            #expect(staircase.hardestValue == reference.hardestValue)
            #expect(staircase.easiestValue == reference.easiestValue)
        }
    }
}

@Suite("Depth Steps and Hold the Fusion")
struct FusionExerciseTests {

    // MARK: D7 — the catch trials are the whole safeguard

    @Test("catch trials appear, and their honest answer is 'two'")
    func catchTrialsExist() {
        // Without these, a user answering "I see one" every time walks the
        // staircase to the easiest end and is reported as having an excellent
        // fusion range. Nothing in the data would distinguish them from someone
        // who genuinely has one.
        let exercise = DepthStepsExercise()
        var generator = SeededGenerator(seed: 91)
        var catches = 0
        let total = 1_000
        for _ in 0..<total {
            let trial = exercise.makeTrial(difficulty: 20, generator: &generator)
            if exercise.isCatchTrial(trial) {
                catches += 1
                #expect(trial.correctAnswer == DepthStepsExercise.Answer.two.rawValue,
                        "a catch trial must score 'two' as correct")
                #expect(trial.payload.value("disparityArcmin")
                        == DepthStepsExercise.catchDisparityArcminutes)
            } else {
                #expect(trial.correctAnswer == DepthStepsExercise.Answer.one.rawValue)
                #expect(trial.payload.value("disparityArcmin") == 20)
            }
        }
        let share = Double(catches) / Double(total)
        let expected = 1.0 / Double(DepthStepsExercise.catchTrialInterval)
        #expect(abs(share - expected) < 0.06,
                "\(Int(share * 100))% were catch trials, expected about \(Int(expected * 100))%")
    }

    @Test("always answering 'one' fails every catch trial")
    func blindAnsweringIsCaught() {
        // The property that makes the metric falsifiable, stated as a test.
        let exercise = DepthStepsExercise()
        var generator = SeededGenerator(seed: 93)
        var caught = 0
        for _ in 0..<500 {
            let trial = exercise.makeTrial(difficulty: 30, generator: &generator)
            let blindAnswer = DepthStepsExercise.Answer.one.rawValue
            if trial.correctAnswer != blindAnswer { caught += 1 }
        }
        #expect(caught > 50,
                "only \(caught) of 500 blind answers were caught — too few to move the staircase")
    }

    @Test("the catch disparity is far beyond any human fusion range")
    func catchDisparityIsUnfusable() {
        #expect(DepthStepsExercise.catchDisparityArcminutes
                > DepthStepsExercise.descriptor.staircase.hardestValue * 2,
                "a catch trial a user could fuse would punish honest answering")
    }

    @Test("both crossed and uncrossed disparities are presented")
    func bothDepthDirectionsAppear() {
        let exercise = DepthStepsExercise()
        var generator = SeededGenerator(seed: 97)
        var directions: Set<Int> = []
        for _ in 0..<300 {
            let trial = exercise.makeTrial(difficulty: 25, generator: &generator)
            directions.insert(Int(trial.payload.value("crossed")))
        }
        #expect(directions.count == 2,
                "base-in and base-out must both be tested")
    }

    @Test("D7 inherits the one-point disparity floor")
    func depthStepsRespectsThePixelGrid() throws {
        // Same failure as D6 would have had: below a point of shift there is no
        // disparity on screen, only two identical images.
        let limit = try #require(DepthStepsExercise.descriptor.staircase.renderLimit)
        let profile = CalibrationProfile(screenPointsPerCM: 56.9,
                                         screenSizeUserVerified: true,
                                         viewingDistanceCM: 30)
        let floor = try #require(limit.hardestRenderableValue(for: profile))
        #expect(abs(floor - 60.0 / profile.points(forDegrees: 1.0)) < 0.05)
    }

    // MARK: D10 — the answer demonstrates the hold

    @Test("the hold is demonstrated by naming a shape, not by a held button")
    func holdIsDemonstratedNotAsserted() {
        // A "hold this button while fused" design is unfalsifiable: holding it
        // throughout produces a perfect score. Naming a shape that is only
        // identifiable while fused makes the answer the evidence.
        let exercise = HoldTheFusionExercise()
        var generator = SeededGenerator(seed: 99)
        for _ in 0..<200 {
            let trial = exercise.makeTrial(difficulty: 6, generator: &generator)
            #expect(StereogramParameters.Shape(rawValue: trial.correctAnswer) != nil,
                    "the answer must be a nameable shape")
        }
        #expect(HoldTheFusionExercise.descriptor.staircase.alternatives == 4,
                "four shapes means a guesser is right one time in four, which the staircase corrects for")
    }

    @Test("the hold period is what varies, not the disparity")
    func onlyDurationVaries() {
        // Letting the disparity vary too would make the threshold a mixture of
        // fusion range and fusion stamina, describing neither.
        let exercise = HoldTheFusionExercise()
        let calibration = CalibrationProfile(screenPointsPerCM: 47.2,
                                             screenSizeUserVerified: true,
                                             viewingDistanceCM: 50)
        var generator = SeededGenerator(seed: 103)
        var disparities: Set<Double> = []
        for seconds in [2.0, 6.0, 12.0, 20.0] {
            let trial = exercise.makeTrial(difficulty: seconds, generator: &generator)
            #expect(exercise.holdSeconds(for: trial) == seconds)
            disparities.insert(exercise.parameters(for: trial, calibration: calibration)
                .disparityArcminutes)
        }
        #expect(disparities.count == 1,
                "the disparity moved between trials: \(disparities)")
    }

    @Test("all four shapes are used")
    func shapesVary() {
        let exercise = HoldTheFusionExercise()
        var generator = SeededGenerator(seed: 107)
        var shapes: Set<Int> = []
        for _ in 0..<400 {
            shapes.insert(exercise.makeTrial(difficulty: 5, generator: &generator)
                .correctAnswer)
        }
        #expect(shapes.count == 4)
    }

    @Test("longer holds are the harder end of the staircase")
    func longerIsHarder() {
        #expect(HoldTheFusionExercise.descriptor.staircase.polarity == .higherIsHarder)
        #expect(HoldTheFusionExercise.descriptor.staircase.hardestValue
                > HoldTheFusionExercise.descriptor.staircase.easiestValue)
    }

    @Test("neither interpretation claims a clinical finding")
    func interpretationsStayHonest() {
        for value in [1.0, 5.0, 12.0, 25.0, 60.0, 150.0] {
            for text in [DepthStepsExercise.interpretation(disparityArcminutes: value),
                         HoldTheFusionExercise.interpretation(holdSeconds: value)] {
                #expect(!text.isEmpty)
                let lowered = text.lowercased()
                for phrase in ["normal", "diagnos", "healthy", "abnormal"] {
                    #expect(!lowered.contains(phrase), "\"\(phrase)\" in \"\(text)\"")
                }
            }
        }
    }
}
