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

    // The dots, the generators and the frame clock moved into `BalanceField`
    // when the Check-in needed the same animation. This view keeps only what it
    // decides: which fields to show, and the seeds that make a trial replayable.
    @State private var seeds: (signal: UInt64, noise: UInt64) = (1, 2)
    @State private var signalField: KinematogramParameters?
    @State private var noiseField: KinematogramParameters?

    // The compositor moved to `BalanceField` with the drawing that used it.

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

                // Animated by the SHARED field, which the Check-in also uses.
                // Two copies of a moving anaglyph stimulus would have drifted,
                // and the balance sub-test's number is compared against this
                // screen's over months.
                BalanceField(signal: signalField,
                             noise: noiseField,
                             calibration: calibration,
                             signalSeed: seeds.signal,
                             noiseSeed: seeds.noise)

                Spacer()
                directionButtons.padding(.horizontal, Spacing.lg).padding(.bottom, 96)
            }
        }
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
            Image(systemName: direction.systemImage)
                .font(.system(size: 24))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!runner.phase.acceptsResponses)
        .accessibilityLabel(direction.label)
    }

    // MARK: Trial

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            signalField = nil; noiseField = nil
            return
        }
        let signal = exercise.signalField(for: trial, calibration: calibration)
        let noise = exercise.noiseField(for: trial, calibration: calibration)

        // Separate seeds so the two fields are independent. Sharing one would
        // correlate the noise with the signal, and correlated noise is not noise.
        seeds = (UInt64(trial.payload.value("signalSeed")),
                 UInt64(trial.payload.value("noiseSeed")))
        signalField = signal
        noiseField = noise
    }
}
