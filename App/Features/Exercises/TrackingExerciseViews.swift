//
//  TrackingExerciseViews.swift
//
//  M9 Follow the Dot, M10 Quick Taps, M13 Stay on the Path.
//
//  All three share `ExerciseScaffold` below rather than re-implementing the
//  ready/break/paused/finished states. That scaffold is where the fatigue button
//  and break card live, and duplicating it per exercise is how one of them ends
//  up without a fatigue button.
//

import SwiftUI

// MARK: - Shared scaffold

/// Wraps an exercise's live content with every non-negotiable session state.
@MainActor
struct ExerciseScaffold<Content: View>: View {

    let runner: SessionRunner
    let icon: String
    let instructions: String
    var warning: (title: String, message: String)?
    var onFinish: (EndReason) -> Void
    @ViewBuilder var content: () -> Content

    // THIS ONE REWRITE COVERS FOURTEEN EXERCISE VIEWS.
    //
    // Every game and most dichoptic exercises render through this scaffold, so
    // after the first device test — "the visuals are very bad, none of them
    // proper" — this was the highest-leverage file in the project. Migrating 25
    // individual views would have been 25 chances to leave one behind; this is
    // one place, and nothing can miss it.
    //
    // What changed: the grey no longer covers the entire screen (it was there
    // because the monocular stimuli need it, and it was applied to every state
    // including the ready and paused screens, which have no stimulus at all),
    // the timer is a ring rather than absent, and there is a "how to" button.
    //
    // What did NOT change: the fatigue button, the break card, the cap, the
    // honest summary. Those were the reason this scaffold was written and they
    // survive the visual change untouched.
    var body: some View {
        Group {
            switch runner.phase {
            case .ready:
                readyState.sessionBackdrop()

            case .presenting, .feedback:
                // No answer bar: in these exercises the stimulus IS the control.
                // You tap the balloon, not a button underneath it.
                ExerciseStage(
                    title: runner.descriptor.title,
                    secondsRemaining: runner.secondsRemaining,
                    secondsTotal: runner.plannedSessionSeconds,
                    descriptor: runner.descriptor,
                    onPause: { runner.pause() },
                    onFatigue: { runner.reportFatigue() }
                ) {
                    content()
                }

            case .onBreak(let remaining):
                BreakCard(secondsRemaining: remaining).sessionBackdrop()

            case .paused:
                pausedState.sessionBackdrop()

            case .finished(let reason):
                SessionSummaryView(runner: runner, reason: reason) { onFinish(reason) }
            }
        }
        .onDisappear { runner.stop() }
    }

    private var readyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            Text(runner.descriptor.title).font(TypeScale.displayLarge())

            Text(instructions)
                .font(TypeScale.body())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            EvidenceBadge(tier: runner.descriptor.evidenceTier)

            if let warning {
                SafetyBanner(level: .info, title: warning.title,
                             message: warning.message)
            }

            AmblyoButton(title: "Start", systemImage: "play.fill") { runner.start() }
        }
        .padding(Spacing.lg)
        .readableContentWidth()
    }

    private var pausedState: some View {
        VStack(spacing: Spacing.lg) {
            Text("Paused").font(TypeScale.title())
            Text("Your progress is saved.")
                .font(TypeScale.callout())
                .foregroundStyle(Color.textSecondary)
            AmblyoButton(title: "Continue", systemImage: "play.fill") { runner.resume() }
            AmblyoButton(title: "Finish session", style: .tertiary) { runner.stopEarly() }
        }
        .padding(Spacing.lg)
        .readableContentWidth()
    }
}

// MARK: - M9 · Follow the Dot

@MainActor
struct SmoothPursuitView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = SmoothPursuitExercise()

    @State private var path: PursuitPath?
    @State private var startedAt: Date = .now
    @State private var hasChanged = false
    @State private var changedAt: Date?
    @State private var answered = false

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "circle.dashed",
            instructions: "A dot will move around a loop. Follow it with your eyes, and tap anywhere the moment it changes colour.",
            onFinish: onFinish
        ) {
            content
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
    }

    @ViewBuilder
    private var content: some View {
        if let path {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                let position = path.position(at: elapsed)
                let changed = elapsed >= changeDelay

                Canvas { context, _ in
                    let colour = changed ? Color.brandAccent : Color.brandPrimary
                    let d = path.targetDiameterPoints
                    context.fill(
                        Path(ellipseIn: CGRect(x: position.x - d / 2, y: position.y - d / 2,
                                               width: d, height: d)),
                        with: .color(colour))
                }
                .frame(width: path.canvasPoints, height: path.canvasPoints)
                .onChange(of: changed) { _, isChanged in
                    // Record the moment it turned, so a late tap can be judged.
                    if isChanged && changedAt == nil { changedAt = timeline.date }
                    hasChanged = isChanged
                    expireIfWindowPassed(now: timeline.date)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { registerTap() }
            .accessibilityLabel("Moving target. Tap when it changes colour.")
        }
    }

    private var changeDelay: Double {
        runner.currentTrial?.payload.value("changeDelay", default: 2) ?? 2
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else { path = nil; return }
        path = exercise.path(for: trial, calibration: calibration)
        startedAt = .now
        hasChanged = false
        changedAt = nil
        answered = false
    }

    /// A tap before the colour change is a false alarm; after it, within the
    /// window, is correct.
    private func registerTap() {
        guard runner.phase.acceptsResponses, !answered else { return }
        answered = true
        runner.respond(answer: hasChanged ? 0 : 1)
    }

    /// Missing the change entirely is a miss, not an absence of data — otherwise
    /// someone who never looks at the screen produces no wrong answers at all.
    private func expireIfWindowPassed(now: Date) {
        guard runner.phase.acceptsResponses, !answered, let changedAt else { return }
        if now.timeIntervalSince(changedAt) > SmoothPursuitExercise.responseWindowSeconds {
            answered = true
            runner.respond(answer: 1)
        }
    }
}

