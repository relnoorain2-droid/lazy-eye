//
//  StereogramField.swift
//
//  The random-dot stereogram canvas, extracted so that D6 and the Check-in draw
//  the SAME stimulus rather than two that resemble each other.
//
//  WHY IT WAS EXTRACTED RATHER THAN REIMPLEMENTED.
//  The check-in borrows registered exercises on purpose — the whole reason
//  `AssessmentBattery.exerciseID(for:)` exists is so that the number on the
//  Progress chart is measured with the same thing the user trains on. A second
//  stereogram renderer written for the assessment would break exactly that
//  guarantee, silently, and the two would drift the first time either was
//  touched. So the drawing moved here and both callers use it.
//
//  THE COLOUR RULES ARE NOT STYLE AND MUST TRAVEL WITH THE DRAWING.
//  A dot in the same position in both fields is common to the two images and
//  must be bright to BOTH eyes; most of the field is common, since only the
//  shape region differs. Get that wrong and the entire background flickers
//  between the eyes and swamps the disparity being measured. Keeping it in the
//  view that draws the dots is what stops a caller from reinventing it badly.
//
//  docs/03-EXERCISE-CATALOG.md D6, docs/16-EXERCISE-STAGE-SPEC.md.
//

import SwiftUI

@MainActor
struct StereogramField: View {

    let pair: StereogramPair
    let parameters: StereogramParameters
    let calibration: CalibrationProfile
    /// Renders both layers plainly so the exercise can be evaluated without
    /// glasses. Labelled on screen wherever it is offered — App Review needs
    /// this, and so does anyone whose glasses have gone missing.
    var previewWithoutGlasses: Bool = false

    private var compositor: AnaglyphCompositor {
        AnaglyphCompositor(calibration: calibration)
    }

    var body: some View {
        Canvas { context, _ in draw(in: context) }
            .frame(width: pair.fieldPoints, height: pair.fieldPoints)
            .background(backgroundColour)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityLabel(previewWithoutGlasses
                ? "Preview with the hidden shape outlined"
                : "Speckled field. Name the shape that stands out.")
    }

    /// The compositor's midpoint. Compositing assumes both layers sit around it,
    /// and any other background silently changes the effective contrast of every
    /// dot in the field.
    private var backgroundColour: Color {
        colour(amblyopic: AnaglyphCompositor.layerMidpoint,
               fellow: AnaglyphCompositor.layerMidpoint)
    }

    private func draw(in context: GraphicsContext) {
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
}

// MARK: - Building one from a trial

extension StereogramField {

    /// Builds the field for a trial, or nil when there is no trial to draw.
    ///
    /// Static and side-effect free so both the training screen and the check-in
    /// derive the stimulus the same way, from the same seed, with no shared
    /// state between them.
    static func make(for trial: Trial,
                     exercise: DepthPopExercise,
                     calibration: CalibrationProfile)
    -> (pair: StereogramPair, parameters: StereogramParameters) {
        let built = exercise.parameters(for: trial, calibration: calibration)
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("seed")))
        return (StereogramGenerator.make(built, generator: &generator), built)
    }
}
