//
//  StarTracerAndViewingViews.swift
//
//  D1 Balanced Viewing and G5 Star Tracer.
//
//  docs/03-EXERCISE-CATALOG.md D1, G5.
//

import SwiftUI

// MARK: - D1 Balanced Viewing

@MainActor
struct BalancedViewingView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = BalancedViewingExercise()

    @State private var elements: [GamePhysics.Body] = []
    @State private var lastTick: Date?
    @State private var accumulator: Double = 0
    @State private var viewedSeconds: Double = 0
    @State private var checkInVisible = false

    private var field: GameField { GameField(calibration: calibration) }
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "sparkles.tv",
            instructions: "Just watch. The scene is dimmed for your stronger eye so the weaker one has to join in. Every so often a shape appears that only one eye can see — tap which shape it was.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or both eyes see the same scene and nothing is rebalanced."),
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
            VStack(spacing: Spacing.lg) {
                Spacer()
                TimelineView(.animation(minimumInterval: GamePhysics.timestep)) { timeline in
                    Canvas { context, _ in
                        advance(to: timeline.date)
                        draw(in: context, trial: trial, difficulty: level)
                    }
                    .frame(width: field.widthPoints, height: field.heightPoints)
                }
                .background(neutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .accessibilityLabel("A slowly drifting scene")

                if checkInVisible {
                    Text("Which shape appeared?")
                        .font(TypeScale.callout())
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
                    Text("Keep watching…")
                        .font(TypeScale.caption())
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
        }
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            elements = []
            return
        }
        elements = exercise.sceneElements(for: trial)
        lastTick = nil
        accumulator = 0
        viewedSeconds = 0
        checkInVisible = false
    }

    private func advance(to now: Date) {
        guard runner.phase.acceptsResponses else { return }
        let elapsed = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        accumulator = min(accumulator + elapsed, 0.25)

        while accumulator >= GamePhysics.timestep {
            accumulator -= GamePhysics.timestep
            viewedSeconds += GamePhysics.timestep
            elements = elements.map { GamePhysics.step($0, in: field) }
        }

        // The check-in window opens after the viewing stretch and stays open
        // long enough to answer. Outside it there is nothing to answer, which is
        // what makes the viewing restful rather than a test.
        let start = BalancedViewingExercise.secondsBetweenCheckIns
        let end = start + BalancedViewingExercise.checkInSeconds
        checkInVisible = viewedSeconds >= start && viewedSeconds <= end + 30
    }

    private func draw(in context: GraphicsContext, trial: Trial,
                      difficulty: GameDifficulty) {
        // The scene: both eyes, with the fellow eye's contrast reduced. This IS
        // the therapy — sustained binocular viewing with the balance shifted.
        let sceneColour = colour(actor: level(GameDifficulty.actorContrast),
                                 context: level(difficulty.fellowContrast))
        for element in elements {
            let centre = field.point(element.position)
            let size = field.points(element.size)
            context.fill(Path(ellipseIn: CGRect(x: centre.x - size / 2,
                                                y: centre.y - size / 2,
                                                width: size, height: size)),
                         with: .color(sceneColour))
        }

        // The check-in symbol: amblyopic eye only, and only during its window.
        let start = BalancedViewingExercise.secondsBetweenCheckIns
        let end = start + BalancedViewingExercise.checkInSeconds
        guard viewedSeconds >= start, viewedSeconds <= end else { return }

        let symbolColour = colour(actor: level(GameDifficulty.actorContrast),
                                  context: AnaglyphCompositor.layerMidpoint)
        let side = field.points(3.0)
        let rect = CGRect(x: field.widthPoints / 2 - side / 2,
                          y: field.heightPoints / 2 - side / 2,
                          width: side, height: side)
        var path = Path()
        switch exercise.shape(for: trial) {
        case .square: path.addRect(rect)
        case .circle: path.addEllipse(in: rect)
        case .triangle:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        case .diamond:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
        context.fill(path, with: .color(symbolColour))
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

// MARK: - G5 Star Tracer

@MainActor
struct StarTracerView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = StarTracerExercise()

    @State private var stars: [CGPoint] = []
    @State private var joined: Int = 0
    @State private var settled = false

    private var field: GameField { GameField(calibration: calibration) }
    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "sparkles",
            instructions: "Tap the stars one at a time to join them up. Only one eye can see the stars, and the other sees the lines you have already drawn — so keep both open.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or one eye sees everything and the joining is trivial."),
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
                Canvas { context, _ in
                    draw(in: context, difficulty: level)
                }
                .frame(width: field.widthPoints, height: field.heightPoints)
                .background(neutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    tap(at: value.location)
                })
                .accessibilityLabel("Stars to join in order")

                Text("\(joined) of \(stars.count) joined")
                    .font(TypeScale.caption())
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, Spacing.sm)
                Spacer()
            }
        }
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else {
            stars = []
            return
        }
        stars = exercise.stars(for: trial)
        joined = 0
        settled = false
    }

    /// A wrong star ends the trial as a failure; the full sequence ends it as a
    /// success. Taps on empty space are ignored, so a stray finger is not scored
    /// — the same rule as Hidden Half.
    private func tap(at location: CGPoint) {
        guard !settled, runner.phase.acceptsResponses else { return }
        let degrees = CGPoint(x: location.x / field.pointsPerDegree,
                              y: location.y / field.pointsPerDegree)
        guard let index = StarTracerExercise.star(at: degrees, in: stars) else { return }

        if index == joined {
            joined += 1
            if joined == stars.count {
                settled = true
                // The star COUNT means "completed". No star index can equal it,
                // so a re-tap can never be mistaken for finishing.
                runner.respond(answer: stars.count)
            }
        } else {
            settled = true
            runner.respond(answer: index)          // wrong star: scored as such
        }
    }

    private func draw(in context: GraphicsContext, difficulty: GameDifficulty) {
        // Lines already drawn: fellow eye. They are the record of progress.
        if joined > 1 {
            let lineColour = colour(actor: AnaglyphCompositor.layerMidpoint,
                                    context: level(difficulty.fellowContrast))
            var path = Path()
            path.move(to: field.point(stars[0]))
            for index in 1..<joined {
                path.addLine(to: field.point(stars[index]))
            }
            context.stroke(path, with: .color(lineColour), lineWidth: 3)
        }

        // Stars: amblyopic eye. They are what must be found.
        let starColour = colour(actor: level(GameDifficulty.actorContrast),
                                context: AnaglyphCompositor.layerMidpoint)
        let joinedColour = colour(actor: level(0.35),
                                  context: AnaglyphCompositor.layerMidpoint)
        let size = field.points(StarTracerExercise.starDegrees)
        for (index, star) in stars.enumerated() {
            let centre = field.point(star)
            let rect = CGRect(x: centre.x - size / 2, y: centre.y - size / 2,
                              width: size, height: size)
            context.fill(Path(ellipseIn: rect),
                         with: .color(index < joined ? joinedColour : starColour))
        }
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
