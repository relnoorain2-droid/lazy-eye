//
//  BalanceMeterView.swift
//
//  D5's session screen, and the first view that composites two eyes into one
//  frame. Every dichoptic exercise after this reuses the pattern.
//
//  WHY BOTH FIELDS DRAW INTO ONE Canvas
//  The two eyes' layers must be combined PER PIXEL, because the crosstalk
//  cancellation subtracts one from the other. Drawing them as two stacked
//  SwiftUI views would blend them with the system compositor, which knows nothing
//  about the correction — the leak would come straight back. So both dot fields
//  are rasterised into the same context and every dot's colour comes from
//  `AnaglyphCompositor`.
//
//  NOT VERIFIED THROUGH REAL GLASSES. See AnaglyphCompositor's header.
//

import SwiftUI

@MainActor
struct BalanceMeterView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = BalanceMeterExercise()

    @State private var signalDots: [KinematogramDot] = []
    @State private var noiseDots: [KinematogramDot] = []
    @State private var signalField: KinematogramParameters?
    @State private var noiseField: KinematogramParameters?
    @State private var signalGenerator = SeededGenerator(seed: 1)
    @State private var noiseGenerator = SeededGenerator(seed: 2)
    @State private var lastFrame: Date = .distantPast

    private var compositor: AnaglyphCompositor {
        AnaglyphCompositor(calibration: calibration)
    }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "eye.trianglebadge.exclamationmark",
            instructions: "With your glasses on, some dots drift together while the rest move at random. Say which way the drift goes. It gets harder as it goes — guessing is expected.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or the two eyes will not be separated properly."),
            onFinish: onFinish
        ) {
            content
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
    }

    @ViewBuilder
    private var content: some View {
        if let signalField, let noiseField {
            VStack(spacing: 0) {
                Spacer()

                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    Canvas { context, _ in
                        advanceIfNeeded(to: timeline.date,
                                        signal: signalField, noise: noiseField)
                        draw(in: context, signal: signalField, noise: noiseField)
                    }
                    .frame(width: signalField.fieldPoints, height: signalField.fieldPoints)
                }
                .background(backgroundColour)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .accessibilityLabel("Two-eye dot field")

                Spacer()
                directionButtons.padding(.horizontal, Spacing.lg).padding(.bottom, 96)
            }
        }
    }

    /// The background must be the compositor's midpoint, not black or grey.
    /// Compositing assumes both layers sit around that midpoint; a different
    /// background would shift the effective contrast of every dot and the
    /// cancellation would be tuned against the wrong reference.
    private var backgroundColour: Color {
        let pixel = compositor.composite(amblyopic: 0.5, fellow: 0.5)
        return Color(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }

    private var directionButtons: some View {
        VStack(spacing: Spacing.sm) {
            button(.up)
            HStack(spacing: Spacing.sm) { button(.left); button(.right) }
            button(.down)
        }
    }

    private func button(_ direction: KinematogramParameters.Direction) -> some View {
        Button {
            runner.respond(answer: direction.rawValue)
        } label: {
            Image(systemName: icon(for: direction))
                .font(.system(size: 24))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!runner.phase.acceptsResponses)
        .accessibilityLabel(label(for: direction))
    }

    private func icon(for d: KinematogramParameters.Direction) -> String {
        switch d {
        case .up: "arrow.up"
        case .right: "arrow.right"
        case .down: "arrow.down"
        case .left: "arrow.left"
        }
    }

    private func label(for d: KinematogramParameters.Direction) -> String {
        switch d {
        case .up: "Up"
        case .right: "Right"
        case .down: "Down"
        case .left: "Left"
        }
    }

    // MARK: Trial

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            signalField = nil; noiseField = nil
            signalDots = []; noiseDots = []
            return
        }
        let signal = exercise.signalField(for: trial, calibration: calibration)
        let noise = exercise.noiseField(for: trial, calibration: calibration)

        // Separate seeds so the two fields are independent. Sharing one would
        // correlate the noise with the signal, and correlated noise is not noise.
        signalGenerator = SeededGenerator(seed: UInt64(trial.payload.value("signalSeed")))
        noiseGenerator = SeededGenerator(seed: UInt64(trial.payload.value("noiseSeed")))

        signalDots = KinematogramGenerator.makeDots(signal, generator: &signalGenerator)
        noiseDots = KinematogramGenerator.makeDots(noise, generator: &noiseGenerator)
        signalField = signal
        noiseField = noise
        lastFrame = .distantPast
    }

    private func advanceIfNeeded(to date: Date,
                                 signal: KinematogramParameters,
                                 noise: KinematogramParameters) {
        guard date.timeIntervalSince(lastFrame) >= 1.0 / 70.0 else { return }
        lastFrame = date
        KinematogramGenerator.advance(&signalDots, parameters: signal,
                                      generator: &signalGenerator)
        KinematogramGenerator.advance(&noiseDots, parameters: noise,
                                      generator: &noiseGenerator)
    }

    private func draw(in context: GraphicsContext,
                      signal: KinematogramParameters,
                      noise: KinematogramParameters) {
        let compositor = self.compositor

        // Each field is drawn with the OTHER eye's layer at the midpoint, so a
        // dot only ever brightens the eye it belongs to. Drawing both eyes' dots
        // in one pass with both layers active would let a signal dot and a noise
        // dot land on the same pixel and produce a colour neither eye can read.
        let signalPixel = compositor.composite(
            amblyopic: 0.5 + 0.5 * signal.contrast, fellow: 0.5)
        let noisePixel = compositor.composite(
            amblyopic: 0.5, fellow: 0.5 + 0.5 * noise.contrast)

        let signalColour = Color(red: signalPixel.red,
                                 green: signalPixel.green,
                                 blue: signalPixel.blue)
        let noiseColour = Color(red: noisePixel.red,
                                green: noisePixel.green,
                                blue: noisePixel.blue)

        for dot in noiseDots {
            let d = noise.dotDiameterPoints
            context.fill(Path(ellipseIn: CGRect(x: dot.x - d / 2, y: dot.y - d / 2,
                                                width: d, height: d)),
                         with: .color(noiseColour))
        }
        for dot in signalDots {
            let d = signal.dotDiameterPoints
            context.fill(Path(ellipseIn: CGRect(x: dot.x - d / 2, y: dot.y - d / 2,
                                                width: d, height: d)),
                         with: .color(signalColour))
        }
    }
}
