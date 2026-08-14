//
//  HiddenHalfView.swift
//
//  D9's screen. Rings to the amblyopic eye, dots to the fellow eye, one Canvas.
//
//  THE ITEM BODY IS DRAWN TO BOTH EYES, AND THAT IS DELIBERATE
//  Every item's disc is in the shared layer, so both eyes see WHERE the items
//  are. Only the marks are split. If the discs were split too, each eye would
//  see a different subset of items and the user would be comparing two
//  half-populated fields rather than combining two marks on one field — a harder
//  task, but a different one, and not the one the exercise claims to measure.
//
//  docs/03-EXERCISE-CATALOG.md D9.
//

import SwiftUI

@MainActor
struct HiddenHalfView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = HiddenHalfExercise()

    @State private var items: [HiddenHalfExercise.Item] = []

    private var field: GameField { GameField(calibration: calibration) }
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "circle.grid.cross",
            instructions: "One shape has BOTH a ring and a dot. Your two eyes each see only one of the two marks, so you have to put them together. Tap the shape that has both.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first. Without it one eye sees both marks and the puzzle solves itself."),
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
            VStack(spacing: 0) {
                Spacer()
                Canvas { context, _ in
                    draw(in: context, difficulty: level)
                }
                .frame(width: field.widthPoints, height: field.heightPoints)
                .background(neutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        tap(at: value.location)
                    })
                .accessibilityLabel("Shapes. Tap the one with both a ring and a dot.")

                Text("\(items.count) shapes")
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

    // MARK: Trial

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            items = []
            return
        }
        items = exercise.layout(for: trial)
    }

    private func tap(at location: CGPoint) {
        guard runner.phase.acceptsResponses else { return }
        let degrees = CGPoint(x: location.x / field.pointsPerDegree,
                              y: location.y / field.pointsPerDegree)
        guard let index = HiddenHalfExercise.item(at: degrees, in: items) else { return }
        runner.respond(answer: index)
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext, difficulty: GameDifficulty) {
        let side = field.points(HiddenHalfExercise.itemDegrees)

        // Item bodies: BOTH eyes. Only the marks are split.
        let bodyColour = colour(actor: level(0.35), context: level(0.35))
        let ringColour = colour(actor: level(GameDifficulty.actorContrast),
                                context: AnaglyphCompositor.layerMidpoint)
        let dotColour = colour(actor: AnaglyphCompositor.layerMidpoint,
                               context: level(difficulty.fellowContrast))

        for item in items {
            let centre = field.point(item.position)
            let rect = CGRect(x: centre.x - side / 2, y: centre.y - side / 2,
                              width: side, height: side)
            context.fill(Path(ellipseIn: rect), with: .color(bodyColour))

            if item.hasRing {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: side * 0.12,
                                                            dy: side * 0.12)),
                               with: .color(ringColour), lineWidth: max(2, side * 0.10))
            }
            if item.hasDot {
                let dot = rect.insetBy(dx: side * 0.34, dy: side * 0.34)
                context.fill(Path(ellipseIn: dot), with: .color(dotColour))
            }
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
