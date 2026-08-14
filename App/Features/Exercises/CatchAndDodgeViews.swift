//
//  CatchAndDodgeViews.swift
//
//  G2 Sky Catch and G8 Space Dodge share a screen: one falling body, one bar
//  the finger controls, one Canvas compositing both eyes. The only differences
//  are which layer each element belongs to and what counts as success — so they
//  share a view and pass those in, rather than being copied and edited.
//
//  WHY THE SHARED VIEW TAKES THE LAYERS AS PARAMETERS
//  Sky Catch puts the falling fruit in the amblyopic eye; Space Dodge puts the
//  falling rock there and the SHIP in the fellow eye. If that were hardcoded per
//  copy, the two would drift and one of them would eventually end up assigning
//  both elements to the same eye — which plays perfectly and trains nothing.
//  Making it a parameter means the difference is stated once, in one line, where
//  it can be read.
//
//  docs/03-EXERCISE-CATALOG.md G2, G8.
//

import SwiftUI

/// One falling body, one draggable bar. Used by both games.
@MainActor
struct FallingObjectGameView: View {

    struct Configuration {
        let icon: String
        let instructions: String
        /// Body size, bar size and the bar's line, all in degrees.
        let bodyDegrees: Double
        let barWidthDegrees: Double
        let barThicknessDegrees: Double
        let barY: Double
        /// True when the falling body belongs to the amblyopic eye. False puts
        /// the BAR there instead — Space Dodge's arrangement.
        let fallingBodyIsActor: Bool
        /// Does reaching the bar mean success?
        let contactIsSuccess: Bool
        let speed: (GameDifficulty) -> Double
    }

    let runner: SessionRunner
    let calibration: CalibrationProfile
    let configuration: Configuration
    let makeBody: (Trial) -> GamePhysics.Body
    let difficulty: (Trial) -> GameDifficulty
    var onFinish: (EndReason) -> Void = { _ in }

    @State private var falling: GamePhysics.Body?
    @State private var barX: Double = GameField.widthDegrees / 2
    @State private var lastTick: Date?
    @State private var accumulator: Double = 0
    @State private var settled = false

    private var field: GameField { GameField(calibration: calibration) }
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: configuration.icon,
            instructions: configuration.instructions,
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or both eyes will see everything and the game trains nothing."),
            onFinish: onFinish
        ) {
            content
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
        .onAppear(perform: beginTrial)
    }

    @ViewBuilder
    private var content: some View {
        if let trial = runner.currentTrial {
            let level = difficulty(trial)
            VStack(spacing: 0) {
                Spacer()
                TimelineView(.animation(minimumInterval: GamePhysics.timestep)) { timeline in
                    Canvas { context, _ in
                        advance(to: timeline.date)
                        draw(in: context, difficulty: level)
                    }
                    .frame(width: field.widthPoints, height: field.heightPoints)
                }
                .background(neutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let half = configuration.barWidthDegrees / 2
                        let degrees = value.location.x / field.pointsPerDegree
                        barX = min(max(degrees, half), GameField.widthDegrees - half)
                    })
                .accessibilityLabel("Playfield. Drag to move.")
                Spacer()
            }
        }
    }

    private var neutral: Color {
        colour(actor: AnaglyphCompositor.layerMidpoint,
               context: AnaglyphCompositor.layerMidpoint)
    }

    // MARK: Simulation

    private func advance(to now: Date) {
        guard runner.phase.acceptsResponses, var body = falling, !settled else { return }

        let elapsed = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        accumulator = min(accumulator + elapsed, 0.25)

        let half = configuration.barWidthDegrees / 2
        while accumulator >= GamePhysics.timestep {
            accumulator -= GamePhysics.timestep
            let previous = body.position
            body = GamePhysics.step(body, in: field, bounceBottom: false)

            let reachedBar = GamePhysics.crossesBar(
                from: previous, to: body.position,
                radius: body.radius,
                barY: configuration.barY,
                barMinX: barX - half, barMaxX: barX + half)

            if reachedBar {
                settle(success: configuration.contactIsSuccess)
                break
            }
            if body.position.y - body.radius > GameField.heightDegrees {
                // Reached the bottom without touching the bar: a miss for
                // Sky Catch, a successful dodge for Space Dodge.
                settle(success: !configuration.contactIsSuccess)
                break
            }
        }
        falling = body
    }

    private func settle(success: Bool) {
        guard !settled else { return }
        settled = true
        runner.respond(answer: success ? 1 : 0)
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            falling = nil
            return
        }
        falling = makeBody(trial)
        barX = GameField.widthDegrees / 2
        lastTick = nil
        accumulator = 0
        settled = false
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext, difficulty level: GameDifficulty) {
        let actorLevel = self.level(GameDifficulty.actorContrast)
        let contextLevel = self.level(level.fellowContrast)

        let bodyColour = configuration.fallingBodyIsActor
            ? colour(actor: actorLevel, context: AnaglyphCompositor.layerMidpoint)
            : colour(actor: AnaglyphCompositor.layerMidpoint, context: contextLevel)
        let barColour = configuration.fallingBodyIsActor
            ? colour(actor: AnaglyphCompositor.layerMidpoint, context: contextLevel)
            : colour(actor: actorLevel, context: AnaglyphCompositor.layerMidpoint)

        let half = configuration.barWidthDegrees / 2
        let barRect = CGRect(
            x: field.points(barX - half),
            y: field.points(configuration.barY),
            width: field.points(configuration.barWidthDegrees),
            height: field.points(configuration.barThicknessDegrees))
        context.fill(Path(roundedRect: barRect, cornerRadius: 6), with: .color(barColour))

        if let falling {
            let centre = field.point(falling.position)
            let radius = field.points(falling.radius)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(bodyColour))
        }
    }

    private func level(_ contrast: Double) -> Double {
        AnaglyphCompositor.layerMidpoint
            + (1 - AnaglyphCompositor.layerMidpoint) * contrast
    }

    private func colour(actor: Double, context: Double) -> Color {
        let pixel = compositor.composite(amblyopic: actor, fellow: context)
        return Color(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }
}

