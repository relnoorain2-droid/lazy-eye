//
//  StackDropView.swift
//
//  D3's screen. The falling piece is drawn to the amblyopic eye, the grid and
//  the target slot to the fellow eye, and both go through one Canvas so the
//  crosstalk correction survives — same rule as every other dichoptic view here.
//
//  STEERING IS A DRAG, AND THE PIECE FOLLOWS THE FINGER'S COLUMN
//  Not left/right buttons: buttons let a user look only at the piece, tap twice
//  and glance at the grid once. Dragging to a column means holding both layers
//  in mind at the same time, which is the demand this exercise exists to make.
//
//  docs/03-EXERCISE-CATALOG.md D3.
//

import SwiftUI

@MainActor
struct StackDropView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = StackDropExercise()

    @State private var piece: GamePhysics.Body?
    @State private var lastTick: Date?
    @State private var accumulator: Double = 0
    @State private var settled = false

    private var field: GameField { GameField(calibration: calibration) }
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "square.grid.3x3.topleft.filled",
            instructions: "A block falls from the top. Slide your finger to steer it into the marked slot. One eye sees the block and the other sees the slot, so you need both to aim.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or both eyes will see everything and the aiming is trivial."),
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
                        advance(to: timeline.date, trial: trial)
                        draw(in: context, trial: trial, difficulty: difficulty)
                    }
                    .frame(width: field.widthPoints, height: field.heightPoints)
                }
                .background(neutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        guard var body = piece else { return }
                        let degrees = value.location.x / field.pointsPerDegree
                        let column = StackDropExercise.column(atX: degrees)
                        body.position.x = StackDropExercise.centreX(ofColumn: column)
                        piece = body
                    })
                .accessibilityLabel("Grid. Drag to steer the falling block.")

                Text("Slide to the marked slot")
                    .font(TypeScale.caption())
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, Spacing.sm)
                Spacer()
            }
        }
    }

    private var neutral: Color {
        colour(actor: AnaglyphCompositor.layerMidpoint,
               context: AnaglyphCompositor.layerMidpoint)
    }

    // MARK: Simulation

    private func advance(to now: Date, trial: Trial) {
        guard runner.phase.acceptsResponses, var body = piece, !settled else { return }

        let elapsed = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        accumulator = min(accumulator + elapsed, 0.25)

        let floor = GameField.heightDegrees - StackDropExercise.cellDegrees / 2
        while accumulator >= GamePhysics.timestep {
            accumulator -= GamePhysics.timestep
            // Only the vertical component is simulated; the horizontal position
            // is wherever the finger put it, so there is nothing to integrate.
            body.position.y += body.velocity.y * GamePhysics.timestep
            if body.position.y >= floor {
                body.position.y = floor
                let landed = StackDropExercise.column(atX: body.position.x)
                settle(landedIn: landed)
                break
            }
        }
        piece = body
    }

    /// One piece is one trial: the column it lands in IS the answer, scored
    /// against the target exactly as a tapped button would be.
    private func settle(landedIn column: Int) {
        guard !settled else { return }
        settled = true
        runner.respond(answer: column)
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            piece = nil
            return
        }
        let difficulty = exercise.difficulty(for: trial)
        piece = GamePhysics.Body(
            position: CGPoint(
                x: StackDropExercise.centreX(ofColumn: exercise.startColumn(for: trial)),
                y: StackDropExercise.cellDegrees / 2),
            velocity: CGPoint(x: 0, y: StackDropExercise.dropSpeed(for: difficulty)),
            size: StackDropExercise.cellDegrees)
        lastTick = nil
        accumulator = 0
        settled = false
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext, trial: Trial,
                      difficulty: GameDifficulty) {
        let cell = field.points(StackDropExercise.cellDegrees)
        let contextColour = colour(actor: AnaglyphCompositor.layerMidpoint,
                                   context: level(difficulty.fellowContrast))

        // The grid and the target slot: fellow eye only. If any of this were
        // drawn to both eyes, the amblyopic eye could aim without the fellow one
        // and the exercise would stop being dichoptic.
        let baseY = field.heightPoints - cell
        for column in 0..<StackDropExercise.columns {
            let rect = CGRect(x: Double(column) * cell, y: baseY,
                              width: cell, height: cell)
            let isTarget = column == exercise.targetColumn(for: trial)
            let path = Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 4)
            if isTarget {
                context.fill(path, with: .color(contextColour))
            } else {
                context.stroke(path, with: .color(contextColour), lineWidth: 1)
            }
        }

        // The falling piece: amblyopic eye, always full contrast.
        if let piece {
            let actorColour = colour(actor: level(GameDifficulty.actorContrast),
                                     context: AnaglyphCompositor.layerMidpoint)
            let centre = field.point(piece.position)
            let side = field.points(piece.size) - 4
            let rect = CGRect(x: centre.x - side / 2, y: centre.y - side / 2,
                              width: side, height: side)
            context.fill(Path(roundedRect: rect, cornerRadius: 6),
                         with: .color(actorColour))
        }
    }

    /// Contrast is a modulation either side of the compositor's midpoint, not a
    /// brightness. Drawing "80% white" would put the piece outside the headroom
    /// the crosstalk correction needs.
    private func level(_ contrast: Double) -> Double {
        AnaglyphCompositor.layerMidpoint
            + (1 - AnaglyphCompositor.layerMidpoint) * contrast
    }

    private func colour(actor: Double, context: Double) -> Color {
        let pixel = compositor.composite(amblyopic: actor, fellow: context)
        return Color(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }
}
