//
//  PeekabooAndSortViews.swift
//
//  G3 Peekaboo and G6 Colour Sort.
//
//  docs/03-EXERCISE-CATALOG.md G3, G6.
//

import SwiftUI

// MARK: - G3 Peekaboo

@MainActor
struct PeekabooView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = PeekabooExercise()

    @State private var appearedAt: Date?
    @State private var settled = false

    private var field: GameField { GameField(calibration: calibration) }
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "hare",
            instructions: "A creature pops out of one of the holes. Tap it before it ducks back down. Only one of your eyes can see it, so keep both open.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or both eyes see the creature and the game trains nothing."),
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
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    Canvas { context, _ in
                        expireIfNeeded(now: timeline.date, difficulty: level)
                        draw(in: context, trial: trial, difficulty: level)
                    }
                    .frame(width: field.widthPoints, height: field.heightPoints)
                }
                .background(neutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    tap(at: value.location, trial: trial)
                })
                .accessibilityLabel("Holes. Tap the creature when it appears.")
                Spacer()
            }
        }
    }

    private var neutral: Color {
        colour(actor: AnaglyphCompositor.layerMidpoint,
               context: AnaglyphCompositor.layerMidpoint)
    }

    private func beginTrial() {
        appearedAt = runner.currentTrial == nil ? nil : Date()
        settled = false
    }

    /// The creature ducks back down after its time is up: a miss.
    private func expireIfNeeded(now: Date, difficulty: GameDifficulty) {
        guard let appearedAt, !settled, runner.phase.acceptsResponses else { return }
        if now.timeIntervalSince(appearedAt)
            >= PeekabooExercise.secondsVisible(for: difficulty) {
            settled = true
            runner.respond(answer: 0)
        }
    }

    private func tap(at location: CGPoint, trial: Trial) {
        guard !settled, runner.phase.acceptsResponses else { return }
        let degrees = CGPoint(x: location.x / field.pointsPerDegree,
                              y: location.y / field.pointsPerDegree)
        guard PeekabooExercise.tapped(at: degrees,
                                      burrow: exercise.burrow(for: trial)) else { return }
        settled = true
        runner.respond(answer: 1)
    }

    private func draw(in context: GraphicsContext, trial: Trial,
                      difficulty: GameDifficulty) {
        let size = field.points(PeekabooExercise.burrowDegrees)

        // Burrows: BOTH eyes. They are the scene, not the target.
        let burrowColour = colour(actor: level(0.3), context: level(0.3))
        for index in 0..<PeekabooExercise.burrowCount {
            let centre = field.point(PeekabooExercise.centre(ofBurrow: index))
            let rect = CGRect(x: centre.x - size / 2, y: centre.y - size / 2,
                              width: size, height: size)
            context.stroke(Path(ellipseIn: rect), with: .color(burrowColour),
                           lineWidth: 2)
        }

        // The creature: amblyopic eye only, and only while it is up.
        guard !settled, let appearedAt,
              Date().timeIntervalSince(appearedAt)
                < PeekabooExercise.secondsVisible(for: difficulty) else { return }
        let creatureColour = colour(actor: level(GameDifficulty.actorContrast),
                                    context: AnaglyphCompositor.layerMidpoint)
        let centre = field.point(PeekabooExercise.centre(
            ofBurrow: exercise.burrow(for: trial)))
        let inset = size * 0.7
        let rect = CGRect(x: centre.x - inset / 2, y: centre.y - inset / 2,
                          width: inset, height: inset)
        context.fill(Path(ellipseIn: rect), with: .color(creatureColour))
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

// MARK: - G6 Colour Sort

@MainActor
struct ColourSortView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = ColourSortExercise()

    @Environment(\.theme) private var theme

    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    private var cardPoints: Double { calibration.points(forDegrees: 4.0) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "square.split.2x1",
            instructions: "Each shape has one mark on the left and one on the right — and each of your eyes can only see one of them. Say whether the two marks are the same or different.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or one eye sees both marks and the answer is obvious."),
            onFinish: onFinish
        ) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let trial = runner.currentTrial {
            let level = exercise.difficulty(for: trial)
            VStack(spacing: Spacing.xl) {
                Spacer()
                card(left: exercise.leftMark(for: trial),
                     right: exercise.rightMark(for: trial),
                     difficulty: level)
                    .accessibilityLabel("Shape with one mark for each eye")

                HStack(spacing: Spacing.md) {
                    ForEach(ColourSortExercise.Answer.allCases, id: \.rawValue) { answer in
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

    private func card(left: Int, right: Int, difficulty: GameDifficulty) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(colour(actor: AnaglyphCompositor.layerMidpoint,
                                             context: AnaglyphCompositor.layerMidpoint)))

            draw(mark: left,
                 in: CGRect(x: 0, y: 0, width: size.width / 2, height: size.height),
                 colour: colour(actor: level(GameDifficulty.actorContrast),
                                context: AnaglyphCompositor.layerMidpoint),
                 context: context)
            draw(mark: right,
                 in: CGRect(x: size.width / 2, y: 0,
                            width: size.width / 2, height: size.height),
                 colour: colour(actor: AnaglyphCompositor.layerMidpoint,
                                context: level(difficulty.fellowContrast)),
                 context: context)
        }
        .frame(width: cardPoints, height: cardPoints * 0.6)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Color.separatorLine, lineWidth: 1))
    }

    /// Four marks, distinguishable by shape rather than colour.
    ///
    /// Colour would be the obvious choice for something called Colour Sort, and
    /// it is the one thing that cannot work here: the anaglyph filters ARE
    /// colours, so a red mark and a cyan mark are already how the eyes are
    /// separated. Encoding meaning in hue on top of that would collide with the
    /// separation itself.
    private func draw(mark: Int, in rect: CGRect, colour: Color,
                      context: GraphicsContext) {
        let inset = rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)
        var path = Path()
        switch mark % ColourSortExercise.markCount {
        case 0: path.addRect(inset)
        case 1: path.addEllipse(in: inset)
        case 2:
            path.move(to: CGPoint(x: inset.midX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
            path.closeSubpath()
        default:
            path.move(to: CGPoint(x: inset.midX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.minX, y: inset.midY))
            path.closeSubpath()
        }
        context.fill(path, with: .color(colour))
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
