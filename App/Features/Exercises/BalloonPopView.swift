//
//  BalloonPopView.swift
//
//  G1's screen. One balloon at a time, rising; tap it before it leaves the top.
//
//  THE TOP EDGE IS OPEN, DELIBERATELY
//  `GamePhysics.step` is asked not to bounce off the top here. With the default
//  the balloon would rebound and drift forever, the trial could never end in a
//  miss, and the staircase would climb until every balloon was invisible —
//  while the game looked perfectly healthy.
//
//  ONE BALLOON, NOT A SCREENFUL
//  A screenful is a better toy and a worse measurement: with six balloons up,
//  a child pops whichever they happen to see and the miss rate stops being
//  about the faint one. One at a time keeps a trial a trial.
//
//  docs/03-EXERCISE-CATALOG.md G1.
//

import SwiftUI

@MainActor
struct BalloonPopView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = BalloonPopExercise()

    @State private var balloon: GamePhysics.Body?
    @State private var lastTick: Date?
    @State private var accumulator: Double = 0
    @State private var settled = false
    @State private var poppedFlash = false

    private var field: GameField { GameField(calibration: calibration) }
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "balloon.2",
            instructions: "Pop the balloons before they float away. Tap them with your finger. Some are hard to see — that is the game.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or the balloons will be easy to see with either eye."),
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
                .background(sky(difficulty))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        tap(at: value.location)
                    })
                .accessibilityLabel("Sky. Tap the balloons.")
                Spacer()
            }
        }
    }

    /// The sky is the fellow eye's layer, at the staircase's contrast. It is not
    /// decoration: it is the thing the fellow eye is given to attend to, and its
    /// contrast is the measured dimension.
    private func sky(_ difficulty: GameDifficulty) -> Color {
        colour(actor: AnaglyphCompositor.layerMidpoint,
               context: level(difficulty.fellowContrast * 0.5))
    }

    // MARK: Simulation

    private func advance(to now: Date) {
        guard runner.phase.acceptsResponses, var body = balloon, !settled else { return }

        let elapsed = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        accumulator = min(accumulator + elapsed, 0.25)

        while accumulator >= GamePhysics.timestep {
            accumulator -= GamePhysics.timestep
            // Top open so the balloon can escape; bottom closed so drift cannot
            // push it out the way it came.
            body = GamePhysics.step(body, in: field,
                                    bounceBottom: true, bounceTop: false)
            if BalloonPopExercise.escaped(body) {
                settle(popped: false)
                break
            }
        }
        balloon = body
    }

    private func tap(at location: CGPoint) {
        guard let balloon, !settled, runner.phase.acceptsResponses else { return }
        let degrees = CGPoint(x: location.x / field.pointsPerDegree,
                              y: location.y / field.pointsPerDegree)
        if BalloonPopExercise.popped(tapAt: degrees, balloon: balloon) {
            poppedFlash = true
            settle(popped: true)
        }
        // A tap that misses is NOT scored. Punishing a stray finger would make
        // the threshold partly a measure of dexterity, and for a four-year-old
        // mostly that. The trial ends when the balloon escapes or is popped.
    }

    private func settle(popped: Bool) {
        guard !settled else { return }
        settled = true
        runner.respond(answer: popped ? 1 : 0)
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            balloon = nil
            return
        }
        balloon = exercise.launch(for: trial)
        lastTick = nil
        accumulator = 0
        settled = false
        poppedFlash = false
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext, difficulty: GameDifficulty) {
        guard let balloon, !poppedFlash else { return }
        let actorColour = colour(actor: level(GameDifficulty.actorContrast),
                                 context: AnaglyphCompositor.layerMidpoint)
        let centre = field.point(balloon.position)
        let radius = field.points(balloon.radius)
        let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(actorColour))

        // String, drawn in the same layer as the balloon. It is a cue for the
        // amblyopic eye only — putting it in the shared layer would give the
        // fellow eye a way to locate a balloon it cannot see.
        var string = Path()
        string.move(to: CGPoint(x: centre.x, y: centre.y + radius))
        string.addLine(to: CGPoint(x: centre.x, y: centre.y + radius * 1.8))
        context.stroke(string, with: .color(actorColour), lineWidth: 2)
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
