//
//  SplitMatchView.swift
//
//  D2's screen: a target card above, option cards below, every card split down
//  the middle between the two eyes.
//
//  THE DIVIDING LINE IS DRAWN TO BOTH EYES
//  A faint centre line in the shared layer, so both eyes agree on where the card
//  is and the two halves fuse into one object rather than floating apart. Without
//  it the halves read as two separate marks at slightly different depths, which
//  is a fusion problem the user cannot solve and has nothing to do with the task.
//
//  docs/03-EXERCISE-CATALOG.md D2.
//

import SwiftUI

@MainActor
struct SplitMatchView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = SplitMatchExercise()

    @Environment(\.theme) private var theme

    private var compositor: AnaglyphCompositor { AnaglyphCompositor(calibration: calibration) }

    /// Card size in degrees, converted at draw time. 3° is comfortably tappable
    /// on every device (89 pt on an iPhone SE) and leaves room for six of them.
    private static let cardDegrees: Double = 3.0

    private var cardPoints: Double {
        calibration.points(forDegrees: Self.cardDegrees)
    }

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "square.on.square.dashed",
            instructions: "Each card is half-drawn to one eye and half to the other. Find the card below that matches the one at the top — you need both eyes to see a whole card.",
            warning: calibration.isAnaglyphCalibrated
                ? nil
                : (title: "Glasses not set up",
                   message: "Run the glasses setup first, or one eye sees both halves and the matching is trivial."),
            onFinish: onFinish
        ) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let trial = runner.currentTrial {
            let level = exercise.difficulty(for: trial)
            let target = exercise.target(for: trial)
            let options = exercise.options(for: trial)

            VStack(spacing: Spacing.lg) {
                Spacer()

                VStack(spacing: Spacing.sm) {
                    Text("Match this")
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                    card(target, difficulty: level)
                        .accessibilityLabel("Target card")
                }

                Divider().overlay(Color.separatorLine)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: cardPoints))],
                          spacing: Spacing.md) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            runner.respond(answer: index)
                        } label: {
                            card(option, difficulty: level)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .disabled(!runner.phase.acceptsResponses)
                        .accessibilityLabel("Option \(index + 1)")
                    }
                }
                .padding(.horizontal, Spacing.lg)

                Spacer()
            }
        }
    }

    // MARK: Drawing

    private func card(_ card: SplitMatchExercise.Card,
                      difficulty: GameDifficulty) -> some View {
        Canvas { context, size in
            let background = colour(actor: AnaglyphCompositor.layerMidpoint,
                                    context: AnaglyphCompositor.layerMidpoint)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(background))

            let actorColour = colour(actor: level(GameDifficulty.actorContrast),
                                     context: AnaglyphCompositor.layerMidpoint)
            let contextColour = colour(actor: AnaglyphCompositor.layerMidpoint,
                                       context: level(difficulty.fellowContrast))

            // Left half: amblyopic eye. Right half: fellow eye.
            draw(half: card.leftHalf, in: CGRect(x: 0, y: 0,
                                                 width: size.width / 2, height: size.height),
                 colour: actorColour, context: context)
            draw(half: card.rightHalf, in: CGRect(x: size.width / 2, y: 0,
                                                  width: size.width / 2, height: size.height),
                 colour: contextColour, context: context)

            // The seam, in the SHARED layer, so both eyes agree where the card
            // is and the halves fuse into one object.
            let shared = colour(actor: level(0.25), context: level(0.25))
            var seam = Path()
            seam.move(to: CGPoint(x: size.width / 2, y: size.height * 0.1))
            seam.addLine(to: CGPoint(x: size.width / 2, y: size.height * 0.9))
            context.stroke(seam, with: .color(shared), lineWidth: 1)
        }
        .frame(width: cardPoints, height: cardPoints)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .strokeBorder(Color.separatorLine, lineWidth: 1))
    }

    /// Four distinguishable half-glyphs. Deliberately simple geometry rather
    /// than letters: a letter half is often identifiable on its own, which would
    /// let one eye name the card.
    private func draw(half: Int, in rect: CGRect, colour: Color,
                      context: GraphicsContext) {
        let inset = rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.30)
        var path = Path()
        switch half % SplitMatchExercise.halfCount {
        case 0:
            path.addRect(inset)
        case 1:
            path.addEllipse(in: inset)
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
