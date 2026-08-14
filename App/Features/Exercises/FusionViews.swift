//
//  FusionViews.swift
//
//  D7 Depth Steps and D10 Hold the Fusion.
//
//  docs/03-EXERCISE-CATALOG.md D7, D10.
//

import SwiftUI

// MARK: - D7 Depth Steps

@MainActor
struct DepthStepsView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = DepthStepsExercise()

    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "arrow.left.and.right",
            instructions: "A shape steps towards you and away again. Sometimes your eyes can still join it into one, and sometimes it splits into two. Just say what you see — both answers are useful.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or there is nothing for the two eyes to fuse."),
            onFinish: onFinish
        ) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let trial = runner.currentTrial {
            let parameters = exercise.parameters(for: trial, calibration: calibration)
            let size = calibration.points(forDegrees: DepthStepsExercise.targetDegrees)
            let shift = Double(parameters.shiftPoints)
                * (parameters.depth == .nearer ? 1 : -1)

            VStack(spacing: Spacing.xl) {
                Spacer()

                Canvas { context, canvasSize in
                    context.fill(Path(CGRect(origin: .zero, size: canvasSize)),
                                 with: .color(neutral))

                    // The same target drawn to each eye, displaced horizontally.
                    // Fusing them is the task; when the disparity exceeds the
                    // user's range they see two.
                    let centreY = canvasSize.height / 2
                    let centreX = canvasSize.width / 2
                    draw(at: CGPoint(x: centreX - shift / 2, y: centreY), size: size,
                         colour: colour(actor: level(GameDifficulty.actorContrast),
                                        context: AnaglyphCompositor.layerMidpoint),
                         context: context)
                    draw(at: CGPoint(x: centreX + shift / 2, y: centreY), size: size,
                         colour: colour(actor: AnaglyphCompositor.layerMidpoint,
                                        context: level(GameDifficulty.actorContrast)),
                         context: context)

                    // A fusion lock: a frame both eyes see, giving the visual
                    // system something to anchor on. Without it the two targets
                    // drift and the test measures patience.
                    let lock = colour(actor: level(0.3), context: level(0.3))
                    context.stroke(
                        Path(roundedRect: CGRect(origin: .zero, size: canvasSize)
                            .insetBy(dx: 6, dy: 6), cornerRadius: 12),
                        with: .color(lock), lineWidth: 2)
                }
                .frame(width: calibration.points(forDegrees: 7),
                       height: calibration.points(forDegrees: 5))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .accessibilityLabel("A shape at a depth. Say whether you see one or two.")

                HStack(spacing: Spacing.md) {
                    ForEach(DepthStepsExercise.Answer.allCases, id: \.rawValue) { answer in
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

    private func draw(at centre: CGPoint, size: Double, colour: Color,
                      context: GraphicsContext) {
        let rect = CGRect(x: centre.x - size / 2, y: centre.y - size / 2,
                          width: size, height: size)
        context.fill(Path(roundedRect: rect, cornerRadius: size * 0.2),
                     with: .color(colour))
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

// MARK: - D10 Hold the Fusion

@MainActor
struct HoldTheFusionView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = HoldTheFusionExercise()

    @State private var pair: StereogramPair?
    @State private var startedAt: Date?
    @State private var askingNow = false

    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "timer",
            instructions: "Keep looking at the speckled panel. A shape is hidden in it that only appears when both eyes work together. When the panel goes away, say which shape it was.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or there is no hidden shape to hold on to."),
            onFinish: onFinish
        ) {
            content
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
        .onAppear(perform: beginTrial)
    }

    @ViewBuilder
    private var content: some View {
        if let trial = runner.currentTrial, let pair {
            VStack(spacing: Spacing.lg) {
                Spacer()

                if askingNow {
                    Text("Which shape was it?")
                        .font(TypeScale.headline())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: Spacing.sm) {
                        ForEach(StereogramParameters.Shape.allCases, id: \.rawValue) { shape in
                            AmblyoButton(title: shape.label, systemImage: shape.systemImage,
                                         style: .secondary) {
                                runner.respond(answer: shape.rawValue)
                            }
                            .disabled(!runner.phase.acceptsResponses)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                } else {
                    TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                        Canvas { context, _ in
                            expireIfNeeded(now: timeline.date, trial: trial)
                            draw(pair: pair, in: context)
                        }
                        .frame(width: pair.fieldPoints, height: pair.fieldPoints)
                    }
                    .background(neutral)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityLabel("Speckled panel. Keep looking.")

                    Text("Keep looking…")
                        .font(TypeScale.caption())
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
        }
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            pair = nil
            return
        }
        let parameters = exercise.parameters(for: trial, calibration: calibration)
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("seed")))
        pair = StereogramGenerator.make(parameters, generator: &generator)
        startedAt = Date()
        askingNow = false
    }

    /// The panel disappears once the hold period is up, and only THEN is the
    /// question asked. Asking while it is still on screen would let the user
    /// read the answer off the display instead of holding fusion for it.
    private func expireIfNeeded(now: Date, trial: Trial) {
        guard let startedAt, !askingNow else { return }
        if now.timeIntervalSince(startedAt) >= exercise.holdSeconds(for: trial) {
            askingNow = true
        }
    }

    private func draw(pair: StereogramPair, in context: GraphicsContext) {
        let amblyopicOnly = colour(actor: 1.0, context: AnaglyphCompositor.layerMidpoint)
        let fellowOnly = colour(actor: AnaglyphCompositor.layerMidpoint, context: 1.0)
        let shared = colour(actor: 1.0, context: 1.0)

        let fellowKeys = Set(pair.fellowDots.map(Key.init))
        let amblyopicKeys = Set(pair.amblyopicDots.map(Key.init))

        for dot in pair.amblyopicDots {
            let both = fellowKeys.contains(Key(dot))
            context.fill(square(dot, pair.dotPoints),
                         with: .color(both ? shared : amblyopicOnly))
        }
        for dot in pair.fellowDots where !amblyopicKeys.contains(Key(dot)) {
            context.fill(square(dot, pair.dotPoints), with: .color(fellowOnly))
        }
    }

    private struct Key: Hashable {
        let x: Int
        let y: Int
        init(_ point: CGPoint) {
            x = Int(point.x.rounded())
            y = Int(point.y.rounded())
        }
    }

    private func square(_ origin: CGPoint, _ side: Double) -> Path {
        Path(CGRect(x: origin.x, y: origin.y, width: side, height: side))
    }

    private var neutral: Color {
        colour(actor: AnaglyphCompositor.layerMidpoint,
               context: AnaglyphCompositor.layerMidpoint)
    }

    private func colour(actor: Double, context: Double) -> Color {
        let pixel = compositor.composite(amblyopic: actor, fellow: context)
        return Color(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }
}
