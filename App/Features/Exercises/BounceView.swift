//
//  BounceView.swift
//
//  D4's screen: a drag-controlled paddle, a ball, and one Canvas compositing
//  both eyes.
//
//  FIXED TIMESTEP, NOT FRAME DELTAS
//  The simulation advances in 1/60 s steps and catches up if the display falls
//  behind, rather than integrating whatever time actually elapsed. A variable
//  step makes the physics depend on how busy the device is: a dropped frame
//  becomes a double-length jump, and a ball can cross the paddle inside it. It
//  also means the same serve plays out differently on a slow phone, which would
//  make a threshold partly a measurement of the hardware.
//
//  THE PADDLE FOLLOWS A DRAG, NOT A TAP
//  Tapping to teleport would let a user ignore the ball until the last moment
//  and stab at it. Dragging forces continuous tracking, which is the point.
//
//  docs/03-EXERCISE-CATALOG.md D4.
//

import SwiftUI

@MainActor
struct BounceView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = BounceExercise()

    @State private var ball: GamePhysics.Body?
    @State private var previousBallPosition: CGPoint = .zero
    @State private var paddleX: Double = GameField.widthDegrees / 2
    @State private var lastTick: Date?
    @State private var accumulator: Double = 0
    @State private var settled = false

    private var field: GameField { GameField(calibration: calibration) }

    private var compositor: AnaglyphCompositor {
        AnaglyphCompositor(calibration: calibration)
    }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "circle.circle",
            instructions: "Slide your finger to move the paddle and keep the ball in play. One eye sees the ball and the other sees the paddle, so you need both — if the ball keeps vanishing, that is the exercise working, not a fault.",
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
            let difficulty = exercise.difficulty(for: trial)
            VStack(spacing: 0) {
                Spacer()
                TimelineView(.animation(minimumInterval: GamePhysics.timestep)) { timeline in
                    Canvas { context, _ in
                        advance(to: timeline.date)
                        draw(in: context, difficulty: difficulty)
                    }
                    .frame(width: field.widthPoints, height: field.heightPoints)
                }
                .background(backgroundColour(difficulty))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Clamped so the paddle cannot leave the field, and
                            // measured in degrees so a drag covers the same
                            // visual distance on every device.
                            let half = BounceExercise.paddleWidthDegrees / 2
                            let degrees = value.location.x / field.pointsPerDegree
                            paddleX = min(max(degrees, half),
                                          GameField.widthDegrees - half)
                        }
                )
                .accessibilityLabel("Playfield. Drag to move the paddle.")

                Text("Drag anywhere on the panel to move the paddle")
                    .font(TypeScale.caption())
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, Spacing.sm)
                Spacer()
            }
        }
    }

    private func backgroundColour(_ difficulty: GameDifficulty) -> Color {
        colour(actor: AnaglyphCompositor.layerMidpoint,
               context: AnaglyphCompositor.layerMidpoint)
    }

    // MARK: Simulation

    private func advance(to now: Date) {
        guard runner.phase.acceptsResponses, var body = ball, !settled else { return }

        // Catch up in whole fixed steps. Capped so returning from the background
        // after a minute does not run 3,600 steps in one frame — which would
        // teleport the ball and score a miss the user never had a chance at.
        let elapsed = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        accumulator = min(accumulator + elapsed, 0.25)

        while accumulator >= GamePhysics.timestep {
            accumulator -= GamePhysics.timestep
            let previous = body.position
            body = GamePhysics.step(body, in: field, bounceBottom: false)

            if BounceExercise.caught(previous: previous, current: body.position,
                                     paddleCentreX: paddleX) {
                // Bounce off the paddle, with the angle depending on where it
                // struck: centre sends it straight back, edges send it wide.
                // A pure vertical reflection would make the game a metronome.
                let offset = (body.position.x - paddleX)
                    / (BounceExercise.paddleWidthDegrees / 2)
                let speed = (body.velocity.x * body.velocity.x
                             + body.velocity.y * body.velocity.y).squareRoot()
                let angle = offset * .pi / 4          // up to 45 degrees
                body.position.y = BounceExercise.paddleY - body.radius
                body.velocity = CGPoint(x: speed * sin(angle),
                                        y: -abs(speed * cos(angle)))
                settle(caught: true)
                break
            }

            if BounceExercise.missed(body) {
                settle(caught: false)
                break
            }
        }
        ball = body
        previousBallPosition = body.position
    }

    /// One ball is one trial. Reporting it through `respond` keeps games on the
    /// same staircase as everything else rather than inventing a second scoring
    /// path that would have to be tuned separately.
    private func settle(caught: Bool) {
        guard !settled else { return }
        settled = true
        runner.respond(answer: caught ? 1 : 0)
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            ball = nil
            return
        }
        let served = exercise.serve(for: trial)
        ball = served
        previousBallPosition = served.position
        paddleX = GameField.widthDegrees / 2
        lastTick = nil
        accumulator = 0
        settled = false
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext, difficulty: GameDifficulty) {
        // Paddle and bricks: fellow eye, at the staircase's contrast.
        let contextColour = colour(actor: AnaglyphCompositor.layerMidpoint,
                                   context: contextLevel(difficulty))
        let paddleRect = CGRect(
            x: field.points(paddleX - BounceExercise.paddleWidthDegrees / 2),
            y: field.points(BounceExercise.paddleY),
            width: field.points(BounceExercise.paddleWidthDegrees),
            height: field.points(BounceExercise.paddleThicknessDegrees))
        context.fill(Path(roundedRect: paddleRect, cornerRadius: 4),
                     with: .color(contextColour))

        // Ball: amblyopic eye, always at full contrast.
        if let ball {
            let actorColour = colour(actor: actorLevel, context: AnaglyphCompositor.layerMidpoint)
            let centre = field.point(ball.position)
            let radius = field.points(ball.radius)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(actorColour))
        }
    }

    /// Layer levels around the compositor's midpoint. Contrast is a modulation
    /// either side of that midpoint, not a brightness — drawing "80% white"
    /// would put the ball outside the headroom the crosstalk correction needs.
    private var actorLevel: Double {
        AnaglyphCompositor.layerMidpoint
            + (1 - AnaglyphCompositor.layerMidpoint) * GameDifficulty.actorContrast
    }

    private func contextLevel(_ difficulty: GameDifficulty) -> Double {
        AnaglyphCompositor.layerMidpoint
            + (1 - AnaglyphCompositor.layerMidpoint) * difficulty.fellowContrast
    }

    private func colour(actor: Double, context: Double) -> Color {
        let pixel = compositor.composite(amblyopic: actor, fellow: context)
        return Color(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }
}
