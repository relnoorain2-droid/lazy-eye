//
//  FindItView.swift
//
//  M12 Find It. The answer is a LOCATION rather than a button, so this is the
//  first exercise where the stimulus is also the response surface.
//
//  THE TOUCH-TARGET PROBLEM, WHICH IS A MEASUREMENT PROBLEM.
//  At 40 items the shapes are small, and a miss could mean "did not find it" or
//  "found it and mistapped". Those are different things and only one of them is
//  visual. So a tap resolves to the NEAREST item within a generous radius rather
//  than requiring a hit inside the glyph, and taps landing on empty space are
//  ignored entirely rather than scored as wrong. Scoring a fat-finger error as a
//  search failure would make the threshold partly a measure of finger size.
//
//  docs/03-EXERCISE-CATALOG.md M12, docs/05-DESIGN-SYSTEM.md section 5.
//

import SwiftUI

@MainActor
struct FindItView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = FindItExercise()

    @State private var items: [SearchItem] = []
    @State private var parameters: SearchFieldParameters?

    var body: some View {
        Group {
            switch runner.phase {
            case .ready:
                readyState.sessionBackdrop()

            case .presenting, .feedback:
                // The stimulus is the control here — the answer is given by
                // tapping the field itself — so the stage carries the chrome
                // (countdown, how-to, pause, fatigue) and no answer bar.
                ExerciseStage(
                    title: runner.descriptor.title,
                    secondsRemaining: runner.secondsRemaining,
                    secondsTotal: runner.plannedSessionSeconds,
                    descriptor: runner.descriptor,
                    onPause: { runner.pause() },
                    onFatigue: { runner.reportFatigue() }
                ) {
                    trialState
                }

            case .onBreak(let remaining):
                BreakCard(secondsRemaining: remaining).sessionBackdrop()

            case .paused:
                pausedState.sessionBackdrop()

            case .finished(let reason):
                SessionSummaryView(runner: runner, reason: reason) { onFinish(reason) }
            }
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
        .onDisappear { runner.stop() }
    }

    // MARK: States

    private var readyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            Text(runner.descriptor.title).font(TypeScale.displayLarge())

            Text("Lots of shapes will appear. All of them point the same way except one. Tap the odd one out.")
                .font(TypeScale.body())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            EvidenceBadge(tier: runner.descriptor.evidenceTier)

            AmblyoButton(title: "Start", systemImage: "play.fill") { runner.start() }
        }
        .padding(Spacing.lg)
        .readableContentWidth()
    }

    @ViewBuilder
    private var trialState: some View {
        if let parameters {
            VStack {
                Spacer()
                ZStack(alignment: .topLeading) {
                    Color.surfaceRaised.opacity(0.35)

                    ForEach(items) { item in
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: parameters.itemPoints * 0.8))
                            .foregroundStyle(Color.textPrimary)
                            .rotationEffect(.degrees(item.rotationDegrees))
                            .position(x: item.x, y: item.y)
                            .accessibilityHidden(true)
                    }

                    if case .feedback(let correct) = runner.phase {
                        Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(correct ? Color.success : Color.textSecondary)
                            .position(x: parameters.fieldPoints / 2,
                                      y: parameters.fieldPoints / 2)
                    }
                }
                .frame(width: parameters.fieldPoints, height: parameters.fieldPoints)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in handleTap(at: value.location) }
                )
                .accessibilityLabel("Search field with \(items.count) shapes")

                Spacer()
                Text("Tap the shape pointing a different way")
                    .font(TypeScale.callout())
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 96)
            }
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

    // MARK: Trial

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            items = []
            parameters = nil
            return
        }
        let p = exercise.parameters(for: trial, calibration: calibration)
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("seed")))
        items = SearchFieldGenerator.makeItems(p, generator: &generator)
        parameters = p
    }

    /// Resolves a tap to the nearest item, or ignores it.
    ///
    /// The generous radius and the ignore-empty-space rule are both deliberate —
    /// see the file header. A missed tap must not be recorded as a failure to
    /// find, or the threshold measures dexterity as well as search.
    private func handleTap(at location: CGPoint) {
        guard runner.phase.acceptsResponses, let parameters else { return }

        let radius = max(parameters.itemPoints, Layout.minTouchTarget) * 0.9
        var nearest: SearchItem?
        var nearestDistance = Double.greatestFiniteMagnitude

        for item in items {
            let dx = item.x - location.x
            let dy = item.y - location.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = item
            }
        }

        guard let nearest, nearestDistance <= radius else { return }
        // The runner's answer index is unused by this exercise, so correctness
        // is expressed by matching or not matching the stored correct answer.
        runner.respond(answer: nearest.isTarget ? 0 : 1)
    }
}