// MARK: - M10 · Quick Taps

@MainActor
struct JumpTargetsView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    @State private var target: SaccadeTarget?
    @State private var fieldPoints: Double = 300
    @State private var shownAt: Date = .now
    @State private var answered = false

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "target",
            instructions: "A dot will appear somewhere on the square. Tap it as fast as you can, then look back at the centre.",
            onFinish: onFinish
        ) {
            content
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
    }

    @ViewBuilder
    private var content: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height - 140)
            ZStack {
                Color.surfaceRaised.opacity(0.3)

                // Fixation point: the saccade has to start from somewhere known,
                // or the eccentricity being measured is not the one presented.
                Circle()
                    .fill(Color.textSecondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .position(x: side / 2, y: side / 2)
                    .accessibilityHidden(true)

                if let target, runner.phase.acceptsResponses {
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: target.diameterPoints, height: target.diameterPoints)
                        .position(x: target.x, y: target.y)
                        .accessibilityLabel("Target")
                }

                if case .feedback(let correct) = runner.phase {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(correct ? Color.success : Color.textSecondary)
                        .position(x: side / 2, y: side / 2)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { handleTap(at: $0.location) })
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 40)
            .onAppear {
                fieldPoints = side
                beginTrial()
            }
        }
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else { target = nil; return }
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("seed")))
        target = SaccadeGenerator.makeTarget(
            eccentricityDegrees: trial.payload.value("eccentricityDegrees", default: 1.5),
            pointsPerDegree: calibration.points(forDegrees: 1.0),
            fieldPoints: fieldPoints,
            id: 0,
            generator: &generator)
        shownAt = .now
        answered = false
    }

    /// A hit inside the target is correct. A tap elsewhere, or one slower than
    /// the window, is a miss.
    private func handleTap(at location: CGPoint) {
        guard runner.phase.acceptsResponses, !answered, let target else { return }
        answered = true

        let dx = target.x - location.x, dy = target.y - location.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let inTime = Date.now.timeIntervalSince(shownAt)
            <= JumpTargetsExercise.responseWindowSeconds
        let hit = distance <= target.diameterPoints / 2 + 8

        runner.respond(answer: (hit && inTime) ? 0 : 1)
    }
}

// MARK: - M13 · Stay on the Path

@MainActor
struct PathTracerView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = PathTracerExercise()

    @State private var path: TracePath?
    @State private var progress: Double = 0
    @State private var strayed = false
    @State private var answered = false
    @State private var canvasSide: Double = 300

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "scribble",
            instructions: "Put your finger on the left end of the path and drag along it to the right end without going outside the band.",
            onFinish: onFinish
        ) {
            content
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
    }

    @ViewBuilder
    private var content: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width - 24, geometry.size.height - 160)
            ZStack {
                if let path {
                    // The corridor itself, drawn as a thick stroke.
                    Path { p in
                        guard let first = path.points.first else { return }
                        p.move(to: first)
                        for point in path.points.dropFirst() { p.addLine(to: point) }
                    }
                    .stroke(strayed ? Color.caution.opacity(0.35)
                                    : Color.brandPrimary.opacity(0.28),
                            style: StrokeStyle(lineWidth: path.corridorWidthPoints,
                                               lineCap: .round, lineJoin: .round))

                    // Centre line, so the target is unambiguous at narrow widths.
                    Path { p in
                        guard let first = path.points.first else { return }
                        p.move(to: first)
                        for point in path.points.dropFirst() { p.addLine(to: point) }
                    }
                    .stroke(Color.brandPrimary.opacity(0.7), lineWidth: 1.5)

                    if let start = path.points.first {
                        Circle().fill(Color.success)
                            .frame(width: 18, height: 18).position(start)
                    }
                    if let end = path.points.last {
                        Circle().strokeBorder(Color.success, lineWidth: 3)
                            .frame(width: 22, height: 22).position(end)
                    }
                }

                if case .feedback(let correct) = runner.phase {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(correct ? Color.success : Color.textSecondary)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { follow($0.location) }
                    .onEnded { _ in finishTrace() }
            )
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 50)
            .onAppear {
                canvasSide = side
                beginTrial()
            }
            .accessibilityLabel("Trace the path from left to right")
        }
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else { path = nil; return }
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("seed")))
        path = exercise.path(for: trial, calibration: calibration,
                             canvasPoints: canvasSide, generator: &generator)
        progress = 0
        strayed = false
        answered = false
    }

    /// Tracks how far along the path the finger has reached, and whether it ever
    /// left the corridor. Straying is remembered rather than ending the trial
    /// immediately, so a slip near the end still shows the user where it went
    /// wrong instead of the screen simply changing.
    private func follow(_ location: CGPoint) {
        guard runner.phase.acceptsResponses, let path, !answered else { return }

        if path.distance(to: location) > path.corridorWidthPoints / 2 {
            strayed = true
        }
        if let last = path.points.last, let first = path.points.first {
            let span = max(1, last.x - first.x)
            progress = min(1, max(0, (location.x - first.x) / span))
        }
    }

    private func finishTrace() {
        guard runner.phase.acceptsResponses, !answered else { return }
        // Lifting off before the end is not a correct trace, but it is also not
        // a stray — treated as incorrect either way, and the distinction is kept
        // in the trial record via the difficulty value.
        answered = true
        runner.respond(answer: (!strayed && progress > 0.92) ? 0 : 1)
    }
}
