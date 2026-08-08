//
//  MotionFieldView.swift
//
//  M7 Motion Field. The first exercise with a moving stimulus, so it cannot use
//  the static `ChoiceExerciseView` shell — but it reuses every piece of session
//  chrome, so the fatigue button, break card, cap and honest summary behave
//  identically. That reuse is the point: those are safety behaviours, and a
//  bespoke screen is exactly where one would go missing.
//
//  WHY Canvas AND TimelineView RATHER THAN A CGImage PER FRAME
//  200 dots at 60 fps is 12,000 draws a second. Rebuilding a bitmap for each
//  frame would allocate ~700 MB/minute and drop frames; `Canvas` draws straight
//  into the display list. Dropped frames matter here beyond smoothness - a
//  motion stimulus that stutters is presenting a different speed than the one
//  being measured, so a dropped frame invalidates the trial.
//
//  docs/04-ARCHITECTURE.md sections 4 and 5, docs/03-EXERCISE-CATALOG.md M7.
//

import SwiftUI

@MainActor
struct MotionFieldView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = MotionFieldExercise()

    @State private var dots: [KinematogramDot] = []
    @State private var parameters: KinematogramParameters?
    @State private var generator = SeededGenerator(seed: 1)
    @State private var lastFrame: Date = .distantPast

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.stimulusNeutral.ignoresSafeArea()

            switch runner.phase {
            case .ready:
                readyState
            case .presenting, .feedback:
                trialState
            case .onBreak(let remaining):
                BreakCard(secondsRemaining: remaining)
            case .paused:
                pausedState
            case .finished(let reason):
                SessionSummaryView(runner: runner, reason: reason) { onFinish(reason) }
            }
        }
        .overlay(alignment: .bottom) { controls }
        .statusBarHidden(runner.phase.acceptsResponses)
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
        .onDisappear { runner.stop() }
    }

    // MARK: States

    private var readyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 48))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            Text(runner.descriptor.title).font(TypeScale.displayLarge())

            Text("A cloud of dots will drift. Most move randomly — some drift together. Say which way that drift goes, and guess when you can't tell.")
                .font(TypeScale.body())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            EvidenceBadge(tier: runner.descriptor.evidenceTier)

            if reduceMotion {
                // Honest rather than silently degraded: this exercise IS motion,
                // so there is no meaningful reduced-motion variant. Saying so
                // beats presenting something that no longer measures motion.
                SafetyBanner(
                    level: .info,
                    title: "This one uses movement",
                    message: "You have Reduce Motion on. This exercise needs moving dots, so it will still move. Skip it if that's uncomfortable."
                )
            }

            AmblyoButton(title: "Start", systemImage: "play.fill") { runner.start() }
        }
        .padding(Spacing.lg)
        .readableContentWidth()
    }

    private var trialState: some View {
        VStack(spacing: 0) {
            Spacer()

            if let parameters, runner.phase.acceptsResponses {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    Canvas { context, size in
                        advanceIfNeeded(to: timeline.date)
                        draw(in: context, size: size, parameters: parameters)
                    }
                    .frame(width: parameters.fieldPoints, height: parameters.fieldPoints)
                }
                .accessibilityHidden(true)
            } else if case .feedback(let correct) = runner.phase {
                Image(systemName: correct ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 44))
                    .foregroundStyle(correct ? Color.success : Color.textSecondary)
                    .frame(width: parameters?.fieldPoints ?? 200,
                           height: parameters?.fieldPoints ?? 200)
                    .accessibilityLabel(correct ? "Correct" : "Not that one")
            }

            Spacer()
            directionButtons.padding(.horizontal, Spacing.lg).padding(.bottom, 96)
        }
    }

    /// A cross layout, so the button positions match the directions they mean.
    /// A 2x2 grid would put "up" next to "right" and cost a moment's thought on
    /// every trial — thought that would be measured as slower motion perception.
    private var directionButtons: some View {
        VStack(spacing: Spacing.sm) {
            button(.up)
            HStack(spacing: Spacing.sm) {
                button(.left)
                button(.right)
            }
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
                .frame(height: 60)
                .background(Color.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!runner.phase.acceptsResponses)
        .accessibilityLabel(label(for: direction))
    }

    private func icon(for direction: KinematogramParameters.Direction) -> String {
        switch direction {
        case .up: "arrow.up"
        case .right: "arrow.right"
        case .down: "arrow.down"
        case .left: "arrow.left"
        }
    }

    private func label(for direction: KinematogramParameters.Direction) -> String {
        switch direction {
        case .up: "Up"
        case .right: "Right"
        case .down: "Down"
        case .left: "Left"
        }
    }

    private var pausedState: some View {
        VStack(spacing: Spacing.lg) {
            Text("Paused").font(TypeScale.title())
            AmblyoButton(title: "Continue", systemImage: "play.fill") { runner.resume() }
            AmblyoButton(title: "Finish session", style: .tertiary) { runner.stopEarly() }
        }
        .padding(Spacing.lg)
        .readableContentWidth()
    }

    @ViewBuilder
    private var controls: some View {
        if !runner.phase.isTerminal && runner.phase != .ready {
            SessionControlCapsule(onFatigue: { runner.reportFatigue() },
                                  onPause: { runner.pause() })
                .padding(.bottom, Spacing.md)
        }
    }

    // MARK: Animation

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            parameters = nil
            dots = []
            return
        }
        let p = exercise.parameters(for: trial, calibration: calibration)
        // Seeded from the trial so the exact dot field can be reproduced from
        // the stored record when someone reports a bad trial.
        generator = SeededGenerator(seed: UInt64(trial.payload.value("seed")))
        dots = KinematogramGenerator.makeDots(p, generator: &generator)
        parameters = p
        lastFrame = .distantPast
    }

    /// Advances at most one step per frame. `TimelineView(.animation)` can fire
    /// more often than the display refreshes on ProMotion, and stepping twice in
    /// one frame would double the presented speed.
    private func advanceIfNeeded(to date: Date) {
        guard let parameters else { return }
        guard date.timeIntervalSince(lastFrame) >= 1.0 / 70.0 else { return }
        lastFrame = date
        KinematogramGenerator.advance(&dots, parameters: parameters, generator: &generator)
    }

    private func draw(in context: GraphicsContext, size: CGSize,
                      parameters p: KinematogramParameters) {
        let colour = Color(white: 0.5 - 0.5 * p.contrast)
        let diameter = p.dotDiameterPoints
        for dot in dots {
            let rect = CGRect(x: dot.x - diameter / 2, y: dot.y - diameter / 2,
                              width: diameter, height: diameter)
            context.fill(Path(ellipseIn: rect), with: .color(colour))
        }
    }
}