// MARK: - The two games

@MainActor
struct SkyCatchView: View {
    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = SkyCatchExercise()

    var body: some View {
        FallingObjectGameView(
            runner: runner,
            calibration: calibration,
            configuration: .init(
                icon: "basket",
                instructions: "Catch the falling fruit in your basket. Slide your finger to move it. One eye sees the fruit and the other sees the basket, so you need both.",
                bodyDegrees: SkyCatchExercise.fruitDegrees,
                barWidthDegrees: SkyCatchExercise.basketWidthDegrees,
                barThicknessDegrees: SkyCatchExercise.basketThicknessDegrees,
                barY: SkyCatchExercise.basketY,
                // The fruit is the thing you must SEE, so it is the amblyopic
                // eye's.
                fallingBodyIsActor: true,
                contactIsSuccess: true,
                speed: SkyCatchExercise.fallSpeed),
            makeBody: exercise.drop(for:),
            difficulty: exercise.difficulty(for:),
            onFinish: onFinish)
    }
}

@MainActor
struct SpaceDodgeView: View {
    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = SpaceDodgeExercise()

    var body: some View {
        FallingObjectGameView(
            runner: runner,
            calibration: calibration,
            configuration: .init(
                icon: "airplane",
                instructions: "Steer your ship out of the way of the falling rocks. One eye sees the rocks and the other sees your ship — you already know where your finger is, so the rocks are the part you have to see.",
                bodyDegrees: SpaceDodgeExercise.rockDegrees,
                barWidthDegrees: SpaceDodgeExercise.shipWidthDegrees,
                barThicknessDegrees: SpaceDodgeExercise.shipThicknessDegrees,
                barY: SpaceDodgeExercise.shipY,
                // INVERTED, and deliberately: you steer the ship, so you know
                // where it is without seeing it. The ROCKS are what must be
                // seen, so they go to the amblyopic eye.
                fallingBodyIsActor: true,
                // Reaching the ship is a HIT, which is the failure here.
                contactIsSuccess: false,
                speed: SpaceDodgeExercise.fallSpeed),
            makeBody: exercise.rock(for:),
            difficulty: exercise.difficulty(for:),
            onFinish: onFinish)
    }
}
