//
//  RemainingDichopticViews.swift
//
//  D8 Bead Line, G4 Maze Runner and G7 Rhythm Tap.
//
//  docs/03-EXERCISE-CATALOG.md D8, G4, G7.
//

import SwiftUI

// MARK: - D8 Bead Line

@MainActor
struct BeadLineView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = BeadLineExercise()
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "line.diagonal",
            instructions: "Look at the bead. Say how many lines you can see running to it — one or two. Both answers happen, and both are useful, so answer what you actually see.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or there is only ever one line to see."),
            onFinish: onFinish
        ) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let trial = runner.currentTrial {
            let separation = exercise.separationPoints(for: trial, calibration: calibration)
            VStack(spacing: Spacing.xl) {
                Spacer()
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .color(neutral))

                    let beadY = size.height * 0.25
                    let baseY = size.height * 0.95
                    let centreX = size.width / 2

                    // On a catch trial the separation is zero and BOTH eyes get
                    // the same single line, so "one" is the honest answer.
                    let amblyopic = colour(actor: level(GameDifficulty.actorContrast),
                                           context: AnaglyphCompositor.layerMidpoint)
                    let fellow = colour(actor: AnaglyphCompositor.layerMidpoint,
                                        context: level(GameDifficulty.actorContrast))
                    let both = colour(actor: level(GameDifficulty.actorContrast),
                                      context: level(GameDifficulty.actorContrast))

                    if separation == 0 {
                        stroke(from: CGPoint(x: centreX, y: baseY),
                               to: CGPoint(x: centreX, y: beadY),
                               colour: both, context: context)
                    } else {
                        stroke(from: CGPoint(x: centreX - separation / 2, y: baseY),
                               to: CGPoint(x: centreX, y: beadY),
                               colour: amblyopic, context: context)
                        stroke(from: CGPoint(x: centreX + separation / 2, y: baseY),
                               to: CGPoint(x: centreX, y: beadY),
                               colour: fellow, context: context)
                    }

                    // The bead itself is shared: both eyes must agree where to
                    // converge, or there is nothing to fuse on.
                    let bead = colour(actor: level(0.6), context: level(0.6))
                    let radius = calibration.points(forDegrees: 0.5) / 2
                    context.fill(Path(ellipseIn: CGRect(x: centreX - radius,
                                                        y: beadY - radius,
                                                        width: radius * 2,
                                                        height: radius * 2)),
                                 with: .color(bead))
                }
                .frame(width: calibration.points(forDegrees: 7),
                       height: calibration.points(forDegrees: 8))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .accessibilityLabel("A bead with lines running to it")

                HStack(spacing: Spacing.md) {
                    ForEach(BeadLineExercise.Answer.allCases, id: \.rawValue) { answer in
                        AmblyoButton(title: answer.label, style: .secondary) {
                            runner.respond(answer: answer.rawValue)
                        }
                        .disabled(!runner.phase.acceptsResponses)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                Spacer()
            }
        }
    }

    private func stroke(from: CGPoint, to: CGPoint, colour: Color,
                        context: GraphicsContext) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(colour), lineWidth: 3)
    }

    private var neutral: Color {
        colour(actor: AnaglyphCompositor.layerMidpoint,
               context: AnaglyphCompositor.layerMidpoint)
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

// MARK: - G4 Maze Runner

@MainActor
struct MazeRunnerView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = MazeRunnerExercise()

    @State private var wallY: Double = 0
    @State private var runnerX: Double = GameField.widthDegrees / 2
    @State private var lastTick: Date?
    @State private var accumulator: Double = 0
    @State private var settled = false

    private var field: GameField { GameField(calibration: calibration) }
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "figure.run",
            instructions: "A wall comes towards you with one gap in it. Slide your finger to steer through the gap. One eye sees the wall and the other sees your runner, so you need both to find the opening.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or the gap is visible to either eye alone."),
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
            let level = exercise.difficulty(for: trial)
            VStack {
                Spacer()
                TimelineView(.animation(minimumInterval: GamePhysics.timestep)) { timeline in
                    Canvas { context, _ in
                        advance(to: timeline.date, trial: trial, difficulty: level)
                        draw(in: context, trial: trial, difficulty: level)
                    }
                    .frame(width: field.widthPoints, height: field.heightPoints)
                }
                .background(neutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let half = MazeRunnerExercise.runnerDegrees / 2
                    let degrees = value.location.x / field.pointsPerDegree
                    runnerX = min(max(degrees, half), GameField.widthDegrees - half)
                })
                .accessibilityLabel("Steer through the gap")
                Spacer()
            }
        }
    }

    private func beginTrial() {
        wallY = 0
        runnerX = GameField.widthDegrees / 2
        lastTick = nil
        accumulator = 0
        settled = false
    }

    private func advance(to now: Date, trial: Trial, difficulty: GameDifficulty) {
        guard runner.phase.acceptsResponses, !settled else { return }
        let elapsed = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        accumulator = min(accumulator + elapsed, 0.25)

        let runnerY = GameField.heightDegrees - 1.5
        let speed = MazeRunnerExercise.approachSpeed(for: difficulty)
        while accumulator >= GamePhysics.timestep {
            accumulator -= GamePhysics.timestep
            wallY += speed * GamePhysics.timestep
            if wallY >= runnerY {
                settled = true
                let through = MazeRunnerExercise.passedThrough(
                    runnerX: runnerX, gapCentre: exercise.gapCentre(for: trial))
                runner.respond(answer: through ? 1 : 0)
                break
            }
        }
    }

    private func draw(in context: GraphicsContext, trial: Trial,
                      difficulty: GameDifficulty) {
        // WALL to the amblyopic eye: it carries the gap, which is the thing that
        // must be seen. RUNNER to the fellow eye: the finger already knows where
        // it is.
        let wallColour = colour(actor: level(GameDifficulty.actorContrast),
                                context: AnaglyphCompositor.layerMidpoint)
        let runnerColour = colour(actor: AnaglyphCompositor.layerMidpoint,
                                  context: level(difficulty.fellowContrast))

        let gapCentre = exercise.gapCentre(for: trial)
        let half = MazeRunnerExercise.gapDegrees / 2
        let thickness = field.points(MazeRunnerExercise.wallThicknessDegrees)
        let y = field.points(wallY)

        context.fill(Path(CGRect(x: 0, y: y,
                                 width: field.points(gapCentre - half),
                                 height: thickness)), with: .color(wallColour))
        let rightStart = field.points(gapCentre + half)
        context.fill(Path(CGRect(x: rightStart, y: y,
                                 width: field.widthPoints - rightStart,
                                 height: thickness)), with: .color(wallColour))

        let size = field.points(MazeRunnerExercise.runnerDegrees)
        let centre = field.point(CGPoint(x: runnerX, y: GameField.heightDegrees - 1.5))
        context.fill(Path(ellipseIn: CGRect(x: centre.x - size / 2, y: centre.y - size / 2,
                                            width: size, height: size)),
                     with: .color(runnerColour))
    }

    private var neutral: Color {
        colour(actor: AnaglyphCompositor.layerMidpoint,
               context: AnaglyphCompositor.layerMidpoint)
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

// MARK: - G7 Rhythm Tap

@MainActor
struct RhythmTapView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = RhythmTapExercise()

    @State private var startedAt: Date?
    @State private var markerY: Double = 0
    @State private var settled = false

    private var field: GameField { GameField(calibration: calibration) }
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    private var lineY: Double { GameField.heightDegrees - 2.0 }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "metronome",
            instructions: "A marker slides down towards the line. Tap anywhere the moment it reaches the line. One eye sees the marker and the other sees the line.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or one eye sees both the marker and the line."),
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
            let level = exercise.difficulty(for: trial)
            VStack {
                Spacer()
                TimelineView(.animation(minimumInterval: GamePhysics.timestep)) { timeline in
                    Canvas { context, _ in
                        advance(to: timeline.date, trial: trial, difficulty: level)
                        draw(in: context, difficulty: level)
                    }
                    .frame(width: field.widthPoints, height: field.heightPoints)
                }
                .background(neutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { _ in
                    tap(trial: trial, difficulty: level)
                })
                .accessibilityLabel("Tap when the marker reaches the line")
                Spacer()
            }
        }
    }

    private func beginTrial() {
        startedAt = runner.currentTrial == nil ? nil : Date()
        markerY = 0
        settled = false
    }

    private func advance(to now: Date, trial: Trial, difficulty: GameDifficulty) {
        guard let startedAt, !settled, runner.phase.acceptsResponses else { return }
        let elapsed = now.timeIntervalSince(startedAt) - exercise.startDelay(for: trial)
        guard elapsed > 0 else { return }
        markerY = min(elapsed * RhythmTapExercise.sweepSpeed(for: difficulty),
                      GameField.heightDegrees)

        // Well past the line without a tap: a miss.
        let arrival = arrivalSeconds(trial: trial, difficulty: difficulty)
        if now.timeIntervalSince(startedAt)
            > arrival + RhythmTapExercise.toleranceSeconds {
            settled = true
            runner.respond(answer: 0)
        }
    }

    private func arrivalSeconds(trial: Trial, difficulty: GameDifficulty) -> Double {
        exercise.startDelay(for: trial)
            + lineY / RhythmTapExercise.sweepSpeed(for: difficulty)
    }

    private func tap(trial: Trial, difficulty: GameDifficulty) {
        guard let startedAt, !settled, runner.phase.acceptsResponses else { return }
        settled = true
        let elapsed = Date().timeIntervalSince(startedAt)
        let arrival = arrivalSeconds(trial: trial, difficulty: difficulty)
        runner.respond(answer: RhythmTapExercise.inTime(tapAt: elapsed,
                                                        arrivalAt: arrival) ? 1 : 0)
    }

    private func draw(in context: GraphicsContext, difficulty: GameDifficulty) {
        // Marker to the amblyopic eye — it is what must be tracked. Line to the
        // fellow eye.
        let markerColour = colour(actor: level(GameDifficulty.actorContrast),
                                  context: AnaglyphCompositor.layerMidpoint)
        let lineColour = colour(actor: AnaglyphCompositor.layerMidpoint,
                                context: level(difficulty.fellowContrast))

        let thickness = field.points(RhythmTapExercise.targetLineDegrees)
        context.fill(Path(CGRect(x: 0, y: field.points(lineY),
                                 width: field.widthPoints, height: thickness)),
                     with: .color(lineColour))

        let size = field.points(RhythmTapExercise.markerDegrees)
        let centreX = field.widthPoints / 2
        let y = field.points(markerY)
        context.fill(Path(ellipseIn: CGRect(x: centreX - size / 2, y: y - size / 2,
                                            width: size, height: size)),
                     with: .color(markerColour))
    }

    private var neutral: Color {
        colour(actor: AnaglyphCompositor.layerMidpoint,
               context: AnaglyphCompositor.layerMidpoint)
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
