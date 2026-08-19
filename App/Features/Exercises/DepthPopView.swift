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

    // The compositor, the dot colouring, the background midpoint and the
    // preview outline all moved to `StereogramField` when the Check-in needed
    // the same stimulus. They are not duplicated here on purpose: two
    // stereogram renderers would have drifted, and the battery borrows this
    // exercise specifically so its measurement matches this screen.

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

                // Drawn by the SHARED field, which the Check-in also uses.
                // Two renderers would have drifted, and the battery borrows this
                // exercise precisely so its number matches this screen's.
                StereogramField(pair: pair,
                                parameters: parameters,
                                calibration: calibration,
                                previewWithoutGlasses: previewWithoutGlasses)

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

    // MARK: Trial

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            pair = nil
            parameters = nil
            return
        }
        let made = StereogramField.make(for: trial, exercise: exercise,
                                        calibration: calibration)
        parameters = made.parameters
        pair = made.pair
    }
}
