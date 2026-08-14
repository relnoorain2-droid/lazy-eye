//
//  StereoExercises.swift
//
//  D6 Depth Pop. The only exercise in the app that CANNOT be done with one eye,
//  by construction rather than by discipline.
//
//  WHY IT IS WORTH ITS OWN FILE
//  Everything else dichoptic here can be part-cheated: a suppressing user can
//  half-solve a matching task with their good eye and guess the rest, and the
//  staircase will happily report a threshold for that guessing. A random-dot
//  stereogram gives each eye uniform noise. There is no shape to find
//  monocularly, so a correct answer is evidence of fusion and an incorrect one
//  is evidence of its absence. That makes this both an exercise and the honest
//  half of the `a.stereo` assessment.
//
//  THE STAIRCASE IS IN ARCMINUTES AND THE DISPLAY IS THE FLOOR
//  One point of horizontal shift is 2.01 arcmin on an iPhone SE at 30 cm and
//  1.26 arcmin on an iPad Pro at 60 cm. Below that there is no shift to make,
//  so `RenderLimit.arcminutes(minimumFeaturePoints: 1)` clamps the bound to
//  what the screen can present. Without it the staircase would descend past the
//  pixel grid, both eyes would receive identical images, and it would converge
//  on a disparity while the user guessed at flat noise — the same silent failure
//  as M13's degrees/arcminutes mix-up.
//
//  WHAT IS RECORDED IS WHAT WAS SHOWN
//  The trial stores `renderedDisparityArcminutes` after quantisation, not the
//  value the staircase asked for. A requested 1.4 arcmin that renders as 2.01 is
//  a 2.01 arcmin trial, and logging the request would put a number in the
//  progress chart that nobody ever saw.
//
//  CROSSTALK MATTERS MORE HERE THAN ANYWHERE
//  With leaky glasses each eye receives some of the other's field. For a
//  contrast-based exercise that degrades the stimulus; for a stereogram it
//  destroys it, because the correlation the visual system needs is between two
//  DIFFERENT images. That is why the glasses self-check exists, and why this
//  exercise is the first thing to look wrong if separation is poor.
//
//  docs/03-EXERCISE-CATALOG.md D6, docs/01-RESEARCH-BRIEF.md section 4.
//

import Foundation

struct DepthPopExercise: Exercise {

    static let descriptor = ExerciseDescriptor(
        id: "d.randomDotStereo",
        title: "Depth Pop",
        track: .dichoptic,
        evidenceTier: .a,
        summary: "A shape hidden in speckle, visible only when both eyes work together. Name the shape.",
        targets: "Depth perception and using both eyes at once",
        defaultDurationSeconds: 240,
        staircase: StaircaseConfiguration(
            dimensionName: "disparity",
            unit: "arcmin",
            // 30 arcmin is unmistakable to anyone with any stereopsis at all,
            // which matters for the first trial: a user who sees nothing on
            // trial one concludes the app is broken rather than that the task
            // is hard.
            startValue: 30,
            // Requested floor. The display almost always binds first, and
            // `renderLimit` is what enforces that.
            hardestValue: 1.0,
            easiestValue: 60,
            polarity: .lowerIsHarder,
            alternatives: 4,
            initialStepSize: 8,
            minimumStepSize: 0.5,
            // ONE POINT of horizontal shift. This is what makes the exercise
            // honest on a phone: below a point there is no disparity to render,
            // only two identical images. It belongs to the STAIRCASE, not the
            // descriptor — the bound is a property of the dimension being
            // measured, not of the exercise as a whole.
            renderLimit: .arcminutes(minimumFeaturePoints: 1.0)
        ),
        safety: SafetyEnvelope(
            // Static field. Nothing moves, nothing flickers.
            maxTemporalRateHz: 0,
            invertsFullFieldLuminance: false,
            maxContrast: AnaglyphCompositor.maximumContrast,
            maxHighContrastAreaFraction: 0.35
        ),
        isFreeTier: false,
        minimumAgeGroup: .fiveToTwelve
    )

    typealias Answer = StereogramParameters.Shape

    /// Field size, held constant across devices. 6.5° fits every supported
    /// screen with room to spare — an iPhone SE gives 29.8 pt/° so 6.5° is
    /// 194 pt against a 320 pt short axis. Holding it constant rather than
    /// filling each screen is what makes a threshold comparable between an
    /// iPhone and an iPad.
    static let fieldDegrees: Double = 6.5

    func makeTrial(difficulty: Double, generator: inout SeededGenerator) -> Trial {
        let shape = Answer.allCases.randomElement(using: &generator) ?? .square
        // Depth direction randomised so nobody answers from the last trial's
        // memory of "it pops forward".
        let depth: StereogramParameters.Depth =
            generator.next() % 2 == 0 ? .nearer : .further

        return Trial(
            difficulty: difficulty,
            correctAnswer: shape.rawValue,
            payload: TrialPayload([
                "disparityArcmin": difficulty,
                "shape": Double(shape.rawValue),
                "depth": Double(depth.rawValue),
                "seed": Double(generator.next() % 1_000_000)
            ])
        )
    }

    func parameters(for trial: Trial,
                    calibration: CalibrationProfile) -> StereogramParameters {
        var parameters = StereogramParameters()
        parameters.shape = Answer(rawValue: Int(trial.payload.value("shape"))) ?? .square
        parameters.depth = StereogramParameters.Depth(
            rawValue: Int(trial.payload.value("depth"))) ?? .nearer
        parameters.disparityArcminutes = trial.payload.value("disparityArcmin")
        parameters.pointsPerDegree = calibration.points(forDegrees: 1.0)
        parameters.fieldPoints = calibration.points(forDegrees: Self.fieldDegrees)
        // Dot size in ANGLE, not points, so a dot is the same visual object on
        // every device: 6 arcmin lands at 3 pt on an iPhone SE and 4.8 pt on an
        // iPad Pro. A fixed point size would make the dots twice as coarse,
        // visually, on the smaller screen.
        parameters.dotPoints = max(2, (calibration.points(forDegrees: 1.0) * 6.0 / 60.0)
            .rounded())
        return parameters
    }

    /// What the trial actually presented, which is what the session records.
    /// Quantisation can only make the disparity coarser, never finer.
    func renderedDisparity(for trial: Trial,
                           calibration: CalibrationProfile) -> Double {
        parameters(for: trial, calibration: calibration).renderedDisparityArcminutes
    }

    /// Plain reading of a converged threshold. Banded, because a single session
    /// on a phone through paper glasses does not support a precise number, and
    /// because stereoacuity is a screening observation here rather than a
    /// diagnosis.
    static func interpretation(disparityArcminutes: Double) -> String {
        switch disparityArcminutes {
        case ..<2: "Fine depth detail — near the limit of what this screen can show"
        case ..<5: "Good depth detail"
        case ..<15: "Moderate depth detail"
        case ..<40: "Coarse depth only"
        default: "No clear depth from this test today"
        }
    }
}
