//
//  DepthPopView.swift
//
//  D6's session screen. One Canvas, two dot fields, four answer buttons.
//
//  WHY ONE Canvas AND NOT TWO STACKED VIEWS
//  Same reason as the Balance Meter, and worth repeating because it is the
//  easiest way to break every dichoptic exercise here: the crosstalk correction
//  SUBTRACTS one eye's layer from the other's channel. Two stacked SwiftUI views
//  are blended by the system compositor, which knows nothing about that
//  correction, so the leak comes straight back — and for a stereogram that does
//  not merely degrade the stimulus, it destroys it, because the depth lives in
//  the difference between two images.
//
//  THE PREVIEW OUTLINES THE SHAPE, AND THE REAL STIMULUS NEVER DOES
//  App Review has to be able to evaluate this without red-cyan glasses, and a
//  reviewer looking at honest stereogram noise sees noise, which reads as a
//  broken exercise. Preview mode outlines the shape and says plainly that this
//  is not how the exercise looks. That outline must never appear in the real
//  stimulus: it is a monocular cue, and a monocular cue defeats the one property
//  that makes this exercise worth having.
//
//  docs/03-EXERCISE-CATALOG.md D6, docs/08-COMPLIANCE-LEGAL.md section 8.
//

import SwiftUI

@MainActor
struct DepthPopView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = DepthPopExercise()

    @State private var pair: StereogramPair?
    @State private var parameters: StereogramParameters?
    @State private var previewWithoutGlasses = false

    private var compositor: AnaglyphCompositor {
        AnaglyphCompositor(calibration: calibration)
    }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "cube.transparent",
            instructions: "With your glasses on, a shape stands out from the speckle. Say which shape it is. Neither eye can see it alone — that is the point, so take a moment before answering.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first. Without separation there is no depth to see here at all."),
            onFinish: onFinish
        ) {
            content
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
        .onAppear(perform: beginTrial)
    }

    @ViewBuilder
    private var content: some View {
        if let pair, let parameters {
            VStack(spacing: 0) {
                Spacer()

                Canvas { context, _ in
                    draw(pair: pair, parameters: parameters, in: context)
                }
                .frame(width: pair.fieldPoints, height: pair.fieldPoints)
                .background(backgroundColour)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .accessibilityLabel(previewWithoutGlasses
                    ? "Preview with the hidden shape outlined"
                    : "Speckled field. Name the shape that stands out.")

                if parameters.isLimitedByDisplay {
                    // Honest, and specifically NOT framed as the user's limit.
                    Text("This screen can't show a finer depth than this.")
                        .font(TypeScale.caption())
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, Spacing.sm)
                }

                Spacer()
                shapeButtons.padding(.horizontal, Spacing.lg)
                previewToggle.padding(.horizontal, Spacing.lg).padding(.bottom, 96)
            }
        }
    }

    /// The compositor's midpoint, for the same reason as D5: compositing assumes
    /// both layers sit around it, and any other background silently changes the
    /// effective contrast of every dot.
    private var backgroundColour: Color {
        colour(amblyopic: AnaglyphCompositor.layerMidpoint,
               fellow: AnaglyphCompositor.layerMidpoint)
    }

    private var shapeButtons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: Spacing.sm) {
            ForEach(StereogramParameters.Shape.allCases, id: \.rawValue) { shape in
                Button {
                    runner.respond(answer: shape.rawValue)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: shape.systemImage)
                        Text(shape.label).font(TypeScale.callout())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button,
                                                style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!runner.phase.acceptsResponses)
                .accessibilityLabel(shape.label)
            }
        }
    }

    private var previewToggle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Show without glasses", isOn: $previewWithoutGlasses)
                .font(TypeScale.caption())
                .tint(.brandPrimary)
            if previewWithoutGlasses {
                Text("For reviewing the app without red-cyan glasses. The real exercise draws no outline — the shape exists only in the difference between your two eyes.")
                    .font(TypeScale.caption())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: Drawing

    private func draw(pair: StereogramPair, parameters: StereogramParameters,
                      in context: GraphicsContext) {
        // A dot at the same position in both fields is common to the two images
        // and must be bright to BOTH eyes. Most of the field is common — only
        // the shape region differs — so getting this wrong would make the whole
        // background flicker between the eyes and swamp the disparity.
        let amblyopicOnly = colour(amblyopic: 1.0,
                                   fellow: AnaglyphCompositor.layerMidpoint)
        let fellowOnly = colour(amblyopic: AnaglyphCompositor.layerMidpoint,
                                fellow: 1.0)
        let shared = colour(amblyopic: 1.0, fellow: 1.0)

        let fellowKeys = Set(pair.fellowDots.map(PointKey.init))
        let amblyopicKeys = Set(pair.amblyopicDots.map(PointKey.init))

        for dot in pair.amblyopicDots {
            let isShared = fellowKeys.contains(PointKey(dot))
            context.fill(square(at: dot, side: pair.dotPoints),
                         with: .color(isShared ? shared : amblyopicOnly))
        }
        for dot in pair.fellowDots where !amblyopicKeys.contains(PointKey(dot)) {
            context.fill(square(at: dot, side: pair.dotPoints),
                         with: .color(fellowOnly))
        }

        guard previewWithoutGlasses else { return }
        let inset = pair.fieldPoints * (1 - parameters.shapeFraction) / 2
        let box = CGRect(x: inset, y: inset,
                         width: pair.fieldPoints - 2 * inset,
                         height: pair.fieldPoints - 2 * inset)
        context.stroke(Path(roundedRect: box, cornerRadius: 4),
                       with: .color(.orange), lineWidth: 2)
    }

    /// Dot positions in the two fields come from the same integer arithmetic, so
    /// rounding to whole points is an exact comparison here rather than an
    /// approximate one.
    private struct PointKey: Hashable {
        let x: Int
        let y: Int
        init(_ point: CGPoint) {
            x = Int(point.x.rounded())
            y = Int(point.y.rounded())
        }
    }

    private func square(at origin: CGPoint, side: Double) -> Path {
        Path(CGRect(x: origin.x, y: origin.y, width: side, height: side))
    }

    private func colour(amblyopic: Double, fellow: Double) -> Color {
        if previewWithoutGlasses {
            // Both layers to all channels so the field is visible to the naked
            // eye. Not the real stimulus, and labelled as such on screen.
            return Color(white: max(amblyopic, fellow))
        }
        let pixel = compositor.composite(amblyopic: amblyopic, fellow: fellow)
        return Color(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }

    // MARK: Trial

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            pair = nil
            parameters = nil
            return
        }
        let built = exercise.parameters(for: trial, calibration: calibration)
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("seed")))
        parameters = built
        pair = StereogramGenerator.make(built, generator: &generator)
    }
}
